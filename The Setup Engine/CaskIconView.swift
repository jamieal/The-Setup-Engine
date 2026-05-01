import SwiftUI
import AppKit

/// Displays an app icon — uses an installed .app's icon when available,
/// falling back to a favicon for the homepage, then to a system glyph.
struct CaskIconView: View {
    let homepageURL: String?
    let caskName: String
    /// Whether to show the subscription/$ badge corner overlay. Off on screens
    /// where the badge adds noise (e.g. Profile cards showing 5–6 icons in a row).
    var showSubscriptionBadge: Bool = true

    @State private var nsImage: NSImage?

    var body: some View {
        Group {
            if let nsImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if let url = remoteIconURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.15))) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        fallback
                    default:
                        fallback.opacity(0.4)
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(alignment: .bottomTrailing) {
            if showSubscriptionBadge {
                pricingBadge
            }
        }
        // Re-run the lookup whenever caskName changes — fixes a stale-icon bug where
        // a reused view (e.g. on InstallStep cycling through apps) kept showing the
        // first app's icon for every subsequent app.
        .task(id: caskName) {
            nsImage = nil
            loadInstalledAppIcon()
        }
    }

    /// Corner badge — orange $ for pure subscription, blue + for freemium, nothing for free.
    @ViewBuilder
    private var pricingBadge: some View {
        switch pricingForCask(caskName) {
        case .subscription:
            Image(systemName: "dollarsign.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .orange)
                .font(.system(size: 13, weight: .black))
                .background(Circle().fill(.background).padding(1))
                .offset(x: 4, y: 4)
                .help("Requires a paid subscription")
        case .freemium:
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .blue)
                .font(.system(size: 13, weight: .black))
                .background(Circle().fill(.background).padding(1))
                .offset(x: 4, y: 4)
                .help("Free to use; paid tier available")
        case .free:
            EmptyView()
        }
    }

    private func pricingForCask(_ name: String) -> AppEntry.Pricing {
        if AppEntry.subscriptionCasks.contains(name) { return .subscription }
        if AppEntry.freemiumCasks.contains(name)     { return .freemium }
        return .free
    }

    /// Resolution + override list lives in IconPrewarm so app launch can
    /// prefetch the same URLs we'll request here.
    private var remoteIconURL: URL? {
        CaskIcon.remoteURL(caskName: caskName, homepageURL: homepageURL)
    }

    private var fallback: some View {
        Image(systemName: "app.fill")
            .resizable()
            .frame(width: 32, height: 32)
            .foregroundStyle(.tertiary)
    }

    private func loadInstalledAppIcon() {
        let titleCased = caskName
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")

        let noSpaces = titleCased.replacingOccurrences(of: " ", with: "")

        var candidates = [titleCased, noSpaces, caskName, caskName.uppercased()]

        let knownMappings: [String: String] = [
            "google-chrome":       "Google Chrome",
            "visual-studio-code":  "Visual Studio Code",
            "iterm2":              "iTerm",
            "microsoft-edge":      "Microsoft Edge",
            "microsoft-teams":     "Microsoft Teams",
            "obs":                 "OBS",
            "vlc":                 "VLC",
            "1password":           "1Password 7",
            "firefox":             "Firefox",
            "brave-browser":       "Brave Browser",
            "github-desktop":      "GitHub Desktop",
            "sublime-text":        "Sublime Text",
            "the-unarchiver":      "The Unarchiver",
            "arc":                 "Arc",
        ]
        if let mapped = knownMappings[caskName] {
            candidates.insert(mapped, at: 0)
        }

        let appDirs = ["/Applications", NSHomeDirectory() + "/Applications"]
        for dir in appDirs {
            for name in candidates {
                let path = "\(dir)/\(name).app"
                if FileManager.default.fileExists(atPath: path) {
                    nsImage = NSWorkspace.shared.icon(forFile: path)
                    return
                }
            }
        }

        if let contents = try? FileManager.default.contentsOfDirectory(atPath: "/Applications") {
            let lowerCask = caskName.replacingOccurrences(of: "-", with: "").lowercased()
            for item in contents where item.hasSuffix(".app") {
                let appNameLower = item.replacingOccurrences(of: ".app", with: "")
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased()
                if appNameLower == lowerCask
                    || appNameLower.contains(lowerCask)
                    || lowerCask.contains(appNameLower) {
                    nsImage = NSWorkspace.shared.icon(forFile: "/Applications/\(item)")
                    return
                }
            }
        }
    }

}
