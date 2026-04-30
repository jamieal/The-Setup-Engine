import Combine
import Foundation
import SwiftUI

final class SetupCoordinator: ObservableObject {

    // MARK: - Step

    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case homebrew
        case profile
        case apps
        case system
        case review
        case install
        case done

        var id: Int { rawValue }

        /// Steps shown in the top progress indicator. Welcome and Done sit outside the dotted track.
        static var trackedSteps: [Step] {
            [.homebrew, .profile, .apps, .system, .review, .install]
        }

        var trackTitle: String {
            switch self {
            case .homebrew: "Tools"
            case .profile:  "Profile"
            case .apps:     "Apps"
            case .system:   "System"
            case .review:   "Review"
            case .install:  "Install"
            default: ""
            }
        }
    }

    enum HomebrewStatus: Equatable {
        case checking
        case installed
        case notInstalled
        case installing
        case uninstalling
        case failed(String)
    }

    enum ItemStatus: Equatable {
        case pending
        case installing
        case succeeded
        case failed
        case skipped   // already installed; no work needed
    }

    // MARK: - State

    @Published var currentStep: Step = .welcome

    @Published var homebrewStatus: HomebrewStatus = .checking

    @Published var selectedProfile: SetupProfile?
    @Published var selectedApps: [AppEntry] = []

    @Published var settings = SystemPreferences()

    @Published var itemStatuses: [String: ItemStatus] = [:]
    @Published var currentInstallIndex: Int = 0
    @Published var settingsApplied: Bool = false
    @Published var installComplete: Bool = false
    @Published var failedItems: [String] = []

    /// Pre-loaded at app launch.
    @Published var installedCasks: Set<String> = []
    /// Lowercased, space-stripped names of every .app under /Applications.
    @Published var installedAppNames: Set<String> = []
    @Published var installedStateLoaded: Bool = false

    let shell = ShellRunner()
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Bridge Debug menu's step jumps into the coordinator.
        DebugState.shared.$requestedJumpStep
            .compactMap { $0 }
            .sink { [weak self] step in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.currentStep = step
                }
                DebugState.shared.requestedJumpStep = nil
            }
            .store(in: &cancellables)

        // When the no-brew override flips, re-run detection so the UI updates live
        // without needing the user to navigate away and back.
        DebugState.shared.$forceNoBrew
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { await self?.preflight() }
            }
            .store(in: &cancellables)

        // Forward ShellRunner's @Published changes to our own observers so views
        // that derive UI from `coordinator.shell.output` (e.g. the staged brew
        // install progress bar) re-render in real time.
        //
        // Throttled to 10/sec — without it, brew's per-line output during an
        // install fans out hundreds of publishes/sec to every observing view,
        // which can trigger SwiftUI's "publishing changes from within view
        // updates" panic and freeze/crash the UI.
        shell.objectWillChange
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Preflight

    /// Called from SetupContainerView.task at launch. Detects Homebrew and pre-loads
    /// the user's installed apps so AppsStep has data ready before they arrive.
    func preflight() async {
        await checkHomebrew()
        await loadInstalledState()
    }

    // MARK: - Navigation

    func next() {
        guard let n = Step(rawValue: currentStep.rawValue + 1) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = n
        }
        if n == .install {
            Task { await runInstall() }
        }
    }

    func back() {
        guard let p = Step(rawValue: currentStep.rawValue - 1), p.rawValue >= 0 else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = p
        }
    }

    var canGoBack: Bool {
        switch currentStep {
        case .welcome, .install, .done: false
        default: true
        }
    }

    var canGoNext: Bool {
        switch currentStep {
        case .welcome: true
        case .homebrew: homebrewStatus == .installed
        case .profile: !selectedApps.isEmpty || selectedProfile != nil
        case .apps: !selectedApps.isEmpty
        case .system: true
        case .review: true
        case .install: installComplete
        case .done: true
        }
    }

    var primaryActionTitle: String {
        switch currentStep {
        case .welcome: "Get Started"
        case .homebrew:
            switch homebrewStatus {
            case .installed: "Continue"
            case .notInstalled: "Install Homebrew"
            case .installing: "Installing…"
            case .uninstalling: "Uninstalling…"
            case .checking: "Checking…"
            case .failed: "Try Again"
            }
        case .review: "Begin Setup"
        case .install: installComplete ? "Continue" : "Installing…"
        case .done: "Quit"
        default: "Continue"
        }
    }

    // MARK: - Homebrew

    func checkHomebrew() async {
        if DebugState.shared.forceNoBrew {
            AppLog.info(.homebrew, "Forced not-installed (debug override)")
            homebrewStatus = .notInstalled
            return
        }
        homebrewStatus = .checking
        try? await Task.sleep(for: .milliseconds(300))
        let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        let found = paths.contains { FileManager.default.fileExists(atPath: $0) }
        AppLog.info(.homebrew, "Detection: \(found ? "installed" : "not installed")")
        homebrewStatus = found ? .installed : .notInstalled
    }

    func installHomebrew() async {
        AppLog.info(.homebrew, "Install requested")
        homebrewStatus = .installing

        // Debug override — simulate failure without touching the system.
        if DebugState.shared.forceBrewInstallFails {
            AppLog.warn(.homebrew, "Simulating install failure (debug)")
            try? await Task.sleep(for: .seconds(2))
            homebrewStatus = .failed("Simulated failure (debug mode is on).")
            return
        }

        // Xcode Command Line Tools are required by brew (for git, gcc, etc).
        // Surface this before asking for the admin password.
        if !xcodeCommandLineToolsInstalled() {
            AppLog.warn(.homebrew, "Xcode CLT missing; triggering system installer")
            homebrewStatus = .failed(
                "Xcode Command Line Tools are required first. We'll open the installer — accept it, wait for it to finish, then click Try Again."
            )
            triggerXcodeCommandLineToolsInstaller()
            return
        }

        let userName = NSUserName()
        let prefix = "/opt/homebrew"

        // Manual install — the official `install.sh` aborts when run as root, but
        // `osascript with administrator privileges` runs us as root. So we do the
        // privileged steps ourselves, then drop back to the user (`sudo -u`) for
        // anything brew refuses to do as root.
        // Stage markers (STAGE_X) drive the staged progress bar in the UI.
        // We split download and extract into separate steps (via a temp tarball) so
        // each transition produces a visible change for the user.
        let installCommand = """
        set -e
        USER_NAME='\(userName)'
        PREFIX='\(prefix)'
        TARBALL='/tmp/the_setup_engine_brew.tar.gz'

        # --- defensive guards (root context — bugs here would be catastrophic) ---
        # Refuse if any required variable is missing or unexpected. Belt and braces:
        # we set them ourselves, but we run as root so we're paranoid about anything
        # that touches the filesystem.
        if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
            echo "ERROR: invalid user '$USER_NAME'"; exit 1
        fi
        if [ "$PREFIX" != "/opt/homebrew" ]; then
            echo "ERROR: prefix must be /opt/homebrew, got '$PREFIX'"; exit 1
        fi
        if [ ! -d "/Users/$USER_NAME" ]; then
            echo "ERROR: home directory for '$USER_NAME' not found"; exit 1
        fi

        echo "STAGE_PREPARING"
        if [ -d "$PREFIX" ] && [ ! -f "$PREFIX/bin/brew" ]; then
            # Reassert PREFIX is what we expect before any rm — we run as root.
            [ "$PREFIX" = "/opt/homebrew" ] || exit 1
            rm -rf "$PREFIX"/* 2>/dev/null || true
            rm -rf "$PREFIX"/.??* 2>/dev/null || true
        fi
        mkdir -p "$PREFIX"
        chown -R "$USER_NAME": "$PREFIX"
        chmod -R u+rwX,g+rX,o+rX "$PREFIX"

        echo "STAGE_DOWNLOADING"
        sudo -u "$USER_NAME" /bin/bash -c "
            set -e
            curl -fsSL https://github.com/Homebrew/brew/tarball/main -o '$TARBALL'
        "

        echo "STAGE_EXTRACTING"
        sudo -u "$USER_NAME" /bin/bash -c "
            set -e
            cd '$PREFIX'
            tar xz --strip 1 -f '$TARBALL'
        "
        rm -f "$TARBALL"

        echo "STAGE_CONFIGURING"
        sudo -u "$USER_NAME" "$PREFIX/bin/brew" update --force --quiet 2>&1 || true

        ZPROFILE="/Users/$USER_NAME/.zprofile"
        if [ ! -f "$ZPROFILE" ] || ! grep -q "brew shellenv" "$ZPROFILE"; then
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$ZPROFILE"
            chown "$USER_NAME": "$ZPROFILE"
        fi

        echo "INSTALL_OK"
        """

        let success = await shell.runWithAdmin(installCommand)
        let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        let found = paths.contains { FileManager.default.fileExists(atPath: $0) }

        if success || found {
            AppLog.info(.homebrew, "Install completed successfully")
            homebrewStatus = .installed
            await loadInstalledState()
        } else if shell.output.isEmpty {
            AppLog.warn(.homebrew, "Install cancelled (no output)")
            homebrewStatus = .failed("Installation was cancelled.")
        } else {
            let msg = friendlyError(from: shell.output)
            AppLog.error(.homebrew, "Install failed: \(msg)")
            homebrewStatus = .failed(msg)
        }
    }

    private func xcodeCommandLineToolsInstalled() -> Bool {
        // Either CLT-only install or full Xcode satisfies brew.
        FileManager.default.fileExists(atPath: "/Library/Developer/CommandLineTools/usr/bin/git")
            || FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
    }

    private func triggerXcodeCommandLineToolsInstaller() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["--install"]
        try? p.run()
    }

    /// Removes /opt/homebrew and the brew shellenv line from the user's ~/.zprofile.
    /// Useful for testing the no-brew flow on a real machine.
    func uninstallHomebrew() async {
        AppLog.info(.homebrew, "Uninstall requested")
        homebrewStatus = .uninstalling

        let userName = NSUserName()
        let uninstallCommand = """
        set -e
        USER_NAME='\(userName)'

        # --- defensive guards ---
        # Hard-coded paths only. Refuse if user is empty/root or home doesn't exist.
        if [ -z "$USER_NAME" ] || [ "$USER_NAME" = "root" ]; then
            echo "ERROR: invalid user '$USER_NAME'"; exit 1
        fi
        if [ ! -d "/Users/$USER_NAME" ]; then
            echo "ERROR: home directory for '$USER_NAME' not found"; exit 1
        fi

        # Each rm has its target literally in the script — no variable interpolation
        # near the slash. Belt and braces.
        if [ -d /opt/homebrew ]; then
            rm -rf /opt/homebrew 2>/dev/null || true
        fi
        if [ -d /usr/local/Homebrew ]; then
            rm -rf /usr/local/Homebrew 2>/dev/null || true
        fi

        CACHE="/Users/$USER_NAME/Library/Caches/Homebrew"
        LOGS="/Users/$USER_NAME/Library/Logs/Homebrew"
        [ -d "$CACHE" ] && rm -rf "$CACHE"
        [ -d "$LOGS" ] && rm -rf "$LOGS"

        ZPROFILE="/Users/$USER_NAME/.zprofile"
        if [ -f "$ZPROFILE" ]; then
            sed -i '' '/brew shellenv/d' "$ZPROFILE"
        fi
        echo "UNINSTALL_OK"
        """

        _ = await shell.runWithAdmin(uninstallCommand)

        // Re-detect rather than assuming success — the user might have cancelled.
        await checkHomebrew()
        installedCasks = []
    }

    private func friendlyError(from output: String) -> String {
        let lower = output.lowercased()
        if lower.contains("don't run this as root") {
            return "Internal install error — please report this. (Tried to run as root.)"
        }
        if lower.contains("xcode-select") || lower.contains("command line tools") {
            return "Xcode Command Line Tools are required. Run xcode-select --install in Terminal."
        }
        if lower.contains("could not resolve") || lower.contains("network") || lower.contains("curl: ") {
            return "Couldn't reach Homebrew's servers. Check your internet connection and try again."
        }
        if lower.contains("permission denied") {
            return "Permission denied. Try running setup again and approve the password prompt."
        }
        return "Installation didn't finish. Try again or visit brew.sh."
    }

    // MARK: - Installed-state preload

    /// Scans /Applications and runs `brew list --cask` so we know what's already on the user's Mac.
    /// Safe to call before brew is installed — `brew list` just returns empty.
    func loadInstalledState() async {
        async let appNames = scanApplications()
        async let casks = brewListedCasks()
        let (names, list) = await (appNames, casks)
        installedAppNames = names
        installedCasks = list
        installedStateLoaded = true
    }

    private func scanApplications() async -> Set<String> {
        await Task.detached {
            let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
            var out: Set<String> = []
            for dir in dirs {
                guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
                for item in items where item.hasSuffix(".app") {
                    let name = (item as NSString).deletingPathExtension
                    out.insert(Self.normalize(name))
                }
            }
            return out
        }.value
    }

    private func brewListedCasks() async -> Set<String> {
        guard homebrewStatus == .installed else { return [] }
        return await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-c", "brew list --cask"]
            p.environment = ShellRunner.brewEnvironment()
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                return Set(
                    output
                        .components(separatedBy: .newlines)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                )
            } catch {
                return []
            }
        }.value
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    /// True if the app appears installed on this Mac, by either cask or /Applications match.
    func isInstalled(_ app: AppEntry) -> Bool {
        if installedCasks.contains(app.caskName) { return true }
        let cask = Self.normalize(app.caskName)
        let display = Self.normalize(app.displayName)
        return installedAppNames.contains(cask)
            || installedAppNames.contains(display)
            || installedAppNames.contains { name in
                name.contains(display) || display.contains(name)
            }
    }

    // MARK: - Apps

    func toggle(_ app: AppEntry) {
        if let i = selectedApps.firstIndex(where: { $0.caskName == app.caskName }) {
            selectedApps.remove(at: i)
        } else {
            selectedApps.append(app)
        }
    }

    func isSelected(_ app: AppEntry) -> Bool {
        selectedApps.contains { $0.caskName == app.caskName }
    }

    func apply(profile: SetupProfile) {
        selectedProfile = profile
        // Skip apps already on the Mac — no point queuing an install we'll
        // immediately skip. Keeps the Selected sidebar focused on actual work.
        for cask in profile.casks
            where !isSelected(cask) && !isInstalled(cask) {
            selectedApps.append(cask)
        }
    }

    // MARK: - Install

    /// Apps that will actually run through brew install (excluding already-installed).
    var appsToInstall: [AppEntry] {
        selectedApps.filter { !isInstalled($0) }
    }

    /// Apps that will be skipped because they're already installed.
    var appsAlreadyInstalled: [AppEntry] {
        selectedApps.filter { isInstalled($0) }
    }

    private func runInstall() async {
        AppLog.info(.install, "Install run started — \(selectedApps.count) selected, \(appsToInstall.count) to install")
        currentInstallIndex = 0
        installComplete = false
        failedItems = []
        settingsApplied = false

        for app in selectedApps {
            itemStatuses[app.caskName] = isInstalled(app) ? .skipped : .pending
        }

        let toFakeFail = DebugState.shared.fakeAppFailures
        var fakedSoFar = 0

        // Reset the install log so each setup run starts fresh.
        let logPath = "/tmp/the_setup_engine_install.log"
        try? "".write(toFile: logPath, atomically: true, encoding: .utf8)

        for (i, app) in selectedApps.enumerated() {
            currentInstallIndex = i

            if itemStatuses[app.caskName] == .skipped {
                AppLog.info(.install, "Skipping \(app.caskName) — already installed")
                continue
            }

            itemStatuses[app.caskName] = .installing
            AppLog.info(.install, "Installing \(app.caskName)…")

            // Debug override — simulate first N failures.
            if fakedSoFar < toFakeFail {
                AppLog.warn(.install, "Simulating failure for \(app.caskName) (debug)")
                try? await Task.sleep(for: .seconds(1))
                itemStatuses[app.caskName] = .failed
                failedItems.append(app.displayName)
                fakedSoFar += 1
                continue
            }

            // Tee output to /tmp/the_setup_engine_install.log so failed installs
            // can be diagnosed after the fact.
            let success = await shell.run(
                "{ echo '====='; echo \"=== \(app.caskName) — \\$(date) ===\"; echo '====='; brew install --cask \(app.caskName); } 2>&1 | tee -a \(logPath)",
                clearOutput: false
            )

            if success {
                AppLog.info(.install, "Installed \(app.caskName)")
                itemStatuses[app.caskName] = .succeeded
            } else {
                AppLog.error(.install, "Failed: \(app.caskName) — see \(logPath)")
                itemStatuses[app.caskName] = .failed
                failedItems.append(app.displayName)
            }
        }

        // System preferences
        let script = settings.commandLine()
        if !script.isEmpty {
            AppLog.info(.settings, "Applying system preferences")
            await shell.run(script, clearOutput: false)
        }
        settingsApplied = true

        AppLog.info(.install, "Install run complete — \(failedItems.count) failures")
        installComplete = true
    }
}

