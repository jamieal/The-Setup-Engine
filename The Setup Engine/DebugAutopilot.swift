#if DEBUG
import AppKit

/// Debug-only: opens the app on a chosen step and saves a picture of the
/// window, so every screen can be checked without clicking through.
/// Never starts an install.
///
///   TSE_START_STEP=personalise   step to show (Step case name)
///   TSE_PROFILE=Developer        pre-pick a profile's apps
///   TSE_DOCK=keep                leave the Dock plan empty (shorter page)
///   TSE_SNAPSHOT_TO=/path.png    save the window there, then quit
enum DebugAutopilot {
    static func run(_ coordinator: SetupCoordinator) async {
        let env = ProcessInfo.processInfo.environment
        guard let stepName = env["TSE_START_STEP"] else { return }

        if let name = env["TSE_PROFILE"], let profile = Suggestions.profiles.first(where: { $0.name == name }) {
            coordinator.apply(profile: profile)
        }
        if let step = SetupCoordinator.Step.allCases.first(where: { "\($0)" == stepName }),
           step != .install {
            if env["TSE_DOCK"] != "keep",
               step.rawValue > SetupCoordinator.Step.personalise.rawValue || step == .personalise {
                coordinator.setDockLayout(.essentialsAndMine)
            }
            coordinator.currentStep = step
        }

        guard let path = env["TSE_SNAPSHOT_TO"] else { return }
        try? await Task.sleep(for: .seconds(4))   // let icons and layout settle
        WindowSnapshot.save(to: URL(filePath: path))
        NSApp.terminate(nil)
    }
}
#endif
