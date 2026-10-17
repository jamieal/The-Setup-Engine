import Combine
import Foundation

// MARK: - Records

/// One app from Homebrew's public cask catalog (formulae.brew.sh/api/cask.json),
/// trimmed to what The Setup Engine needs to download and install it itself.
///
/// We only *read* Homebrew's catalog — the download links, versions and checksums
/// its community keeps up to date. Apps are installed directly, without Homebrew.
nonisolated struct CaskRecord: Codable, Sendable, Hashable {
    struct AppArtifact: Codable, Sendable, Hashable {
        /// Path of the .app inside the download (may include folders).
        let source: String
        /// Bundle name it's installed as, e.g. "Visual Studio Code.app".
        let target: String
    }

    struct PkgArtifact: Codable, Sendable, Hashable {
        /// Path of the .pkg inside the download.
        let name: String
        /// Installer choices to override (Homebrew's `choices:`), applied via
        /// `installer -applyChoiceChangesXML`.
        let choices: [Choice]
    }

    struct Choice: Codable, Sendable, Hashable {
        let identifier: String
        let attribute: String
        let setting: Int
    }

    struct URLSpecs: Codable, Sendable, Hashable {
        var userAgent: String?
        var referer: String?
        var headers: [String] = []
        /// Cookies, POST requests or form data — not supported by our downloader.
        var unsupported = false
    }

    /// Fields a `variations` entry can override for one chip + macOS combination.
    struct Override: Codable, Sendable, Hashable {
        var url: String?
        var sha256: String?
        var version: String?
        var apps: [AppArtifact]?
        var pkgs: [PkgArtifact]?
        var minMacOS: String?
        var nestedContainer: String?
    }

    let token: String
    let name: String
    let desc: String?
    let homepage: String?
    var version: String
    var url: String
    /// nil when Homebrew marks the download `no_check` (it changes without notice).
    var sha256: String?
    var urlSpecs: URLSpecs
    var apps: [AppArtifact]
    var pkgs: [PkgArtifact]
    /// Archive inside the download that holds the real payload (Homebrew `container nested:`).
    var nestedContainer: String?
    var minMacOS: String?
    var maxMacOS: String?
    /// "arm" or "intel" when the app only runs on one chip.
    var requiredArch: String?
    let autoUpdates: Bool
    let deprecated: Bool
    let disabled: Bool
    var variations: [String: Override]

    var isInstallable: Bool { !apps.isEmpty || !pkgs.isEmpty }
}

/// A record with this Mac's variation applied, plus whether it can install here.
nonisolated struct ResolvedCask: Sendable, Hashable {
    let record: CaskRecord
    let unavailableReason: String?

    var token: String { record.token }
    var isAvailable: Bool { unavailableReason == nil }

    /// Bundle names this app installs into /Applications.
    var installedAppNames: [String] { record.apps.map(\.target) }

    init(_ base: CaskRecord, variationKey: String = MacEnvironment.variationKey,
         chip: MacEnvironment.Chip = MacEnvironment.chip,
         macOSMajor: Int = MacEnvironment.macOSMajor) {
        var r = base
        if let o = base.variations[variationKey] {
            if let v = o.url { r.url = v }
            if let v = o.sha256 { r.sha256 = v == "no_check" ? nil : v }
            if let v = o.version { r.version = v }
            if let v = o.apps { r.apps = v }
            if let v = o.pkgs { r.pkgs = v }
            if let v = o.minMacOS { r.minMacOS = v }
            if let v = o.nestedContainer { r.nestedContainer = v }
        }
        r.variations = [:]
        record = r

        if base.disabled {
            unavailableReason = "No longer available from its maker"
        } else if r.requiredArch == "arm" && chip == .intel {
            unavailableReason = "Needs an Apple Silicon Mac"
        } else if r.requiredArch == "intel" && chip == .appleSilicon {
            unavailableReason = "Only runs on Intel Macs"
        } else if let min = r.minMacOS, let m = Self.major(min), macOSMajor < m {
            unavailableReason = "Needs macOS \(min) or later"
        } else if let max = r.maxMacOS, let m = Self.major(max), macOSMajor > m {
            unavailableReason = "Doesn't support this version of macOS"
        } else if !r.isInstallable || r.urlSpecs.unsupported {
            unavailableReason = "Can't be installed by The Setup Engine yet"
        } else {
            unavailableReason = nil
        }
    }

    private static func major(_ version: String) -> Int? {
        // "10.15" → 10 is fine: every supported Mac is newer than any 10.x.
        Int(version.split(separator: ".").first ?? "")
    }
}

// MARK: - Parsing Homebrew's JSON

