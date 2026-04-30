import AppKit

/// Saves a PNG of the app's main window to ~/Desktop. Uses NSView.cacheDisplay,
/// which captures the window's own drawing — works without Screen Recording
/// permission because we're not capturing the screen, we're rendering into our
/// own bitmap. Useful for screenshots / marketing without needing system perms.
enum WindowSnapshot {
    @discardableResult
    static func saveMainWindowToDesktop() -> URL? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible }),
              let view = window.contentView
        else {
            AppLog.warn(.ui, "No window available for snapshot")
            return nil
        }

        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else {
            AppLog.warn(.ui, "Could not create bitmap rep")
            return nil
        }
        view.cacheDisplay(in: bounds, to: rep)

        guard let pngData = rep.representation(using: .png, properties: [:]) else {
            AppLog.warn(.ui, "Could not encode PNG")
            return nil
        }

        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default
            .urls(for: .desktopDirectory, in: .userDomainMask).first!
            .appending(path: "TheSetupEngine-Window-\(stamp).png")

        do {
            try pngData.write(to: url)
            AppLog.info(.ui, "Saved window snapshot: \(url.path)")
            return url
        } catch {
            AppLog.error(.ui, "Snapshot save failed: \(error.localizedDescription)")
            return nil
        }
    }
}
