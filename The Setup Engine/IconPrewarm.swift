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
    /// Hand-picked high-res icon URLs for casks whose Google favicon is blurry,
    /// missing, or returns the wrong asset entirely. Verified live before adding.
    static let overrides: [String: String] = [
        // Originals
        "github":         "https://github.com/apple-touch-icon.png",
        "gimp":           "https://www.gimp.org/images/frontpage/wilber-big.png",
        "handbrake-app":  "https://handbrake.fr/apple-touch-icon.png",
        "appcleaner":     "https://freemacsoft.net/img/appcleaner.png",

        // Added because Google favicons returned nothing useful for these
        "sketch":         "https://www.sketch.com/images/components/logos/sketch-logo.png",
        "blender":        "https://www.blender.org/wp-content/uploads/2020/07/blender_community_badge_white.png",
        "imageoptim":     "https://imageoptim.com/img/imageoptim-icon-256.png",
        "sourcetree":     "https://wac-cdn.atlassian.com/dam/jcr:580d0089-3aab-431c-9ad1-9f2e29bd84f0/Atlassian_logo_clear-space-version_blue_RGB.svg",
        "monitorcontrol": "https://raw.githubusercontent.com/MonitorControl/MonitorControl/master/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png",
        "stats":          "https://raw.githubusercontent.com/exelban/stats/master/Stats/Supporting%20Files/Assets.xcassets/AppIcon.appiconset/icon_256x256.png",
        "aldente":        "https://apphousekitchen.com/wp-content/uploads/2021/03/aldente-light.png",
        "iina":           "https://iina.io/images/iina-icon-60.png",
        "obs":            "https://obsproject.com/assets/images/new_icon_small-r.png",
        "rectangle":      "https://rectangleapp.com/img/rectangle-svg.svg",
        "raycast":        "https://www.raycast.com/favicon-production.png",
        "warp":           "https://www.warp.dev/static/favicon-256x256.png",
        "obsidian":       "https://obsidian.md/images/obsidian-logo-gradient.svg",
        "todoist-app":    "https://todoist.b-cdn.net/assets/images/96cf45b3edd0c5d59ae7df1ed91f7c33.png",
        "alfred":         "https://www.alfredapp.com/favicon.ico",
        "the-unarchiver": "https://theunarchiver.com/img/the-unarchiver-icon-128.png",
        "discord":        "https://assets-global.website-files.com/6257adef93867e50d84d30e2/636e0b54f654380a78de4527_icon_clyde_white_RGB.png",
        "telegram":       "https://telegram.org/img/t_logo.png",
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
