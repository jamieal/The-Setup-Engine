import CryptoKit
import Foundation

// MARK: - Results

/// Why an app couldn't be installed, in words we can show people.
nonisolated enum InstallFailure: Error, Equatable, Sendable {
    case unavailable(String)
    case downloadFailed(String)
    case checksumMismatch
    case unrecognisedDownload
    case appMissing(String)
    case untrusted(String)
    case copyFailed(String)

    var message: String {
        switch self {
        case .unavailable(let why):   why
        case .downloadFailed(let why): "Download failed (\(why))"
        case .checksumMismatch:       "Download didn't match the expected file, so it wasn't installed"
        case .unrecognisedDownload:   "The download wasn't a format we can open"
        case .appMissing(let name):   "\(name) wasn't in the download"
        case .untrusted(let what):    "Apple couldn't verify \(what), so it wasn't installed"
        case .copyFailed(let why):    "Couldn't move it into Applications (\(why))"
        }
    }
}

/// An app that has been downloaded, unpacked and checked, waiting to be put in place.
nonisolated struct StagedApp: Sendable, Hashable {
    let token: String
    let source: URL
    let target: String
}

nonisolated struct StagedPkg: Sendable, Hashable {
    let token: String
    let file: URL
    let choicesXML: URL?
}

nonisolated struct StagedInstall: Sendable {
    let token: String
    let workDir: URL
    var apps: [StagedApp] = []
    var pkgs: [StagedPkg] = []
    /// Who signed it, as Gatekeeper reports it ("Developer ID Application: Name (TEAMID)").
    var signer: String?
}

// MARK: - Installer