// MARK: - System Preferences

struct SystemPreferences {
    enum DockPosition: String, CaseIterable, Identifiable {
        case left, bottom, right
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case light, dark, auto
        var id: String { rawValue }
        var label: String {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            case .auto: "Auto"
            }
        }
    }

    var dockPosition: DockPosition = .bottom
    var dockAutoHide: Bool = false
    var appearance: Appearance = .dark
    var showHiddenFiles: Bool = false
    var showPathBar: Bool = true
    var twentyFourHourTime: Bool = true

    /// Builds a single shell script to apply all settings.
    /// Uses `;` between commands so a failure of one (e.g. an osascript permission
    /// prompt) doesn't abort the rest. Each command is individually tolerant.
    ///
    /// Order matters: defaults are written first, processes are restarted to pick
    /// them up, and finally appearance is flipped — so the mode change is a clean
    /// "ta-da" rather than fighting with concurrent killall transitions.
    func commandLine() -> String {
        var cmds: [String] = []

        // ---- 1. Persist defaults ----

        // Dock
        cmds.append("defaults write com.apple.dock orientation -string \(dockPosition.rawValue)")
        cmds.append("defaults write com.apple.dock autohide -bool \(dockAutoHide)")

        // Finder
        cmds.append("defaults write com.apple.finder AppleShowAllFiles -bool \(showHiddenFiles)")
        cmds.append("defaults write com.apple.finder ShowPathbar -bool \(showPathBar)")

        // 24-hour vs locale-default time. Setting AppleICUForce24HourTime to false
        // doesn't FORCE 12-hour — it just unforces, deferring to locale (which is 24h
        // in en_GB and most non-US locales). To get 12-hour everywhere we must
        // explicitly write false AND remove any 24h-forcing override.
        if twentyFourHourTime {
            cmds.append("defaults write NSGlobalDomain AppleICUForce24HourTime -bool true")
        } else {
            cmds.append("defaults write NSGlobalDomain AppleICUForce24HourTime -bool false")
            cmds.append("defaults delete NSGlobalDomain AppleICUForce24HourTime 2>/dev/null || true")
        }

        // ---- 2. Restart affected processes so changes show up ----
        cmds.append("killall Dock 2>/dev/null || true")
        cmds.append("killall Finder 2>/dev/null || true")
        cmds.append("killall SystemUIServer 2>/dev/null || true")
        cmds.append("killall ControlCenter 2>/dev/null || true")

        // ---- 3. Appearance (last — single global flip) ----
        // Write defaults for persistence AND poke System Events so the running UI
        // actually repaints. Without the osascript kick, light-mode switches don't
        // take effect until the next login.
        switch appearance {
        case .light:
            cmds.append("defaults delete -g AppleInterfaceStyle 2>/dev/null || true")
            cmds.append("defaults write -g AppleInterfaceStyleSwitchesAutomatically -bool false")
            cmds.append(#"osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false' 2>/dev/null || true"#)
        case .dark:
            cmds.append("defaults write -g AppleInterfaceStyle -string Dark")
            cmds.append("defaults write -g AppleInterfaceStyleSwitchesAutomatically -bool false")
            cmds.append(#"osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' 2>/dev/null || true"#)
        case .auto:
            cmds.append("defaults write -g AppleInterfaceStyleSwitchesAutomatically -bool true")
        }

        return cmds.joined(separator: "; ")
    }
}
