import AppKit
import Foundation

// MARK: - Settings snapshot (for the receipt and undo)

/// One macOS setting as it stood at a moment: its type and value, or absent.
nonisolated struct DefaultsValue: Codable, Hashable, Sendable {
    let domain: String
    let key: String
    /// `defaults` type ("boolean", "string", "integer", "float"), nil when unset.
    let type: String?
    let value: String?

    var display: String {
        guard let value else { return "not set" }
        if type == "boolean" { return value == "1" ? "on" : "off" }
        return value
    }
}

/// Captures and restores every setting The Setup Engine can change, so the
/// finish screen can show old → new and undo it.
nonisolated enum SettingsSnapshot {
    static let tracked: [(domain: String, key: String, label: String)] = [
        ("NSGlobalDomain", "AppleInterfaceStyle", "Appearance"),
        ("NSGlobalDomain", "AppleInterfaceStyleSwitchesAutomatically", "Automatic appearance"),
        ("com.apple.dock", "orientation", "Dock position"),
        ("com.apple.dock", "autohide", "Dock auto-hide"),
        ("com.apple.finder", "ShowPathbar", "Finder path bar"),
        ("com.apple.finder", "AppleShowAllFiles", "Hidden files in Finder"),
        ("NSGlobalDomain", "AppleICUForce24HourTime", "24-hour time"),
        ("com.apple.screencapture", "location", "Screenshots folder"),
    ]

    static func label(for value: DefaultsValue) -> String {
        tracked.first { $0.domain == value.domain && $0.key == value.key }?.label ?? value.key
    }

    static func capture() async -> [DefaultsValue] {
        var out: [DefaultsValue] = []
        for t in tracked {
            let typeResult = await DirectInstaller.run("/usr/bin/defaults", ["read-type", t.domain, t.key])
            guard typeResult.status == 0 else {
                out.append(DefaultsValue(domain: t.domain, key: t.key, type: nil, value: nil))
                continue
            }
            // "Type is boolean"
            let type = String(decoding: typeResult.stdout, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: " ").last
            let read = await DirectInstaller.run("/usr/bin/defaults", ["read", t.domain, t.key])
            let value = String(decoding: read.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(DefaultsValue(domain: t.domain, key: t.key, type: type, value: value))
        }
        return out
    }

    /// Puts each given setting back the way it was, then restarts what shows
    /// them. Pass only the settings that changed.
    static func restore(_ values: [DefaultsValue]) async {
        guard !values.isEmpty else { return }
        for v in values {
            if let type = v.type, let value = v.value {
                let flag: String
                var arg = value
                switch type {
                case "boolean": flag = "-bool"; arg = value == "1" ? "true" : "false"
                case "integer": flag = "-int"
                case "float":   flag = "-float"
                default:        flag = "-string"
                }
                _ = await DirectInstaller.run("/usr/bin/defaults", ["write", v.domain, v.key, flag, arg])
            } else {
                _ = await DirectInstaller.run("/usr/bin/defaults", ["delete", v.domain, v.key])
            }
        }
        for process in ["Dock", "Finder", "SystemUIServer", "ControlCenter"] {
            _ = await DirectInstaller.run("/usr/bin/killall", [process])
        }
        // Only repaint the appearance if it's one of the settings being restored.
        if let style = values.first(where: { $0.key == "AppleInterfaceStyle" }) {
            let dark = style.value == "Dark"
            _ = await DirectInstaller.run("/usr/bin/osascript", [
                "-e", "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)",
            ])
        }
        AppLog.info(.settings, "Restored \(values.count) settings to their earlier values")
    }

    /// App names in a Dock exported with `defaults export com.apple.dock`.
    static func dockNames(in plist: URL) -> [String] {
        guard let data = try? Data(contentsOf: plist),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let apps = root["persistent-apps"] as? [[String: Any]]
        else { return [] }
        return apps.compactMap { ($0["tile-data"] as? [String: Any])?["file-label"] as? String }
    }
}

// MARK: - Wallpaper undo

enum WallpaperSnapshot {
    /// The current desktop picture for each screen, keyed by screen name.
    static func capture() -> [String: URL] {
        var out: [String: URL] = [:]
        for screen in NSScreen.screens {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) {
                out[screen.localizedName] = url
            }
        }
        return out
    }

    static func restore(_ snapshot: [String: URL]) {
        for screen in NSScreen.screens {
            guard let url = snapshot[screen.localizedName] else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }
}

// MARK: - Receipt

/// Plain-text record of everything a setup run did, saved to Documents.
struct SetupReceipt {
    struct InstalledApp {
        let name: String
        let version: String?
        let signer: String?
        let via: String
    }

    var date = Date()
    var installed: [InstalledApp] = []
    var skipped: [String] = []
    var failed: [(name: String, reason: String)] = []
    var settingsBefore: [DefaultsValue] = []
    var settingsAfter: [DefaultsValue] = []
    var dockBefore: [String] = []
    var dockAfter: [String] = []
    var personalNotes: [String] = []
    var dockBackup: URL?

    var markdown: String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        var md = "# The Setup Engine — receipt\n\n"
        md += "\(df.string(from: date)) · \(Host.current().localizedName ?? "This Mac") · "
        md += "\(MacEnvironment.chip.rawValue) · macOS \(MacEnvironment.macOSVersionString)\n\n"

        md += "## Apps installed (\(installed.count))\n\n"
        if installed.isEmpty { md += "None.\n\n" }
        for app in installed {
            md += "- **\(app.name)**"
            if let v = app.version, v != "latest" { md += " \(v)" }
            md += " — \(app.via)"
            if let s = app.signer { md += "; signed by \(s)" }
            md += "\n"
        }
        if !installed.isEmpty { md += "\n" }

        if !skipped.isEmpty {
            md += "Already on this Mac, left alone: \(skipped.joined(separator: ", ")).\n\n"
        }
        if !failed.isEmpty {
            md += "## Didn't install\n\n"
            for f in failed { md += "- **\(f.name)**: \(f.reason)\n" }
            md += "\n"
        }

        let changes = zip(settingsBefore, settingsAfter).filter { $0 != $1 }
        md += "## Settings changed (\(changes.count))\n\n"
        if changes.isEmpty { md += "None.\n\n" }
        for (old, new) in changes {
            md += "- \(SettingsSnapshot.label(for: old)): \(old.display) → **\(new.display)**  \n"
            md += "  `defaults` key: \(old.domain) \(old.key)\n"
        }
        if !changes.isEmpty { md += "\n" }

        if !dockAfter.isEmpty || !dockBefore.isEmpty, dockBefore != dockAfter, !dockAfter.isEmpty {
            md += "## Dock\n\n"
            md += "Before: \(dockBefore.isEmpty ? "unknown" : dockBefore.joined(separator: ", "))\n\n"
            md += "After: \(dockAfter.joined(separator: ", "))\n\n"
            if let dockBackup {
                md += "To put the old Dock back: `defaults import com.apple.dock \"\(dockBackup.path)\" && killall Dock`\n\n"
            }
        }

        if !personalNotes.isEmpty {
            md += "## Personal touches\n\n"
            for n in personalNotes { md += "- \(n)\n" }
            md += "\n"
        }

        md += "---\n\nTo undo any setting by hand, use the old value above with `defaults write`, "
        md += "or change it in System Settings. Touch ID for sudo can be turned off by deleting "
        md += "`/etc/pam.d/sudo_local`.\n"
        return md
    }

    /// Writes the receipt to ~/Documents and returns where.
    func save() -> URL? {
        let folder = PersonalSetup.backupsDirectory
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH.mm"
        let url = folder.appending(path: "Receipt \(df.string(from: date)).md")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            AppLog.info(.general, "Receipt saved to \(url.path)")
            return url
        } catch {
            AppLog.warn(.general, "Couldn't save receipt: \(error.localizedDescription)")
            return nil
        }
    }
}