nonisolated enum CaskParser {

    /// Parses an array of raw Homebrew cask objects (the API's format) into records.
    /// Entries that can't be parsed or have nothing we can install are dropped.
    static func records(fromRawJSON data: Data) throws -> [CaskRecord] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return array.compactMap(record(from:)).filter { $0.isInstallable || !$0.variations.isEmpty }
    }

    static func record(from c: [String: Any]) -> CaskRecord? {
        guard let token = c["token"] as? String,
              let url = c["url"] as? String
        else { return nil }

        let (apps, pkgs) = artifacts(c["artifacts"])
        let depends = c["depends_on"] as? [String: Any] ?? [:]
        let (minOS, maxOS) = macOSBounds(depends["macos"])

        var variations: [String: CaskRecord.Override] = [:]
        for (key, value) in c["variations"] as? [String: Any] ?? [:] {
            guard !key.hasSuffix("_linux"), let v = value as? [String: Any] else { continue }
            var o = CaskRecord.Override()
            o.url = v["url"] as? String
            o.sha256 = v["sha256"] as? String
            o.version = v["version"] as? String
            if v["artifacts"] != nil {
                let (a, p) = artifacts(v["artifacts"])
                o.apps = a
                o.pkgs = p
            }
            if let d = v["depends_on"] as? [String: Any] {
                o.minMacOS = macOSBounds(d["macos"]).min
            }
            o.nestedContainer = (v["container"] as? [String: Any])?["nested"] as? String
            variations[key] = o
        }

        let sha = c["sha256"] as? String
        return CaskRecord(
            token: token,
            name: (c["name"] as? [String])?.first ?? token,
            desc: c["desc"] as? String,
            homepage: c["homepage"] as? String,
            version: c["version"] as? String ?? "latest",
            url: url,
            sha256: sha == "no_check" ? nil : sha,
            urlSpecs: urlSpecs(c["url_specs"]),
            apps: apps,
            pkgs: pkgs,
            nestedContainer: (c["container"] as? [String: Any])?["nested"] as? String,
            minMacOS: minOS,
            maxMacOS: maxOS,
            requiredArch: requiredArch(depends["arch"]),
            autoUpdates: c["auto_updates"] as? Bool ?? false,
            deprecated: c["deprecated"] as? Bool ?? false,
            disabled: c["disabled"] as? Bool ?? false,
            variations: variations
        )
    }

    private static func artifacts(_ raw: Any?) -> ([CaskRecord.AppArtifact], [CaskRecord.PkgArtifact]) {
        var apps: [CaskRecord.AppArtifact] = []
        var pkgs: [CaskRecord.PkgArtifact] = []
        for entry in raw as? [[String: Any]] ?? [] {
            if let list = entry["app"] as? [Any], let source = list.first as? String {
                // Target comes either as a top-level "target" (absolute path) or as
                // an options hash after the source: ["Foo.app", {"target": "Bar.app"}].
                let options = list.dropFirst().first as? [String: Any]
                let rawTarget = (entry["target"] as? String) ?? (options?["target"] as? String)
                let target = (rawTarget ?? source).split(separator: "/").last.map(String.init) ?? source
                apps.append(.init(source: source, target: target))
            }
            if let list = entry["pkg"] as? [Any], let name = list.first as? String {
                let options = list.dropFirst().first as? [String: Any]
                let choices = (options?["choices"] as? [[String: Any]] ?? []).compactMap { ch -> CaskRecord.Choice? in
                    guard let id = ch["choiceIdentifier"] as? String,
                          let attr = ch["choiceAttribute"] as? String,
                          let setting = ch["attributeSetting"] as? Int
                    else { return nil }
                    return .init(identifier: id, attribute: attr, setting: setting)
                }
                pkgs.append(.init(name: name, choices: choices))
            }
        }
        return (apps, pkgs)
    }

    private static func macOSBounds(_ raw: Any?) -> (min: String?, max: String?) {
        guard let dict = raw as? [String: Any] else { return (nil, nil) }
        let min = (dict[">="] as? [String])?.first
        let max = (dict["<="] as? [String])?.first
        if let exact = (dict["=="] as? [String])?.first { return (exact, exact) }
        return (min, max)
    }

    private static func requiredArch(_ raw: Any?) -> String? {
        let types = (raw as? [[String: Any]] ?? []).compactMap { $0["type"] as? String }
        return types.count == 1 ? types[0] : nil
    }

    private static func urlSpecs(_ raw: Any?) -> CaskRecord.URLSpecs {
        guard let dict = raw as? [String: Any] else { return .init() }
        var specs = CaskRecord.URLSpecs()
        specs.userAgent = dict["user_agent"] as? String
        specs.referer = dict["referer"] as? String
        if let h = dict["header"] as? String { specs.headers = [h] }
        if let h = dict["header"] as? [String] { specs.headers = h }
        specs.unsupported = dict["cookies"] != nil || dict["using"] != nil || dict["data"] != nil
        return specs
    }
}

// MARK: - Catalog

/// Homebrew's app catalog, cached locally and refreshed in the background.
///
/// Load order: on-disk cache (refreshed with an ETag, so unchanged data isn't
/// re-downloaded) → the snapshot bundled in the app (covers our curated apps
/// if the Mac is offline on first launch).
@MainActor
final class CaskCatalog: ObservableObject {
    static let shared = CaskCatalog()

    nonisolated static let apiURL = URL(string: "https://formulae.brew.sh/api/cask.json")!

    @Published private(set) var isLoaded = false
    @Published private(set) var isFresh = false

