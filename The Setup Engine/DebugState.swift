import Combine
import Foundation

/// Live debug overrides. Reads initial values from env vars; can be flipped from the Debug menu.
/// Reflected at runtime by SetupCoordinator.
final class DebugState: ObservableObject {
    static let shared = DebugState()

    @Published var forceNoBrew: Bool
    @Published var forceBrewInstallFails: Bool
    @Published var fakeAppFailures: Int
    @Published var requestedJumpStep: SetupCoordinator.Step?

    private init() {
        let env = ProcessInfo.processInfo.environment
        self.forceNoBrew = env["TSE_FORCE_NO_BREW"] == "1"
        self.forceBrewInstallFails = env["TSE_FORCE_BREW_FAILS"] == "1"
        self.fakeAppFailures = Int(env["TSE_FAKE_APP_FAILURES"] ?? "0") ?? 0
    }

    func resetAll() {
        forceNoBrew = false
        forceBrewInstallFails = false
        fakeAppFailures = 0
    }
}
