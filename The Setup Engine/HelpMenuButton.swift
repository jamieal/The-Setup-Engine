import AppKit
import SwiftUI

/// Floating "?" button in the top-right of the window. Opens a small menu with
/// log collection + repo links — mirrors the Help menu in the menu bar so users
/// who don't think to look there still find it.
struct HelpMenuButton: View {
    var body: some View {
        Menu {
            // Version lives in the dropdown header (and the About panel) —
            // not in the main content area where it adds visual noise.
            Section("The Setup Engine \(AppVersion.shortLabel)") {}

            Button {
                collectLogs()
            } label: {
                Label("Collect Diagnostic Logs…", systemImage: "doc.text.magnifyingglass")
            }

            Button {
                revealLogs()
            } label: {
                Label("Reveal Logs in Finder", systemImage: "folder")
            }

            Divider()

            Link(destination: URL(string: "https://github.com/jamieal/The-Setup-Engine")!) {
                Label("View on GitHub", systemImage: "link")
            }

            Link(destination: URL(string: "https://github.com/jamieal/The-Setup-Engine/issues/new")!) {
                Label("Report an Issue", systemImage: "exclamationmark.bubble")
            }
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("Help & diagnostics")
    }

    // MARK: - Actions (shared with AppCommands menu items)

    private func collectLogs() {
        AppLog.info(.ui, "User requested log bundle (in-app help)")
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

    private func revealLogs() {
        AppLog.info(.ui, "User opened logs folder (in-app help)")
        let folder = AppLog.logFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}