    private var records: [String: CaskRecord] = [:]
    private var resolvedCache: [String: ResolvedCask] = [:]
    private var loadTask: Task<Void, Never>?

    nonisolated static var cacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appending(path: "TheSetupEngine", directoryHint: .isDirectory)
    }
    nonisolated private static var cacheFile: URL { cacheDirectory.appending(path: "catalog.json") }
    nonisolated private static var etagFile: URL { cacheDirectory.appending(path: "catalog.etag") }

    /// Loads the cache (or bundled snapshot) and returns; a refresh from the
    /// network carries on in the background. Safe to call repeatedly.
    func load() async {
        if let loadTask { return await loadTask.value }
        let task = Task {
            let local = await Task.detached { Self.loadLocal() }.value
            self.install(local)
            Task {
                if let fresh = await Task.detached(operation: { await Self.fetchRemote() }).value {
                    self.install(fresh)
                    self.isFresh = true
                }
            }
        }
        loadTask = task
        await task.value
    }

    private func install(_ list: [CaskRecord]) {
        guard !list.isEmpty else { return }
        // Keep snapshot entries that a (partial) newer list doesn't cover.
        for r in list { records[r.token] = r }
        resolvedCache = [:]
        isLoaded = true
        objectWillChange.send()
    }

    func cask(_ token: String) -> ResolvedCask? {
        if let hit = resolvedCache[token] { return hit }
        guard let r = records[token] else { return nil }
        let resolved = ResolvedCask(r)
        resolvedCache[token] = resolved
        return resolved
    }

    /// Bundle name ("Slack.app") → catalog token, for recognising the apps on
    /// a Mac. Prefers the main token over variants like "google-chrome@beta".
    func tokensByBundleName() -> [String: String] {
        var out: [String: String] = [:]
        for r in records.values where r.isInstallable && !r.deprecated && !r.disabled {
            for app in r.apps {
                if let existing = out[app.target], !existing.contains("@"), r.token.contains("@") || existing.count <= r.token.count {
                    continue
                }
                out[app.target] = r.token
            }
        }
        return out
    }

    /// Ranked search over every installable, non-deprecated app in the catalog.
    func search(_ query: String, limit: Int = 20) -> [ResolvedCask] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        var scored: [(Int, CaskRecord)] = []
        for r in records.values where r.isInstallable && !r.deprecated && !r.disabled {
            let name = r.name.lowercased()
            let token = r.token
            let score: Int
            if name == q || token == q { score = 0 }
            else if name.hasPrefix(q) || token.hasPrefix(q) { score = 1 }
            else if name.contains(q) || token.contains(q) { score = 2 }
            else if r.desc?.lowercased().contains(q) == true { score = 3 }
            else { continue }
            scored.append((score, r))
        }
        return scored
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.name.count < $1.1.name.count }
            .prefix(limit * 2)
            .compactMap { cask($0.1.token) }
            .filter(\.isAvailable)
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Loading

    nonisolated private static func loadLocal() -> [CaskRecord] {
        if let data = try? Data(contentsOf: cacheFile) {
            if let cached = try? JSONDecoder().decode([CaskRecord].self, from: data), !cached.isEmpty {
                AppLog.info(.catalog, "Loaded \(cached.count) apps from cache")
                return cached
            }
            // Written by an older version in a different format: drop it (and
            // its ETag) so the next refresh downloads the full catalog again.
            try? FileManager.default.removeItem(at: cacheFile)
            try? FileManager.default.removeItem(at: etagFile)
        }
        if let url = Bundle.main.url(forResource: "CatalogSnapshot", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let snapshot = try? CaskParser.records(fromRawJSON: data) {
            AppLog.info(.catalog, "Loaded \(snapshot.count) apps from bundled snapshot")
            return snapshot
        }
        AppLog.warn(.catalog, "No cached or bundled catalog available")
        return []
    }

    /// Downloads the full catalog if it changed since last time. Returns nil when
    /// unchanged (304) or on failure — the local copy stays in use.
    nonisolated private static func fetchRemote() async -> [CaskRecord]? {
        var request = URLRequest(url: apiURL, timeoutInterval: 60)
        if let etag = try? String(contentsOf: etagFile, encoding: .utf8),
           FileManager.default.fileExists(atPath: cacheFile.path) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            if http.statusCode == 304 {
                AppLog.info(.catalog, "Catalog unchanged since last refresh")
                return nil
            }
            guard http.statusCode == 200 else {
                AppLog.warn(.catalog, "Catalog refresh failed: HTTP \(http.statusCode)")
                return nil
            }
            let parsed = try CaskParser.records(fromRawJSON: data)
            try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(parsed).write(to: cacheFile, options: .atomic)
            if let etag = http.value(forHTTPHeaderField: "ETag") {
                try? etag.write(to: etagFile, atomically: true, encoding: .utf8)
            }
            AppLog.info(.catalog, "Refreshed catalog: \(parsed.count) apps")
            return parsed
        } catch {
            AppLog.warn(.catalog, "Catalog refresh failed: \(error.localizedDescription)")
            return nil
        }
    }
}