/// Installs apps straight from their makers' downloads, the way IT tools like
/// Installomator do, using download links and checksums from Homebrew's catalog.
///
/// For each app: download → check the checksum → unpack (disk image, zip, tar
/// or installer package) → check Apple's signature with Gatekeeper → move the
/// app into /Applications. Installer packages and anything needing admin rights
/// are collected and run together behind one password prompt.
nonisolated struct DirectInstaller: Sendable {
    var applicationsDir = URL(filePath: "/Applications", directoryHint: .isDirectory)
    var workRoot = FileManager.default.temporaryDirectory
        .appending(path: "TheSetupEngine-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)

    /// Downloads, verifies and unpacks a cask. Nothing is installed yet.
    func stage(_ cask: ResolvedCask,
               progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> StagedInstall {
        if let why = cask.unavailableReason { throw InstallFailure.unavailable(why) }
        let r = cask.record

        let workDir = workRoot.appending(path: r.token, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: workDir)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        var staged = StagedInstall(token: r.token, workDir: workDir)

        let download = try await Self.download(r, to: workDir, progress: progress)

        if let expected = r.sha256 {
            let actual = try Self.sha256(of: download)
            guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
                AppLog.error(.install, "\(r.token): checksum mismatch (expected \(expected), got \(actual))")
                throw InstallFailure.checksumMismatch
            }
        } else {
            AppLog.info(.install, "\(r.token): maker publishes no checksum; relying on Apple's signature check")
        }

        var root = try await Self.unpack(download, into: workDir.appending(path: "payload"),
                                         nakedName: r.pkgs.first?.name ?? r.apps.first?.source)
        try? FileManager.default.removeItem(at: download)
        if let nested = r.nestedContainer {
            let inner = root.appending(path: nested)
            guard FileManager.default.fileExists(atPath: inner.path) else {
                throw InstallFailure.appMissing(nested)
            }
            root = try await Self.unpack(inner, into: workDir.appending(path: "nested"), nakedName: nil)
        }

        for app in r.apps {
            guard let found = Self.locate(app.source, in: root) else {
                throw InstallFailure.appMissing(app.target)
            }
            let (trusted, signer) = await Self.gatekeeperAccepts(found, type: "execute")
            guard trusted else { throw InstallFailure.untrusted(app.target) }
            staged.signer = staged.signer ?? signer
            staged.apps.append(StagedApp(token: r.token, source: found, target: app.target))
        }

        for pkg in r.pkgs {
            guard let found = Self.locate(pkg.name, in: root) else {
                throw InstallFailure.appMissing(pkg.name)
            }
            let (trusted, signer) = await Self.gatekeeperAccepts(found, type: "install")
            guard trusted else { throw InstallFailure.untrusted("its installer") }
            staged.signer = staged.signer ?? signer
            let choices = try Self.writeChoicesXML(pkg.choices, in: workDir)
            staged.pkgs.append(StagedPkg(token: r.token, file: found, choicesXML: choices))
        }

        return staged
    }

    /// Moves staged apps into Applications. Returns the ones we weren't allowed to
    /// write (a standard, non-admin account) so they can join the admin batch.
    func place(_ staged: StagedInstall) throws -> [StagedApp] {
        var needAdmin: [StagedApp] = []
        for app in staged.apps {
            let dest = applicationsDir.appending(path: app.target)
            if FileManager.default.fileExists(atPath: dest.path) {
                AppLog.info(.install, "\(app.token): \(app.target) already in place, leaving it alone")
                continue
            }
            do {
                try FileManager.default.moveItem(at: app.source, to: dest)
                AppLog.info(.install, "\(app.token): installed \(dest.path)")
            } catch let error as CocoaError where error.code == .fileWriteNoPermission {
                needAdmin.append(app)
            } catch {
                if (error as NSError).domain == NSPOSIXErrorDomain,
                   [Int(EACCES), Int(EPERM)].contains((error as NSError).code) {
                    needAdmin.append(app)
                } else {
                    throw InstallFailure.copyFailed(error.localizedDescription)
                }
            }
        }
        return needAdmin
    }

    func cleanUp(_ staged: StagedInstall) {
        try? FileManager.default.removeItem(at: staged.workDir)
    }

    func cleanUp(token: String) {
        try? FileManager.default.removeItem(at: workRoot.appending(path: token))
    }

    func cleanUpAll() {
        try? FileManager.default.removeItem(at: workRoot)
    }

    /// Removes work folders left by earlier runs that quit or crashed.
    func sweepStaleWorkFolders() {
        let parent = workRoot.deletingLastPathComponent()
        let mine = workRoot.lastPathComponent
        for name in (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
            where name.hasPrefix("TheSetupEngine-") && name != mine {
            try? FileManager.default.removeItem(at: parent.appending(path: name))
        }
    }

    /// One root shell script for everything that needs a password. Each item
    /// reports `TSE_OK <token>` or `TSE_FAIL <token>` so results can be matched up.
    ///
    /// Staged files live in the user's temp folder, which anything running as
    /// the user could tamper with after our checks. So root first copies each
    /// item into its own root-only folder, verifies the signature again on that
    /// copy, and installs only from the copy.
    func adminScript(apps: [StagedApp], pkgs: [StagedPkg]) -> String {
        var lines = [
            "TSE_ROOT=$(/usr/bin/mktemp -d /private/tmp/tse-root.XXXXXX) || exit 1",
            "trap '/bin/rm -rf \"$TSE_ROOT\"' EXIT",
        ]
        for (i, pkg) in pkgs.enumerated() {
            let copy = "\"$TSE_ROOT/p\(i).pkg\""
            var install = "/usr/sbin/installer -pkg \(copy) -target /"
            var prepare = "/bin/cp \(Self.quote(pkg.file.path)) \(copy)"
            if let xml = pkg.choicesXML {
                prepare += " && /bin/cp \(Self.quote(xml.path)) \"$TSE_ROOT/p\(i).xml\""
                install += " -applyChoiceChangesXML \"$TSE_ROOT/p\(i).xml\""
            }
            let verify = "/usr/sbin/pkgutil --check-signature \(copy) >/dev/null && /usr/sbin/spctl --assess --type install \(copy) 2>/dev/null"
            lines.append("if \(prepare) && \(verify) && \(install); then echo \(Self.quote("TSE_OK \(pkg.token)")); else echo \(Self.quote("TSE_FAIL \(pkg.token)")); fi")
        }
        for (i, app) in apps.enumerated() {
            let dest = Self.quote(applicationsDir.appending(path: app.target).path)
            // Fixed name for the root copy: nothing from the catalog goes inside
            // double quotes. The bundle's name doesn't affect signature checks.
            let copy = "\"$TSE_ROOT/a\(i).app\""
            let prepare = "/usr/bin/ditto \(Self.quote(app.source.path)) \(copy)"
            let verify = "/usr/bin/codesign --verify \(copy) && /usr/sbin/spctl --assess --type execute \(copy) 2>/dev/null"
            lines.append("if [ -e \(dest) ] || { \(prepare) && \(verify) && /usr/bin/ditto \(copy) \(dest); }; then echo \(Self.quote("TSE_OK \(app.token)")); else echo \(Self.quote("TSE_FAIL \(app.token)")); fi")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Download

    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// Homebrew's catalog is tested with curl, and some download servers send
    /// browsers an HTML "your download will start" page instead of the file
    /// (VLC's mirror redirector does). So by default we identify like curl.
    static let defaultUserAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let arch = MacEnvironment.chip == .appleSilicon ? "arm64" : "x86_64"
        return "TheSetupEngine/\(version) (Macintosh; \(arch) Mac OS X \(MacEnvironment.macOSVersionString)) curl/8.7.1"
    }()

    private static func download(_ r: CaskRecord, to dir: URL,
                                 progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let url = URL(string: r.url) else { throw InstallFailure.downloadFailed("bad link") }
        var request = URLRequest(url: url, timeoutInterval: 120)
        switch r.urlSpecs.userAgent {
        case nil, ":default"?: request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
        case ":fake"?, ":browser"?: request.setValue(safariUserAgent, forHTTPHeaderField: "User-Agent")
        case let custom?: request.setValue(custom, forHTTPHeaderField: "User-Agent")
        }
        if let referer = r.urlSpecs.referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        for header in r.urlSpecs.headers {
            let parts = header.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { request.setValue(parts[1], forHTTPHeaderField: parts[0]) }
        }

        let delegate = DownloadProgress(progress)
        do {
            let (temp, response) = try await downloadRetrying(request, delegate: delegate)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                try? FileManager.default.removeItem(at: temp)
                throw InstallFailure.downloadFailed("HTTP \(http.statusCode)")
            }
            if response.mimeType == "text/html" {
                try? FileManager.default.removeItem(at: temp)
                AppLog.error(.install, "\(r.token): got a web page instead of the app from \(response.url?.absoluteString ?? r.url)")
                throw InstallFailure.downloadFailed("the maker's site sent a web page instead of the app")
            }
            let name = response.suggestedFilename ?? url.lastPathComponent
            let dest = dir.appending(path: "download-" + (name.isEmpty ? "file" : name))
            try FileManager.default.moveItem(at: temp, to: dest)
            progress(1)
            return dest
        } catch let failure as InstallFailure {
            throw failure
        } catch {
            throw InstallFailure.downloadFailed(error.localizedDescription)
        }
    }

    /// One retry for connection hiccups (dropped Wi-Fi, a slow mirror timing out).
    private static func downloadRetrying(_ request: URLRequest,
                                         delegate: DownloadProgress) async throws -> (URL, URLResponse) {
        let transient: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet]
        do {
            return try await URLSession.shared.download(for: request, delegate: delegate)
        } catch let error as URLError where transient.contains(error.code) {
            AppLog.warn(.install, "Download hiccup (\(error.code.rawValue)), retrying \(request.url?.host() ?? "")")
            try await Task.sleep(for: .seconds(3))
            return try await URLSession.shared.download(for: request, delegate: delegate)
        }
    }

    private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        let report: @Sendable (Double) -> Void
        init(_ report: @escaping @Sendable (Double) -> Void) { self.report = report }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            guard totalBytesExpectedToWrite > 0 else { return }
            report(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {}
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Unpack

    enum PayloadKind: Equatable { case dmg, zip, tar, pkg, unknown }

    /// Identifies a download by its bytes; link extensions are unreliable
    /// ("…/download?build=123", ".php").
    static func kind(of file: URL) -> PayloadKind {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return .unknown }
        defer { try? handle.close() }
        // UDIF disk images end with a 512-byte "koly" trailer. Check this first:
        // compressed images (bzip2/xz/lzfse) start with the same bytes as tarballs.
        if let size = try? handle.seekToEnd(), size >= 512 {
            try? handle.seek(toOffset: size - 512)
            if let tail = try? handle.read(upToCount: 4), tail == Data("koly".utf8) { return .dmg }
        }
        try? handle.seek(toOffset: 0)
        let head = [UInt8]((try? handle.read(upToCount: 8)) ?? Data())
        func starts(_ bytes: [UInt8]) -> Bool { head.starts(with: bytes) }

        if starts([0x78, 0x61, 0x72, 0x21]) { return .pkg }                  // "xar!"
        if starts([0x50, 0x4B, 0x03, 0x04]) { return .zip }                  // "PK\3\4"
        if starts([0x1F, 0x8B]) || starts([0x42, 0x5A, 0x68])                 // gzip, bzip2
            || starts([0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) { return .tar }   // xz
        return .unknown
    }

    /// Unpacks a download into `dir` and returns the folder its contents live in.
    static func unpack(_ file: URL, into dir: URL, nakedName: String?) async throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        switch kind(of: file) {
        case .zip:
            try await expect(run("/usr/bin/ditto", ["-x", "-k", file.path, dir.path]))
        case .tar:
            try await expect(run("/usr/bin/tar", ["-xf", file.path, "-C", dir.path]))
        case .pkg:
            // A bare installer package: name it as the cask expects to find it.
            let name = nakedName.flatMap { $0.hasSuffix("pkg") ? $0 : nil } ?? "installer.pkg"
            try FileManager.default.copyItem(at: file, to: dir.appending(path: name))
        case .dmg:
            try await copyOutOfDiskImage(file, into: dir)
        case .unknown:
            // Some disk images lack the trailer we look for; let hdiutil decide.
            do { try await copyOutOfDiskImage(file, into: dir) }
            catch { throw InstallFailure.unrecognisedDownload }
        }
        return dir
    }

    private static func copyOutOfDiskImage(_ dmg: URL, into dir: URL) async throws {
        let mountRoot = dir.deletingLastPathComponent().appending(path: "mnt-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: mountRoot, withIntermediateDirectories: true)
        // "Y" answers a licence agreement if the image shows one.
        let attach = await run("/usr/bin/hdiutil",
                               ["attach", "-nobrowse", "-readonly", "-noautoopen", "-noverify",
                                "-mountrandom", mountRoot.path, "-plist", dmg.path],
                               stdin: "Y\n")
        guard attach.status == 0 else { throw InstallFailure.unrecognisedDownload }
        guard let mount = mountPoint(fromPlist: attach.stdout) else {
            // Attached but unreadable output: detach whatever landed under our mount root.
            for leftover in (try? FileManager.default.contentsOfDirectory(atPath: mountRoot.path)) ?? [] {
                _ = await run("/usr/bin/hdiutil", ["detach", "-force", mountRoot.appending(path: leftover).path])
            }
            throw InstallFailure.unrecognisedDownload
        }
        let copied = await run("/usr/bin/ditto", [mount, dir.path])
        _ = await run("/usr/bin/hdiutil", ["detach", "-force", mount])
        try? FileManager.default.removeItem(at: mountRoot)
        try expect(copied)
    }

    private static func mountPoint(fromPlist output: Data) -> String? {
        // hdiutil can print the licence text before the plist; start at the XML.
        guard let start = output.range(of: Data("<?xml".utf8)) else { return nil }
        let xml = output[start.lowerBound...]
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(xml), format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else { return nil }
        return entities.compactMap { $0["mount-point"] as? String }.first
    }

    /// Finds an artifact at its expected path, or by name a few levels down.
    /// Refuses anything that would lead outside the download: ".." or absolute
    /// paths from the catalog, and symlinks (Gatekeeper would check the link's
    /// target while we'd install the link itself).
    static func locate(_ relativePath: String, in root: URL) -> URL? {
        let parts = relativePath.split(separator: "/")
        guard !relativePath.hasPrefix("/"), !parts.contains(where: { $0 == ".." }) else {
            AppLog.error(.install, "Refusing catalog path outside the download: \(relativePath)")
            return nil
        }
        func acceptable(_ url: URL) -> Bool {
            let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            let inside = url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
            if isLink { AppLog.error(.install, "Refusing symlink in download: \(url.lastPathComponent)") }
            return !isLink && inside
        }
        let direct = root.appending(path: relativePath)
        if (try? direct.checkResourceIsReachable()) == true || isSymlink(direct) {
            return acceptable(direct) ? direct : nil
        }
        let name = (relativePath as NSString).lastPathComponent
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { return nil }
        for case let url as URL in walker {
            if walker.level > 3 { walker.skipDescendants(); continue }
            if url.lastPathComponent == name { return acceptable(url) ? url : nil }
            if url.pathExtension == "app" || url.pathExtension == "pkg" { walker.skipDescendants() }
        }
        return nil
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    // MARK: - Trust

    /// Asks Gatekeeper whether Apple trusts this app or package (Developer ID
    /// signed and notarized, or from the App Store). Returns the signer too.
    static func gatekeeperAccepts(_ item: URL, type: String) async -> (Bool, String?) {
        // Check the signature directly too: if someone has switched Gatekeeper
        // off, spctl approves everything ("override=security disabled").
        let signature = type == "install"
            ? await run("/usr/sbin/pkgutil", ["--check-signature", item.path])
            : await run("/usr/bin/codesign", ["--verify", item.path])
        guard signature.status == 0 else {
            AppLog.warn(.install, "Signature check failed for \(item.lastPathComponent): \(String(decoding: signature.stderr, as: UTF8.self))")
            return (false, nil)
        }
        let result = await run("/usr/sbin/spctl", ["--assess", "--type", type, "-vv", item.path])
        let text = String(decoding: result.stdout + result.stderr, as: UTF8.self)
        let signer = text.split(separator: "\n")
            .first { $0.hasPrefix("origin=") }
            .map { String($0.dropFirst("origin=".count)) }
        if result.status != 0 {
            AppLog.warn(.install, "Gatekeeper rejected \(item.lastPathComponent): \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return (result.status == 0, signer)
    }

    private static func writeChoicesXML(_ choices: [CaskRecord.Choice], in dir: URL) throws -> URL? {
        guard !choices.isEmpty else { return nil }
        let array = choices.map {
            ["choiceIdentifier": $0.identifier, "choiceAttribute": $0.attribute, "attributeSetting": $0.setting] as [String: Any]
        }
        let data = try PropertyListSerialization.data(fromPropertyList: array, format: .xml, options: 0)
        let url = dir.appending(path: "choices.xml")
        try data.write(to: url)
        return url
    }

    // MARK: - Processes

    struct ProcessResult: Sendable {
        let status: Int32
        let stdout: Data
        let stderr: Data
    }

    /// Runs a program directly (no shell), reading its output without blocking.
    static func run(_ executable: String, _ arguments: [String], stdin: String? = nil) async -> ProcessResult {
        await withCheckedContinuation { (cont: CheckedContinuation<ProcessResult, Never>) in
            let p = Process()
            p.executableURL = URL(filePath: executable)
            p.arguments = arguments
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            let input = Pipe()
            p.standardInput = input

            let group = DispatchGroup()
            nonisolated(unsafe) var outData = Data()
            nonisolated(unsafe) var errData = Data()
            group.enter()
            DispatchQueue.global().async { outData = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
            group.enter()
            DispatchQueue.global().async { errData = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }

            p.terminationHandler = { proc in
                group.notify(queue: .global()) {
                    cont.resume(returning: ProcessResult(status: proc.terminationStatus, stdout: outData, stderr: errData))
                }
            }
            do {
                try p.run()
                if let stdin { input.fileHandleForWriting.write(Data(stdin.utf8)) }
                try? input.fileHandleForWriting.close()
            } catch {
                try? out.fileHandleForWriting.close()
                try? err.fileHandleForWriting.close()
                group.notify(queue: .global()) {
                    cont.resume(returning: ProcessResult(status: -1, stdout: Data(), stderr: Data(error.localizedDescription.utf8)))
                }
            }
        }
    }

    private static func expect(_ result: ProcessResult) throws {
        guard result.status == 0 else {
            let why = String(decoding: result.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            AppLog.error(.install, "Unpack failed: \(why)")
            throw InstallFailure.unrecognisedDownload
        }
    }

    /// Single-quotes a string for /bin/sh.
    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
