import Foundation

/// Hand-curated remote icon URLs + a one-shot launch-time prefetcher.
///
/// `CaskIconView` needs an icon URL for every cask: an `iconOverrides` entry if
/// we have one, otherwise a Google favicon URL derived from the cask's homepage.
/// Originally this logic lived inside `CaskIconView`, which meant every Profile
/// card showed blank squares for ~500ms on first display while AsyncImage made
/// 5 parallel network calls.
///
/// Now URL resolution is shared (this file) and `IconPrewarm.start()` runs once
/// at app launch — it bumps `URLCache.shared` to a useful disk size and fires
/// off the fetches in the background. By the time the user reaches the Profile
/// step they're either in the in-memory cache (fast path) or on disk from a
/// previous launch (also fast).
enum CaskIcon {
    /// Hand-picked high-res icon URLs for casks whose Google favicon (the default
    /// fallback) returns nothing useful at sz=128. Each URL was verified to return
    /// HTTP 200 and a usable square icon at the time of adding — re-check if you
    /// see blank cards in Profile/Apps.
    ///
    /// Casks not listed here use Google's `/s2/favicons?domain=…&sz=128` endpoint.
    static let overrides: [String: String] = [
        "github":         "https://github.com/apple-touch-icon.png",
        "gimp":           "https://www.gimp.org/images/frontpage/wilber-big.png",
        "handbrake-app":  "https://handbrake.fr/apple-touch-icon.png",
        "appcleaner":     "https://freemacsoft.net/img/appcleaner.png",
        "sketch":         "https://www.sketch.com/images/metadata/icon-180.png",
        "blender":        "https://www.blender.org/wp-content/themes/bthree/assets/icons/apple-touch-icon.png",
        "imageoptim":     "https://imageoptim.com/icon.png",
        "sourcetree":     "https://wac-cdn.atlassian.com/assets/img/favicons/sourcetree/android-chrome-192x192.png",
        "monitorcontrol": "https://raw.githubusercontent.com/MonitorControl/MonitorControl/main/MonitorControl/Assets.xcassets/AppIcon.appiconset/Icon-512.png",
        "stats":          "https://raw.githubusercontent.com/exelban/stats/master/Stats/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_512x512.png",
    ]

    /// Resolves the remote URL for a cask: override → Google favicon → nil.
    static func remoteURL(caskName: String, homepageURL: String?) -> URL? {
        if let override = overrides[caskName] {
            return URL(string: override)
        }
        guard let homepage = homepageURL,
              let url = URL(string: homepage),
              let host = url.host
        else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128")
    }
}

enum IconPrewarm {
    /// Bumps `URLCache.shared` and fires fetches for every cask icon URL in the
    /// catalogue. Idempotent — safe to call from `App.init`.
    static func start() {
        configureSharedCache()

        let urls = allIconURLs()
        AppLog.info(.ui, "Pre-warming \(urls.count) icon URLs")

        let session = URLSession.shared
        for url in urls {
            // Fire-and-forget — the byproduct of a successful fetch is a populated
            // URLCache entry. We don't care about the response.
            let task = session.dataTask(with: URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad))
            task.resume()
        }
    }

    /// 30 MB on disk is plenty for ~50 small icon PNGs, with headroom.
    private static func configureSharedCache() {
        let mem = 5  * 1024 * 1024
        let disk = 30 * 1024 * 1024
        URLCache.shared = URLCache(memoryCapacity: mem, diskCapacity: disk, diskPath: "tse-icons")
    }

    private static func allIconURLs() -> [URL] {
        var seen = Set<String>()
        var out: [URL] = []

        let allCasks: [AppEntry] =
            Suggestions.profiles.flatMap(\.casks) +
            Suggestions.categories.flatMap(\.apps)

        for cask in allCasks {
            guard let url = CaskIcon.remoteURL(caskName: cask.caskName,
                                               homepageURL: cask.homepageURL),
                  !seen.contains(url.absoluteString)
            else { continue }
            seen.insert(url.absoluteString)
            out.append(url)
        }
        return out
    }
}
