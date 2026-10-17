import AppKit
import Combine
import Foundation

/// One photo in the wallpaper collection (#9), as listed in wallpapers.json on
/// the repo's "wallpapers" GitHub release (see scripts/publish-wallpapers.sh).
nonisolated struct WallpaperPhoto: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let credit: String?
    let thumb: URL
    let full: URL
    let sha256: String?
}

enum WallpaperChoice: Hashable {
    case keep
    case collection(WallpaperPhoto)
    case file(URL)

    var label: String {
        switch self {
        case .keep: "No change"
        case .collection(let photo): photo.title
        case .file(let url): url.deletingPathExtension().lastPathComponent
        }
    }
}

/// The published collection. Empty (and the picker hidden) until photos are
/// published, or when offline.
@MainActor
final class WallpaperCollection: ObservableObject {
    static let shared = WallpaperCollection()
    static let manifestURL = URL(string: "https://github.com/jamieal/The-Setup-Engine/releases/download/wallpapers/wallpapers.json")!

    @Published private(set) var photos: [WallpaperPhoto] = []
    private var loaded = false

    func load() async {
        guard !loaded else { return }
        loaded = true
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.manifestURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                AppLog.info(.settings, "No wallpaper collection published yet")
                return
            }
            struct Manifest: Decodable { let photos: [WallpaperPhoto] }
            photos = try JSONDecoder().decode(Manifest.self, from: data).photos
                .filter { $0.full.scheme == "https" && $0.thumb.scheme == "https" }
        } catch {
            AppLog.warn(.settings, "Wallpaper collection unavailable: \(error.localizedDescription)")
        }
    }
}

nonisolated enum WallpaperSetter {
    static var folder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!
            .appending(path: "The Setup Engine", directoryHint: .isDirectory)
    }

    /// Downloads a collection photo into ~/Pictures/The Setup Engine and checks it.
    static func download(_ photo: WallpaperPhoto) async throws -> URL {
        let (temp, response) = try await URLSession.shared.download(from: photo.full)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw InstallFailure.downloadFailed("wallpaper unavailable")
        }
        if let expected = photo.sha256,
           try DirectInstaller.sha256(of: temp).caseInsensitiveCompare(expected) != .orderedSame {
            try? FileManager.default.removeItem(at: temp)
            throw InstallFailure.checksumMismatch
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeID = photo.id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let dest = folder.appending(path: (safeID.isEmpty ? "wallpaper" : safeID) + ".jpg")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }

    /// Sets the picture on every screen.
    @MainActor
    static func set(_ image: URL) -> Bool {
        var ok = true
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: [:])
            } catch {
                ok = false
                AppLog.warn(.settings, "Couldn't set wallpaper on \(screen.localizedName): \(error.localizedDescription)")
            }
        }
        return ok
    }
}
