import Foundation

/// Lightweight logger — prints to Xcode console + mirrors to a file users can collect.
///
/// File: ~/Library/Application Support/TheSetupEngine/Logs/setup-engine.log
///
/// Usage:
///   AppLog.info(.install, "Starting install of \(cask)")
///   AppLog.error(.homebrew, "Install failed: \(message)")
enum AppLog {
    enum Category: String {
        case general
        case homebrew
        case install
        case settings
        case ui
    }

    enum Level: String {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    /// On-disk log path. Created lazily; safe to call from any thread.
    static let logFileURL: URL = {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = appSupport.appending(path: "TheSetupEngine/Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "setup-engine.log")
    }()

    static func info(_ category: Category, _ message: String) {
        write(.info, category, message)
    }

    static func warn(_ category: Category, _ message: String) {
        write(.warn, category, message)
    }

    static func error(_ category: Category, _ message: String) {
        write(.error, category, message)
    }

    /// All log files we care about for diagnostics.
    static var allLogPaths: [String] {
        [
            logFileURL.path,
            "/tmp/the_setup_engine_admin.log",
            "/tmp/the_setup_engine_install.log",
        ]
    }

    /// Bundles every available log into one annotated text file. Returns the URL
    /// of the bundle (in the user's Caches dir) or nil if nothing was readable.
    static func bundleAllLogs() -> URL? {
        var output = "=== The Setup Engine — Diagnostic Logs ===\n"
        output += "Generated: \(ISO8601DateFormatter().string(from: Date()))\n"
        output += "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build   = info?["CFBundleVersion"]            as? String ?? "?"
        output += "App version: \(version) (\(build))\n"
        output += "Architecture: \(currentArchitecture())\n\n"

        var any = false
        for path in allLogPaths {
            output += "\n========================================\n"
            output += "=== \(path)\n"
            output += "========================================\n"
            if let contents = try? String(contentsOfFile: path) {
                output += contents
                any = true
            } else {
                output += "[file not present or unreadable]\n"
            }
        }

        guard any else { return nil }

        let cache = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first!
        let stamp = Int(Date().timeIntervalSince1970)
        let url = cache.appending(path: "TheSetupEngine-logs-\(stamp).txt")
        try? output.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Internals

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let queue = DispatchQueue(label: "com.jamie.The-Setup-Engine.AppLog")

    private static func write(_ level: Level, _ category: Category, _ message: String) {
        let line = "[\(formatter.string(from: Date()))] [\(level.rawValue)] [\(category.rawValue)] \(message)"
        print(line)
        queue.async {
            appendToFile(line)
        }
    }

    private static func appendToFile(_ line: String) {
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFileURL)
        }
    }

    private static func currentArchitecture() -> String {
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
