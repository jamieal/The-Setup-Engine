//
//  ShellRunner.swift
//  The Setup Engine
//
//  Created by Jamie Cras on 09/03/2026.
//

import Combine
import Foundation

/// Runs shell commands via /bin/zsh and streams stdout/stderr output.
@MainActor
class ShellRunner: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning: Bool = false

    /// Homebrew PATH — covers both Apple Silicon and Intel installs.
    static let brewPaths = "/opt/homebrew/bin:/usr/local/bin"

    /// Fixed log path for admin operations — check this for debugging.
    static let adminLogPath = "/tmp/the_setup_engine_admin.log"

    /// Builds an environment dictionary with Homebrew on the PATH.
    static func brewEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "\(brewPaths):\(existingPath)"
        return env
    }

    /// Runs a shell command asynchronously, streaming output line-by-line.
    /// Returns `true` on exit code 0. Never blocks the main actor — waiting is done via
    /// `terminationHandler`.
    @discardableResult
    func run(_ command: String, clearOutput: Bool = true) async -> Bool {
        if clearOutput {
            output = ""
        }
        isRunning = true

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = Self.brewEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Stream stdout/stderr to the @Published `output` as it arrives (non-blocking).
        let streamTask = Task { [weak self] in
            let handle = pipe.fileHandleForReading
            do {
                for try await line in handle.bytes.lines {
                    guard !Task.isCancelled else { break }
                    await MainActor.run { self?.output += line + "\n" }
                }
            } catch {
                await MainActor.run {
                    self?.output += "Read error: \(error.localizedDescription)\n"
                }
            }
        }

        let exitCode = await Self.runAsync(process)
        streamTask.cancel()
        isRunning = false
        return exitCode == 0
    }

    /// Awaits a Process via its termination handler — does not block the calling actor.
    /// Returns -1 if the process couldn't be started.
    fileprivate static func runAsync(_ process: Process) async -> Int32 {
        await withCheckedContinuation { (cont: CheckedContinuation<Int32, Never>) in
            process.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
            do {
                try process.run()
            } catch {
                cont.resume(returning: -1)
            }
        }
    }

    /// Runs a command with administrator privileges using the native macOS password dialog.
    /// Writes a temp script, runs it via osascript, logs to /tmp/, streams that log to the UI.
    /// Never blocks the main actor — waiting is done via `terminationHandler`.
    @discardableResult
    func runWithAdmin(_ command: String) async -> Bool {
        output = ""
        isRunning = true
        defer { isRunning = false }

        let logPath = Self.adminLogPath
        let scriptPath = "/tmp/the_setup_engine_run.sh"

        let scriptContent = """
        #!/bin/bash
        export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        LOG="\(logPath)"
        echo "=== The Setup Engine ===" > "$LOG"
        echo "Started: $(date)" >> "$LOG"
        echo "========================" >> "$LOG"

        ( \(command) ) >> "$LOG" 2>&1
        EXIT_CODE=$?

        echo "" >> "$LOG"
        echo "=== Exit code: $EXIT_CODE ===" >> "$LOG"
        echo "Finished: $(date)" >> "$LOG"
        exit $EXIT_CODE
        """

        do {
            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        } catch {
            output = "Failed to create script: \(error.localizedDescription)\n"
            return false
        }

        // chmod +x — run async so we don't block.
        let chmod = Process()
        chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmod.arguments = ["+x", scriptPath]
        _ = await Self.runAsync(chmod)

        FileManager.default.createFile(atPath: logPath, contents: nil)

        // Start tailing the log so the UI sees progress as the install runs.
        let tailProcess = Process()
        tailProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        tailProcess.arguments = ["-f", logPath]
        let tailPipe = Pipe()
        tailProcess.standardOutput = tailPipe
        try? tailProcess.run()

        let streamTask = Task { [weak self] in
            let handle = tailPipe.fileHandleForReading
            do {
                for try await line in handle.bytes.lines {
                    guard !Task.isCancelled else { break }
                    await MainActor.run { self?.output += line + "\n" }
                }
            } catch {
                // expected when tail is terminated
            }
        }

        // Run osascript with admin privileges (shows native password dialog).
        // Wait via terminationHandler — does NOT block the main actor.
        let appleScript = "do shell script \"/bin/bash \\\"" + scriptPath + "\\\"\" with administrator privileges"
        let osa = Process()
        osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osa.arguments = ["-e", appleScript]
        let osaPipe = Pipe()
        osa.standardOutput = osaPipe
        osa.standardError = osaPipe

        let exitCode = await Self.runAsync(osa)

        // Let tail catch up with the final lines, then cancel.
        try? await Task.sleep(for: .milliseconds(800))
        if tailProcess.isRunning {
            tailProcess.terminate()
        }
        streamTask.cancel()

        // Capture osascript's own error output (e.g. user cancelled the password dialog).
        let osaData = osaPipe.fileHandleForReading.readDataToEndOfFile()
        let osaOutput = String(data: osaData, encoding: .utf8) ?? ""

        // Read the complete log file as the canonical output.
        if let logData = try? Data(contentsOf: URL(fileURLWithPath: logPath)),
           let logOutput = String(data: logData, encoding: .utf8),
           !logOutput.isEmpty {
            output = logOutput
        }
        if !osaOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output += "\n--- osascript ---\n\(osaOutput)"
        }
        output += "\n[Process exited with code \(exitCode)]\n"
        output += "[Log saved to \(logPath)]\n"

        try? FileManager.default.removeItem(atPath: scriptPath)
        return exitCode == 0
    }
}
