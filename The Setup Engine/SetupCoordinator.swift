import Combine
import Foundation
import SwiftUI

final class SetupCoordinator: ObservableObject {

    // MARK: - Step

    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case profile
        case apps
        case system
        case review
        case install
        case done

        var id: Int { rawValue }

        /// Steps shown in the top progress indicator. Welcome and Done sit outside the dotted track.
        static var trackedSteps: [Step] {
            [.profile, .apps, .system, .review, .install]
        }

        var trackTitle: String {
            switch self {
            case .profile:  "Profile"
            case .apps:     "Apps"
            case .system:   "System"
            case .review:   "Review"
            case .install:  "Install"
            default: ""
            }
        }
    }

    enum ItemStatus: Equatable {
        case pending
        case downloading(Double)
        case verifying
        case installing
        case waitingForPassword
        case succeeded
        case failed(String)
        case skipped   // already installed; no work needed

        var isFinished: Bool {
            switch self {
            case .succeeded, .failed, .skipped: true
            default: false
            }
        }
    }

    // MARK: - State

    @Published var currentStep: Step = .welcome

    @Published var selectedProfile: SetupProfile?
    @Published var selectedApps: [AppEntry] = []

    @Published var settings = SystemPreferences()

    @Published var itemStatuses: [String: ItemStatus] = [:]
    @Published var currentInstallIndex: Int = 0
    @Published var settingsApplied: Bool = false
    @Published var installComplete: Bool = false
    @Published var failedItems: [String] = []

    /// Pre-loaded at app launch.
    /// Exact bundle names ("Google Chrome.app") in /Applications and ~/Applications.
    @Published var installedBundles: Set<String> = []
    /// Lowercased, space-stripped names of the same bundles, for loose matching.
    @Published var installedAppNames: Set<String> = []
    /// Casks and formulae Homebrew already manages (empty without Homebrew).
    @Published var installedCasks: Set<String> = []
    @Published var installedFormulae: Set<String> = []
    @Published var installedStateLoaded: Bool = false

    let shell = ShellRunner()
    let catalog = CaskCatalog.shared
    private let installer = DirectInstaller()
    private var cancellables = Set<AnyCancellable>()

    static var installLogPath: String {
        AppLog.logFileURL.deletingLastPathComponent().appending(path: "install.log").path
    }

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

        // Forward ShellRunner's @Published changes to our own observers so views
        // that derive UI from `coordinator.shell.output` re-render in real time.
        //
        // Throttled to 10/sec — without it, per-line output during an install
        // fans out hundreds of publishes/sec to every observing view, which can
        // trigger SwiftUI's "publishing changes from within view updates" panic.
        shell.objectWillChange
            .throttle(for: .milliseconds(100), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Availability badges depend on the catalog, which loads in the background.
        catalog.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Preflight

    /// Called from SetupContainerView.task at launch. Loads Homebrew's app catalog
    /// and scans what's already installed so the Apps step has data ready.
    func preflight() async {
        async let catalogLoad: Void = catalog.load()
        await loadInstalledState()
        await catalogLoad
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
        case .review: "Begin Setup"
        case .install: installComplete ? "Continue" : "Installing…"
        case .done: "Quit"
        default: "Continue"
        }
    }

    // MARK: - Installed-state preload

    /// Scans /Applications and asks Homebrew (if present) what it manages, so we
    /// know what's already on the user's Mac.
    func loadInstalledState() async {
        async let bundles = scanApplications()
        async let casks = HomebrewSupport.installedCasks()
        async let formulae = HomebrewSupport.installedFormulae()
        let (b, c, f) = await (bundles, casks, formulae)
        installedBundles = b
        installedAppNames = Set(b.map { Self.normalize(($0 as NSString).deletingPathExtension) })
        installedCasks = c
        installedFormulae = f
        installedStateLoaded = true
    }

    private func scanApplications() async -> Set<String> {
        await Task.detached {
            let dirs = ["/Applications", NSHomeDirectory() + "/Applications"]
            var out: Set<String> = []
            for dir in dirs {
                guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
                out.formUnion(items.filter { $0.hasSuffix(".app") })
            }
            return out
        }.value
    }

    nonisolated private static func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    /// True if the app or tool is already on this Mac.
    func isInstalled(_ app: AppEntry) -> Bool {
        if app.kind == .commandLine { return installedFormulae.contains(app.caskName) }
        if installedCasks.contains(app.caskName) { return true }

        // Best signal: the exact bundle names Homebrew's catalog says this app installs.
        if let cask = catalog.cask(app.caskName), !cask.installedAppNames.isEmpty {
            return cask.installedAppNames.contains { installedBundles.contains($0) }
        }

        // Installer-package apps (or catalog not loaded yet): match by name.
        let cask = Self.normalize(app.caskName)
        let display = Self.normalize(app.displayName)
        return installedAppNames.contains(cask)
            || installedAppNames.contains(display)
            || installedAppNames.contains { $0.hasPrefix(display) && display.count >= 4 }
    }

    /// Command-line tools, and the few apps whose makers only serve Homebrew,
    /// are installed through Homebrew. Everything else is installed directly.
    func usesHomebrew(_ app: AppEntry) -> Bool {
        app.kind == .commandLine || Suggestions.homebrewOnly.contains(app.caskName)
    }

    /// Why this app can't be installed on this Mac, or nil if it can.
    func unavailableReason(_ app: AppEntry) -> String? {
        if app.kind == .app, let why = catalog.cask(app.caskName)?.unavailableReason { return why }
        guard usesHomebrew(app), let why = HomebrewSupport.unavailableReason else { return nil }
        return app.kind == .app ? "Its maker only allows downloads through Homebrew" : why
    }

    /// True if installing this app will ask for the Mac's password: it uses
    /// Apple's installer, or this account can't write to /Applications
    /// (a standard, non-admin account).
    func needsPassword(_ app: AppEntry) -> Bool {
        guard !usesHomebrew(app), let record = catalog.cask(app.caskName)?.record else { return false }
        return !record.pkgs.isEmpty || !FileManager.default.isWritableFile(atPath: "/Applications")
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
        // Skip apps already on the Mac or unavailable here — no point queuing an
        // install we'll immediately skip. Keeps the Selected sidebar focused.
        for cask in profile.casks
            where !isSelected(cask) && !isInstalled(cask) && unavailableReason(cask) == nil {
            selectedApps.append(cask)
        }
    }

    // MARK: - Install

    /// Apps that will actually be installed (excluding already-installed).
    var appsToInstall: [AppEntry] {
        selectedApps.filter { !isInstalled($0) }
    }

    /// Apps that will be skipped because they're already installed.
    var appsAlreadyInstalled: [AppEntry] {
        selectedApps.filter { isInstalled($0) }
    }

    /// Plain-words reason for each failed item, keyed by token.
    @Published var failureReasons: [String: String] = [:]

    private func fail(_ app: AppEntry, _ reason: String) {
        itemStatuses[app.caskName] = .failed(reason)
        failureReasons[app.caskName] = reason
        if !failedItems.contains(app.displayName) { failedItems.append(app.displayName) }
        AppLog.error(.install, "\(app.caskName): \(reason)")
    }

    private func runInstall() async {
        AppLog.info(.install, "Install run started — \(selectedApps.count) selected, \(appsToInstall.count) to install")
        currentInstallIndex = 0
        installComplete = false
        failedItems = []
        failureReasons = [:]
        settingsApplied = false
        try? "".write(toFile: Self.installLogPath, atomically: true, encoding: .utf8)

        // Catalog first: "already installed" uses its exact bundle names.
        await catalog.load()
        installer.sweepStaleWorkFolders()
        for app in selectedApps {
            itemStatuses[app.caskName] = isInstalled(app) ? .skipped : .pending
        }

        var fakeFailuresLeft = DebugState.shared.fakeAppFailures
        var adminApps: [StagedApp] = []
        var adminPkgs: [StagedPkg] = []
        var waitingOnAdmin: [String: AppEntry] = [:]

        // 1. Apps: download, verify, and move into Applications (no password needed).
        for (i, app) in selectedApps.enumerated() where !usesHomebrew(app) {
            guard itemStatuses[app.caskName] == .pending else { continue }
            currentInstallIndex = i

            if fakeFailuresLeft > 0 {
                fakeFailuresLeft -= 1
                try? await Task.sleep(for: .seconds(1))
                fail(app, "Simulated failure (debug)")
                continue
            }
            guard let cask = catalog.cask(app.caskName) else {
                fail(app, "Couldn't find it in the app catalog. Check your internet connection.")
                continue
            }

            let token = app.caskName
            let gate = ProgressGate()
            itemStatuses[token] = .downloading(0)
            do {
                let staged = try await installer.stage(cask) { [weak self] p in
                    guard gate.shouldReport(p) else { return }
                    Task { @MainActor in
                        guard let self, case .downloading = self.itemStatuses[token] else { return }
                        self.itemStatuses[token] = p >= 1 ? .verifying : .downloading(p)
                    }
                }
                itemStatuses[token] = .installing
                let needAdmin = try installer.place(staged)
                adminApps += needAdmin
                adminPkgs += staged.pkgs
                if needAdmin.isEmpty && staged.pkgs.isEmpty {
                    itemStatuses[token] = .succeeded
                    installer.cleanUp(staged)   // free the disk space now
                    AppLog.info(.install, "Installed \(token) (signed by \(staged.signer ?? "unknown"))")
                } else {
                    itemStatuses[token] = .waitingForPassword
                    waitingOnAdmin[token] = app
                }
            } catch let failure as InstallFailure {
                installer.cleanUp(token: token)
                fail(app, failure.message)
            } catch {
                installer.cleanUp(token: token)
                fail(app, error.localizedDescription)
            }
        }

        // 2. Command-line tools (and Homebrew-only apps) need Homebrew; stage its
        //    installer if it's missing.
        let tools = selectedApps.filter { usesHomebrew($0) && itemStatuses[$0.caskName] == .pending }
        var homebrewReady = HomebrewSupport.isInstalled
        if !tools.isEmpty && !homebrewReady {
            if let why = HomebrewSupport.unavailableReason {
                tools.forEach { fail($0, unavailableReason($0) ?? why) }
            } else {
                do {
                    adminPkgs.append(try await HomebrewSupport.stageInstaller(in: installer.workRoot))
                    tools.forEach { itemStatuses[$0.caskName] = .waitingForPassword }
                } catch let failure as InstallFailure {
                    tools.forEach { fail($0, "Couldn't get Homebrew: \(failure.message)") }
                } catch {
                    tools.forEach { fail($0, "Couldn't get Homebrew: \(error.localizedDescription)") }
                }
            }
        }

        // 3. Everything that needs the password, behind one prompt.
        if !adminApps.isEmpty || !adminPkgs.isEmpty {
            if let first = selectedApps.firstIndex(where: { itemStatuses[$0.caskName] == .waitingForPassword }) {
                currentInstallIndex = first
            }
            let script = installer.adminScript(apps: adminApps, pkgs: adminPkgs)
            let ran = await shell.runWithAdmin(script)
            func tokens(_ prefix: String) -> Set<String> {
                Set(shell.output.split(separator: "\n")
                    .filter { $0.hasPrefix(prefix) }
                    .map { String($0.dropFirst(prefix.count)) })
            }
            // An app with several parts (say an app and a package) only counts
            // as installed if none of its parts failed.
            let ok = tokens("TSE_OK ").subtracting(tokens("TSE_FAIL "))

            for (token, app) in waitingOnAdmin {
                if ok.contains(token) { itemStatuses[token] = .succeeded }
                else { fail(app, ran ? "The installer didn't finish" : "Password prompt was cancelled") }
            }
            if adminPkgs.contains(where: { $0.token == "homebrew" }) {
                homebrewReady = ok.contains("homebrew") && HomebrewSupport.isInstalled
                if homebrewReady {
                    AppLog.info(.homebrew, "Homebrew installed")
                } else {
                    tools.filter { itemStatuses[$0.caskName] == .waitingForPassword }
                        .forEach { fail($0, ran ? "Homebrew didn't install" : "Password prompt was cancelled") }
                }
            }
        }

        // 4. Command-line tools and Homebrew-only apps, through Homebrew.
        if homebrewReady {
            for (i, tool) in selectedApps.enumerated() where usesHomebrew(tool) {
                let status = itemStatuses[tool.caskName]
                guard status == .pending || status == .waitingForPassword else { continue }
                currentInstallIndex = i
                itemStatuses[tool.caskName] = .installing
                guard let command = HomebrewSupport.installCommand(tool.caskName, cask: tool.kind == .app) else {
                    fail(tool, "Not a valid Homebrew formula name")
                    continue
                }
                let success = await shell.run(
                    "{ echo '=== \(tool.caskName) ==='; \(command); } 2>&1 | tee -a \(DirectInstaller.quote(Self.installLogPath)); exit ${pipestatus[1]}",
                    clearOutput: false
                )
                if success { itemStatuses[tool.caskName] = .succeeded }
                else { fail(tool, "Homebrew couldn't install it — see the install log") }
            }
        }

        installer.cleanUpAll()

        // 5. System preferences
        let script = settings.commandLine()
        if !script.isEmpty {
            AppLog.info(.settings, "Applying system preferences")
            await shell.run(script, clearOutput: false)
        }
        settingsApplied = true

        await loadInstalledState()
        AppLog.info(.install, "Install run complete — \(failedItems.count) failures")
        installComplete = true
    }
}

/// Lets download progress through at most every 2%, so a fast download
/// doesn't flood the main thread with UI updates.
nonisolated final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0

    func shouldReport(_ value: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard value >= 1 || value - last >= 0.02 else { return false }
        last = value
        return true
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
