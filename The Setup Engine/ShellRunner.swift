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

    /// Log for admin operations — check this for debugging. Lives in the user's
    /// own Logs folder rather than shared /tmp, so other accounts can't tamper
    /// with a file that root writes to.
    nonisolated static var adminLogPath: String {
        AppLog.logFileURL.deletingLastPathComponent().appending(path: "admin.log").path
    }

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

    /// Runs a script as root behind the native macOS password dialog.
    ///
    /// The script never touches disk: it's base64-encoded into the
    /// `do shell script` call itself, so nothing another process could swap
    /// sits between the password prompt and root running it. Root's output
    /// comes back to us, and we (not root) write it to the admin log.
    /// Returns false if the prompt was cancelled or the script failed to run.
    @discardableResult
    func runWithAdmin(_ command: String) async -> Bool {
        output = ""
        isRunning = true
        defer { isRunning = false }

        let script = "set -u\nexport PATH=/usr/bin:/bin:/usr/sbin:/sbin\n" + command + "\nexit 0\n"
        let encoded = Data(script.utf8).base64EncodedString()
        let appleScript = "do shell script \"/bin/echo \(encoded) | /usr/bin/base64 -D | /bin/bash 2>&1\" with administrator privileges"

        let osa = Process()
        osa.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osa.arguments = ["-e", appleScript]
        let outPipe = Pipe(), errPipe = Pipe()
        osa.standardOutput = outPipe
        osa.standardError = errPipe

        // Drain both pipes while it runs so a chatty installer can't fill them.
        async let outData = Task.detached { outPipe.fileHandleForReading.readDataToEndOfFile() }.value
        async let errData = Task.detached { errPipe.fileHandleForReading.readDataToEndOfFile() }.value
        let exitCode = await Self.runAsync(osa)
        if exitCode == -1 {
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()
        }
        let stdout = String(decoding: await outData, as: UTF8.self)
        let stderr = String(decoding: await errData, as: UTF8.self)

        output = stdout
        if !stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output += "\n--- osascript ---\n\(stderr)"
        }
        output += "\n[Process exited with code \(exitCode)]\n"

        let log = "=== The Setup Engine — admin run \(Date()) ===\n" + script + "\n=== output ===\n" + output
        try? log.write(toFile: Self.adminLogPath, atomically: true, encoding: .utf8)
        return exitCode == 0
    }
}
