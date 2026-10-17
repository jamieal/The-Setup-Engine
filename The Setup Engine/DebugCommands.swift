#if DEBUG
import SwiftUI

struct DebugCommands: Commands {
    @ObservedObject var state: DebugState

    var body: some Commands {
        CommandMenu("Debug") {
            Menu("Fake App Failures") {
                Button("0 (none)") { state.fakeAppFailures = 0 }
                Button("1")        { state.fakeAppFailures = 1 }
                Button("2")        { state.fakeAppFailures = 2 }
                Button("3")        { state.fakeAppFailures = 3 }
                Button("All")      { state.fakeAppFailures = .max }
            }

            Divider()

            Menu("Jump to Step") {
                Button("Welcome")   { state.requestedJumpStep = .welcome }
                Button("Profile")   { state.requestedJumpStep = .profile }
                Button("Apps")      { state.requestedJumpStep = .apps }
                Button("System")    { state.requestedJumpStep = .system }
                Button("Review")    { state.requestedJumpStep = .review }
                Button("Install")   { state.requestedJumpStep = .install }
                Button("Done")      { state.requestedJumpStep = .done }
            }

            Divider()

            Button("Reset All Overrides") { state.resetAll() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
#endif
