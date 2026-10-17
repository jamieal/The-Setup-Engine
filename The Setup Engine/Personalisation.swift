import AppKit
import Foundation
import LocalAuthentication

// MARK: - Touch ID

/// Whether Touch ID for `sudo` can be offered on this Mac (#13).
enum TouchIDStatus: Equatable {
    case available          // sensor + at least one fingerprint enrolled
    case alreadyOn          // pam_tid.so is already enabled for sudo
    case noFingerprints     // sensor, but no fingerprint enrolled yet
    case noSensor           // no Touch ID on this Mac (or keyboard not connected)

    static func detect() -> TouchIDStatus {
        if TouchIDForSudo.isEnabled { return .alreadyOn }
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return context.biometryType == .touchID ? .available : .noSensor
        }
        if let code = (error as? LAError)?.code, code == .biometryNotEnrolled {
            return .noFingerprints
        }
        return .noSensor
    }
}

/// Enables Touch ID for `sudo` via /etc/pam.d/sudo_local, which Apple added in
/// macOS 14 and which survives system updates (unlike editing /etc/pam.d/sudo).
nonisolated enum TouchIDForSudo {
    static let line = "auth       sufficient     pam_tid.so"

    static var isEnabled: Bool {
        for file in ["/etc/pam.d/sudo_local", "/etc/pam.d/sudo"] {
            guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let enabled = text.split(separator: "\n").contains { raw in
                let parts = raw.split(whereSeparator: \.isWhitespace)
                return parts.count >= 3 && parts[0] == "auth" && parts[2] == "pam_tid.so"
            }
            if enabled { return true }
        }
        return false
    }

    /// Root shell snippet. Reports `TSE_OK touchid` / `TSE_FAIL touchid`.
    static var rootScript: String {
        """
        if grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_tid\\.so' /etc/pam.d/sudo_local 2>/dev/null; then
            echo 'TSE_OK touchid'
        elif [ -f /etc/pam.d/sudo_local ]; then
            { echo '\(line)'; cat /etc/pam.d/sudo_local; } > /etc/pam.d/sudo_local.tse && \\
            /bin/mv /etc/pam.d/sudo_local.tse /etc/pam.d/sudo_local && \\
            /usr/sbin/chown root:wheel /etc/pam.d/sudo_local && /bin/chmod 444 /etc/pam.d/sudo_local && \\
            echo 'TSE_OK touchid' || echo 'TSE_FAIL touchid'
        elif [ -f /etc/pam.d/sudo_local.template ]; then
            /usr/bin/sed -e 's/^#auth/auth/' /etc/pam.d/sudo_local.template > /etc/pam.d/sudo_local && \\
            /usr/sbin/chown root:wheel /etc/pam.d/sudo_local && /bin/chmod 444 /etc/pam.d/sudo_local && \\
            echo 'TSE_OK touchid' || echo 'TSE_FAIL touchid'
        else
            echo 'TSE_FAIL touchid'
        fi
        """
    }
}

// MARK: - Dock

struct DockItem: Identifiable, Hashable {
    /// Full path the Dock will point at, e.g. "/Applications/Slack.app".
    let path: String
    let name: String
    var homepageURL: String?
    var token: String?
    var included = true

    var id: String { path }
}

enum DockLayout: String, CaseIterable, Identifiable {
    case keep
    case essentialsAndMine
    case onlyMine

    var id: String { rawValue }

    var label: String {
        switch self {
        case .keep:              "Keep as is"
        case .essentialsAndMine: "Essentials + my apps"
        case .onlyMine:          "Only my apps"
        }
    }

    var detail: String {
        switch self {
        case .keep:              "Leave the Dock exactly as it is."
        case .essentialsAndMine: "Safari, Mail, Messages, Calendar and System Settings, then the apps you picked."
        case .onlyMine:          "Just the apps you picked. Finder and the Trash always stay."
        }
    }
}

/// Apple apps offered in the Dock, in Dock order.
enum AppleApps {
    static let essentials: [(name: String, path: String)] = [
        ("Safari", "/Applications/Safari.app"),
        ("Mail", "/System/Applications/Mail.app"),
        ("Messages", "/System/Applications/Messages.app"),
        ("Calendar", "/System/Applications/Calendar.app"),
    ]
    static let systemSettings = (name: "System Settings", path: "/System/Applications/System Settings.app")
}

