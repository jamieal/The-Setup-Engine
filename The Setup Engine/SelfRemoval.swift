import AppKit
import Foundation

/// "One and done" (#16): when setup is finished, The Setup Engine deletes
/// everything it stored and moves itself to the Trash. Your apps, settings,
/// and the receipt in ~/Documents/The Setup Engine stay.
enum SelfRemoval {
    static var bundleURL: URL { Bundle.main.bundleURL }

    /// False when running from a disk image, a read-only location, or
    /// macOS's App Translocation (an un-moved download): the app can't delete
    /// itself there, so we ask people to drag it to the Trash instead.
    static var canRemoveItself: Bool {
        let path = bundleURL.path
        guard !path.contains("/AppTranslocation/"), !path.hasPrefix("/Volumes/") else { return false }
        return FileManager.default.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path)
    }

    /// Everything the app keeps outside its own bundle.
    static var traces: [URL] {
        let fm = FileManager.default
        let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let id = Bundle.main.bundleIdentifier ?? "com.jamie.The-Setup-Engine"
        return [
            CaskCatalog.cacheDirectory,                                         // Caches/TheSetupEngine
            AppLog.logFileURL.deletingLastPathComponent().deletingLastPathComponent(), // Application Support/TheSetupEngine
            library.appending(path: "Caches/\(id)"),                            // URL cache (icons)
            library.appending(path: "HTTPStorages/\(id)"),
            library.appending(path: "HTTPStorages/\(id).binarycookies"),
            library.appending(path: "Saved Application State/\(id).savedState"),
            library.appending(path: "WebKit/\(id)"),
        ]
    }

    static func removeTraces() {
        for url in traces {
            try? FileManager.default.removeItem(at: url)
        }
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        // Leftover per-run temp folders.
        DirectInstaller().cleanUpAll()
        DirectInstaller().sweepStaleWorkFolders()
    }

    /// Removes all traces, moves the app to the Trash, and quits.
    /// Returns false (and leaves the app in place) if it couldn't be trashed.
    @discardableResult
    static func removeAndQuit() -> Bool {
        removeTraces()
        guard canRemoveItself else { return false }
        do {
            // A running app can be moved to the Trash; it keeps running until it quits.
            try FileManager.default.trashItem(at: bundleURL, resultingItemURL: nil)
        } catch {
            return false
        }
        // Preferences can be re-written on quit; remove them again just before exit.
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
            UserDefaults.standard.synchronize()
        }
        NSApp.terminate(nil)
        return true
    }
}
