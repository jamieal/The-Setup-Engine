import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Format

/// A `.setuprecipe` file: a person's setup (apps, settings, Dock, folders…)
/// to reuse on a fresh Mac or share with someone. Plain JSON, so it's readable.
struct SetupRecipe: Codable {
    struct App: Codable, Hashable {
        let token: String
        let name: String
        var kind: AppEntry.Kind = .app
    }

    struct System: Codable {
        var dockPosition: String?
        var dockAutoHide: Bool?
        var appearance: String?
        var showHiddenFiles: Bool?
        var showPathBar: Bool?
        var twentyFourHourTime: Bool?
    }

    struct DockApp: Codable, Hashable {
        let name: String
        /// Where the app lives, e.g. "/Applications/Slack.app".
        let path: String
        /// Catalog token, when the app comes from the catalog.
        var token: String?
    }

    struct Personal: Codable {
        var folders: [String] = []
        /// Folder name under ~/Pictures, nil to leave screenshots alone.
        var screenshotsFolder: String?
        /// Exact Dock order, nil to leave the Dock alone.
        var dock: [DockApp]?
        /// Browser app name ("Safari", "Google Chrome"), nil to leave it alone.
        var defaultBrowser: String?
        var touchIDForSudo: Bool = false
    }

    static let fileExtension = "setuprecipe"
    /// JSON with our own extension. (Declaring an exported type, for
    /// double-click to open, needs an Info.plist entry — a follow-up.)
    static let contentType = UTType(filenameExtension: fileExtension, conformingTo: .json) ?? .json

    var format = 1
    var name: String
    var created = Date()
    var apps: [App] = []
    var system: System?
    var personal: Personal?