nonisolated enum DockWriter {
    /// Replaces the Dock's apps with `paths` (skipping any that don't exist),
    /// after saving a copy of the current Dock so it can be restored.
    static func apply(paths: [String], backupTo backup: URL) async -> Bool {
        _ = await DirectInstaller.run("/usr/bin/defaults", ["export", "com.apple.dock", backup.path])
        var ok = await DirectInstaller.run("/usr/bin/defaults", ["write", "com.apple.dock", "persistent-apps", "-array"]).status == 0
        for path in paths where FileManager.default.fileExists(atPath: path) {
            // Same form the Dock writes itself: a file URL, type 15.
            let fileURL = URL(filePath: path, directoryHint: .isDirectory).absoluteString
            let tile = """
            <dict><key>tile-data</key><dict><key>file-data</key><dict>\
            <key>_CFURLString</key><string>\(xmlEscape(fileURL))</string>\
            <key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>
            """
            let r = await DirectInstaller.run("/usr/bin/defaults", ["write", "com.apple.dock", "persistent-apps", "-array-add", tile])
            ok = ok && r.status == 0
        }
        _ = await DirectInstaller.run("/usr/bin/killall", ["Dock"])
        AppLog.info(.settings, "Dock set to \(paths.count) apps (backup: \(backup.path))")
        return ok
    }

    /// Restores a Dock saved by `apply`.
    static func restore(from backup: URL) async -> Bool {
        let r = await DirectInstaller.run("/usr/bin/defaults", ["import", "com.apple.dock", backup.path])
        _ = await DirectInstaller.run("/usr/bin/killall", ["Dock"])
        return r.status == 0
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Default browser

struct BrowserChoice: Identifiable, Hashable {
    let name: String
    let path: String
    var homepageURL: String?
    var token: String?
    var id: String { path }
}

enum KnownBrowsers {
    /// Catalog tokens we treat as browsers.
    static let tokens: Set<String> = ["google-chrome", "firefox", "arc", "brave-browser", "microsoft-edge"]
}

// MARK: - Personal settings

/// Everything on the Personalise step (#17).
struct Personalisation {
    struct Folder: Identifiable, Hashable {
        /// Path relative to the home folder, e.g. "dev/src".
        let path: String
        var isOn: Bool
        let isCustom: Bool
        var id: String { path }
    }

    var touchID = false

    var folders: [Folder] = [
        Folder(path: "GitHub", isOn: true, isCustom: false),
        Folder(path: "dev/src", isOn: true, isCustom: false),
    ]

    var screenshotsFolder = true
    var screenshotsFolderName = "Screenshots"

    var dockLayout: DockLayout = .keep
    /// The Dock as it will be applied (only used when `dockLayout != .keep`).
    var dockItems: [DockItem] = []

    /// Path of the browser to make default, or nil to leave it alone.
    var defaultBrowserPath: String?

    var screenshotsPath: String {
        NSHomeDirectory() + "/Pictures/" + Self.sanitisedFolder(screenshotsFolderName, fallback: "Screenshots")
    }

    /// Validates a folder name typed by the user: relative to home, no "..",
    /// no leading slash, no empty parts.
    static func sanitisedFolder(_ raw: String, fallback: String? = nil) -> String {
        let parts = raw.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        let joined = parts.joined(separator: "/")
        return joined.isEmpty ? (fallback ?? "") : joined
    }

    var isEmpty: Bool {
        !touchID && !folders.contains(where: \.isOn) && !screenshotsFolder
            && dockLayout == .keep && defaultBrowserPath == nil
    }
}

/// Applies the user-level parts of Personalisation (folders, screenshots).
/// Touch ID goes in the root batch; Dock and browser are applied after
/// apps are installed so the new apps can be included.
nonisolated enum PersonalSetup {
    static var backupsDirectory: URL {
        AppLog.logFileURL.deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Backups", directoryHint: .isDirectory)
    }

    static func createFolders(_ relativePaths: [String]) -> [String] {
        var created: [String] = []
        for rel in relativePaths {
            let url = URL(filePath: NSHomeDirectory()).appending(path: rel, directoryHint: .isDirectory)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                created.append(url.path)
            } catch {
                AppLog.warn(.settings, "Couldn't create \(url.path): \(error.localizedDescription)")
            }
        }
        if !created.isEmpty { AppLog.info(.settings, "Created folders: \(created.joined(separator: ", "))") }
        return created
    }

    static func setScreenshotsFolder(_ path: String) async -> Bool {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        let r = await DirectInstaller.run("/usr/bin/defaults", ["write", "com.apple.screencapture", "location", "-string", path])
        _ = await DirectInstaller.run("/usr/bin/killall", ["SystemUIServer"])
        AppLog.info(.settings, "Screenshots now save to \(path)")
        return r.status == 0
    }

    /// Asks macOS to make this the default browser. macOS shows its own
    /// "Use … / Keep …" confirmation, which the person has to click.
    @MainActor
    static func setDefaultBrowser(_ path: String) async -> Bool {
        let url = URL(filePath: path)
        do {
            try await NSWorkspace.shared.setDefaultApplication(at: url, toOpenURLsWithScheme: "http")
            AppLog.info(.settings, "Default browser set to \(path)")
            return true
        } catch {
            AppLog.warn(.settings, "Default browser not changed: \(error.localizedDescription)")
            return false
        }
    }
}
