import AppKit
import SwiftUI

/// All non-debug menu items: customised About, File → Collect Logs / Reveal Logs,
/// Help → GitHub / Report Issue.
struct AppCommands: Commands {
    var body: some Commands {
        // About panel — replace default to inject our credits / repo link.
        CommandGroup(replacing: .appInfo) {
            Button("About The Setup Engine") {
                NSApp.orderFrontStandardAboutPanel(options: [
                    NSApplication.AboutPanelOptionKey.credits: aboutCredits,
                    NSApplication.AboutPanelOptionKey.applicationName: "The Setup Engine",
                ])
            }
        }

        // File menu — diagnostic actions live here for visibility.
        CommandGroup(after: .newItem) {
            Divider()
            Button("Collect Diagnostic Logs…") {
                collectAndRevealLogs()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Reveal Logs in Finder") {
                revealLogsFolder()
            }

            Button("Save Window Snapshot to Desktop") {
                saveSnapshot()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        // Help menu — project links only.
        CommandGroup(replacing: .help) {
            Link("View on GitHub",
                 destination: URL(string: "https://github.com/jamieal/The-Setup-Engine")!)
            Link("Report an Issue",
                 destination: URL(string: "https://github.com/jamieal/The-Setup-Engine/issues/new")!)
        }
    }

    // MARK: - About

    private static var aboutCredits: NSAttributedString {
        let body = """
        A guided macOS setup workflow built with SwiftUI.

        Installs apps via Homebrew Cask, configures system preferences, all without touching Terminal.

        github.com/jamieal/The-Setup-Engine
        """
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        return NSAttributedString(string: body, attributes: attrs)
    }

    private var aboutCredits: NSAttributedString { Self.aboutCredits }

    // MARK: - Logs

    /// Bundles every available log into one .txt and reveals it in Finder.
    /// Falls back to a friendly alert if there's nothing to bundle yet.
    private func collectAndRevealLogs() {
        AppLog.info(.ui, "User requested log bundle")
        if let url = AppLog.bundleAllLogs() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            let alert = NSAlert()
            alert.messageText = "No logs yet"
            alert.informativeText = "Run setup once and the logs will be collected here."
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    private func revealLogsFolder() {
        AppLog.info(.ui, "User opened logs folder")
        let folder = AppLog.logFileURL.deletingLastPathComponent()
        // Make sure the folder exists before revealing it.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func saveSnapshot() {
        AppLog.info(.ui, "User requested window snapshot")
        if let url = WindowSnapshot.saveMainWindowToDesktop() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