    static func load(from url: URL) throws -> SetupRecipe {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let recipe = try decoder.decode(SetupRecipe.self, from: Data(contentsOf: url))
        guard recipe.format == 1 else { throw CocoaError(.fileReadUnsupportedScheme) }
        return recipe
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

/// Lets menus and drag-and-drop hand a recipe to the setup flow.
final class RecipeInbox: ObservableObject {
    static let shared = RecipeInbox()
    @Published var pending: SetupRecipe?
    @Published var error: String?
    /// Set by the File menu; the setup window builds and saves the recipe.
    @Published var exportThisMacRequested = false
    private init() {}

    func open(_ url: URL) {
        do {
            pending = try SetupRecipe.load(from: url)
            AppLog.info(.general, "Opened recipe \(url.lastPathComponent)")
        } catch {
            self.error = "That file isn't a Setup Engine recipe this version can read."
            AppLog.warn(.general, "Couldn't open recipe \(url.path): \(error.localizedDescription)")
        }
    }

    func chooseAndOpen() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [SetupRecipe.contentType, .json]
        panel.message = "Choose a Setup Engine recipe"
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
}

// MARK: - Building recipes

extension SetupCoordinator {
    /// A recipe of what was chosen in this run (saved from the finish screen).
    func recipeFromChoices(name: String) -> SetupRecipe {
        var recipe = SetupRecipe(name: name)
        recipe.apps = selectedApps.map { .init(token: $0.caskName, name: $0.displayName, kind: $0.kind) }
        recipe.system = .init(
            dockPosition: settings.dockPosition.rawValue,
            dockAutoHide: settings.dockAutoHide,
            appearance: settings.appearance.rawValue,
            showHiddenFiles: settings.showHiddenFiles,
            showPathBar: settings.showPathBar,
            twentyFourHourTime: settings.twentyFourHourTime
        )
        var personal = SetupRecipe.Personal()
        personal.folders = self.personal.folders.filter(\.isOn).map(\.path)
        personal.screenshotsFolder = self.personal.screenshotsFolder ? self.personal.screenshotsFolderName : nil
        if self.personal.dockLayout != .keep {
            personal.dock = self.personal.dockItems.filter(\.included)
                .map { .init(name: $0.name, path: $0.path, token: $0.token) }
        }
        personal.defaultBrowser = self.personal.defaultBrowserPath
            .map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
        personal.touchIDForSudo = self.personal.touchID || touchIDStatus == .alreadyOn
        recipe.personal = personal
        return recipe
    }

    /// "Like last time, but clean": a recipe of how *this* Mac is set up now —
    /// its catalog apps, command-line tools, Dock, settings and browser —
    /// without copying any of its files.
    func recipeFromThisMac() async -> SetupRecipe {
        await catalog.load()
        await loadInstalledState()
        let byBundle = catalog.tokensByBundleName()

        var recipe = SetupRecipe(name: Host.current().localizedName ?? "My Mac")
        recipe.apps = installedBundles.sorted().compactMap { bundle in
            guard let token = byBundle[bundle], let cask = catalog.cask(token) else { return nil }
            return .init(token: token, name: cask.record.name)
        }
        let tools = await HomebrewSupport.formulaeInstalledOnRequest()
        recipe.apps += tools.sorted().map { .init(token: $0, name: $0, kind: .commandLine) }

        let now = await SettingsSnapshot.capture()
        func value(_ key: String) -> DefaultsValue? { now.first { $0.key == key } }
        func bool(_ key: String) -> Bool? { value(key)?.value.map { $0 == "1" } }
        let appearance: String = bool("AppleInterfaceStyleSwitchesAutomatically") == true ? "auto"
            : (value("AppleInterfaceStyle")?.value == "Dark" ? "dark" : "light")
        recipe.system = .init(
            dockPosition: value("orientation")?.value ?? "bottom",
            dockAutoHide: bool("autohide") ?? false,
            appearance: appearance,
            showHiddenFiles: bool("AppleShowAllFiles") ?? false,
            showPathBar: bool("ShowPathbar") ?? false,
            twentyFourHourTime: bool("AppleICUForce24HourTime") ?? false
        )

        var personal = SetupRecipe.Personal()
        personal.dock = await DockReader.currentApps().map { path in
            let bundle = (path as NSString).lastPathComponent
            return .init(name: (bundle as NSString).deletingPathExtension, path: path, token: byBundle[bundle])
        }
        if let shots = value("location")?.value {
            let pictures = NSHomeDirectory() + "/Pictures/"
            personal.screenshotsFolder = shots.hasPrefix(pictures) ? String(shots.dropFirst(pictures.count)) : nil
        }
        if let browser = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) {
            personal.defaultBrowser = browser.deletingPathExtension().lastPathComponent
        }
        personal.folders = ["GitHub", "dev/src", "Developer", "Projects"]
            .filter { FileManager.default.fileExists(atPath: NSHomeDirectory() + "/" + $0) }
        personal.touchIDForSudo = TouchIDForSudo.isEnabled
        recipe.personal = personal
        return recipe
    }

    // MARK: Applying

    /// Pre-fills every step from a recipe. Apps that can't be installed on
    /// this Mac are left out; everything stays editable before Begin Setup.
    func apply(recipe: SetupRecipe) async {
        await catalog.load()
        let curated = Dictionary(
            (Suggestions.categories.flatMap(\.apps) + Suggestions.profiles.flatMap(\.casks)).map { ($0.caskName, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        selectedProfile = nil
        selectedApps = recipe.apps.compactMap { item -> AppEntry? in
            let entry = curated[item.token] ?? catalog.cask(item.token).map {
                AppEntry(caskName: $0.token, displayName: $0.record.name,
                         homepageURL: $0.record.homepage, desc: $0.record.desc)
            } ?? (item.kind == .commandLine
                  ? AppEntry(caskName: item.token, displayName: item.name, kind: .commandLine)
                  : nil)
            guard let entry, unavailableReason(entry) == nil else { return nil }
            return entry
        }

        if let s = recipe.system {
            if let v = s.dockPosition.flatMap(SystemPreferences.DockPosition.init(rawValue:)) { settings.dockPosition = v }
            if let v = s.appearance.flatMap(SystemPreferences.Appearance.init(rawValue:)) { settings.appearance = v }
            if let v = s.dockAutoHide { settings.dockAutoHide = v }
            if let v = s.showHiddenFiles { settings.showHiddenFiles = v }
            if let v = s.showPathBar { settings.showPathBar = v }
            if let v = s.twentyFourHourTime { settings.twentyFourHourTime = v }
        }

        if let p = recipe.personal {
            let folders = p.folders.map { Personalisation.sanitisedFolder($0) }.filter { !$0.isEmpty }
            for f in folders where !personal.folders.contains(where: { $0.path == f }) {
                personal.folders.append(.init(path: f, isOn: true, isCustom: true))
            }
            for i in personal.folders.indices {
                personal.folders[i].isOn = folders.contains(personal.folders[i].path)
            }
            personal.screenshotsFolder = p.screenshotsFolder != nil
            if let name = p.screenshotsFolder { personal.screenshotsFolderName = Personalisation.sanitisedFolder(name, fallback: "Screenshots") }
            if let dock = p.dock {
                personal.savedDock = dock.compactMap { item in
                    // Only app bundles under the usual Applications folders.
                    guard item.path.hasSuffix(".app"),
                          ["/Applications/", "/System/Applications/", NSHomeDirectory() + "/Applications/"]
                            .contains(where: item.path.hasPrefix),
                          !item.path.contains("/../")
                    else { return nil }
                    let homepage = item.token.flatMap { catalog.cask($0)?.record.homepage }
                    return DockItem(path: item.path, name: item.name, homepageURL: homepage, token: item.token)
                }
                setDockLayout(.saved)
            }
            if let browser = p.defaultBrowser {
                personal.defaultBrowserPath = browserChoices.first { $0.name == browser }?.path
            }
            personal.touchID = p.touchIDForSudo && touchIDStatus == .available
        }

        AppLog.info(.general, "Applied recipe \"\(recipe.name)\": \(selectedApps.count) apps")
        withAnimation(.easeInOut(duration: 0.25)) { currentStep = .apps }
    }
}

/// Saves a recipe with a standard save panel.
enum RecipeSaver {
    @discardableResult
    static func save(_ recipe: SetupRecipe) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [SetupRecipe.contentType]
        panel.nameFieldStringValue = "\(recipe.name).\(SetupRecipe.fileExtension)"
        panel.message = "Save a recipe to set up another Mac the same way"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try recipe.data().write(to: url, options: .atomic)
            AppLog.info(.general, "Saved recipe to \(url.path)")
            return url
        } catch {
            AppLog.warn(.general, "Couldn't save recipe: \(error.localizedDescription)")
            return nil
        }
    }
}

/// Reads the apps currently in the Dock, in order.
nonisolated enum DockReader {
    static func currentApps() async -> [String] {
        let r = await DirectInstaller.run("/usr/bin/defaults", ["export", "com.apple.dock", "-"])
        guard let root = try? PropertyListSerialization.propertyList(from: r.stdout, format: nil) as? [String: Any],
              let apps = root["persistent-apps"] as? [[String: Any]]
        else { return [] }
        return apps.compactMap { tile in
            guard let file = (tile["tile-data"] as? [String: Any])?["file-data"] as? [String: Any],
                  let raw = file["_CFURLString"] as? String
            else { return nil }
            let path = raw.hasPrefix("file://") ? (URL(string: raw)?.path ?? raw) : raw
            // Safari's real home is a system volume; point recipes at the stable path.
            if path.hasSuffix("/Safari.app") { return "/Applications/Safari.app" }
            return path
        }
    }
}
