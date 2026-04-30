//
//  AppStore.swift
//  The Setup Engine
//
//  Created by Jamie Cras on 09/03/2026.
//

import Combine
import Foundation
import SwiftUI

// MARK: - Installation Status

enum InstallStatus: String, Codable {
    case notInstalled = "Not Installed"
    case installed = "Installed"
    case outdated = "Update Available"
    case installing = "Installing…"
    case uninstalling = "Uninstalling…"
    case checking = "Checking…"

    var color: Color {
        switch self {
        case .installed: .green
        case .outdated: .orange
        case .notInstalled: .secondary
        case .installing, .uninstalling, .checking: .blue
        }
    }

    var icon: String {
        switch self {
        case .installed: "checkmark.circle.fill"
        case .outdated: "arrow.up.circle.fill"
        case .notInstalled: "circle.dashed"
        case .installing, .uninstalling: "arrow.down.circle"
        case .checking: "questionmark.circle"
        }
    }

    var isInProgress: Bool {
        switch self {
        case .installing, .uninstalling, .checking: true
        default: false
        }
    }
}

// MARK: - App Entry

/// A single app entry the user wants installed via Homebrew Cask.
struct AppEntry: Identifiable, Codable, Equatable {
    var id: String { caskName }
    let caskName: String    // e.g. "google-chrome"
    let displayName: String // e.g. "Google Chrome"
    var homepageURL: String? // e.g. "https://www.mozilla.org/firefox/"
    var desc: String?        // e.g. "Web browser"

    /// Validates that a cask name looks like a real Homebrew token (lowercase, hyphens, digits, @).
    static func isValidCaskName(_ name: String) -> Bool {
        let pattern = /^[a-z0-9][a-z0-9\-]*[a-z0-9](@[a-z0-9\-]+)?$/
        return name.wholeMatch(of: pattern) != nil
    }

    /// Pricing model for the app. Drives badges, labels, and the Review heads-up.
    enum Pricing: String, Codable, Equatable {
        case free
        case freemium       // free tier exists; paid subscription unlocks more
        case subscription   // must pay to use

        var shortLabel: String? {
            switch self {
            case .free:         nil
            case .freemium:     "+ Subscription"
            case .subscription: "Subscription"
            }
        }
    }

    var pricing: Pricing {
        if Self.subscriptionCasks.contains(caskName)   { return .subscription }
        if Self.freemiumCasks.contains(caskName)       { return .freemium }
        return .free
    }

    /// Convenience for filtering / counting.
    var hasSubscription: Bool { pricing != .free }

    /// Apps that require paying to use at all (no usable free tier).
    static let subscriptionCasks: Set<String> = [
        "1password",
        "sketch",
        "sublime-text",
    ]

    /// Apps that work for free but offer paid tiers most users will encounter.
    static let freemiumCasks: Set<String> = [
        "notion",
        "slack",
        "zoom",
        "spotify",
        "figma",
        "todoist-app",
        "alfred",
        "aldente",
        "microsoft-teams",
        "raycast",
        "warp",
        "obsidian",
        "docker-desktop", // free for personal/small biz, paid for orgs >250 employees
    ]
}

// MARK: - Setup Profile

/// A pre-built bundle of apps for common setups.
struct SetupProfile: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let description: String
    let casks: [AppEntry]
}

// MARK: - App Category

/// A category of suggested apps.
struct AppCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let apps: [AppEntry]
}

// MARK: - Suggestions Data

enum Suggestions {
    static let profiles: [SetupProfile] = [
        SetupProfile(
            name: "Developer",
            icon: "hammer.fill",
            description: "Essential tools for software development",
            casks: [
                AppEntry(caskName: "visual-studio-code", displayName: "Visual Studio Code", homepageURL: "https://code.visualstudio.com", desc: "Code editor"),
                AppEntry(caskName: "iterm2", displayName: "iTerm2", homepageURL: "https://iterm2.com", desc: "Terminal emulator"),
                AppEntry(caskName: "docker-desktop", displayName: "Docker Desktop", homepageURL: "https://www.docker.com", desc: "Container platform"),
                AppEntry(caskName: "postman", displayName: "Postman", homepageURL: "https://www.postman.com", desc: "API development"),
                AppEntry(caskName: "github", displayName: "GitHub Desktop", homepageURL: "https://desktop.github.com", desc: "Git client"),
                AppEntry(caskName: "sourcetree", displayName: "Sourcetree", homepageURL: "https://www.sourcetreeapp.com", desc: "Git GUI"),
            ]
        ),
        SetupProfile(
            name: "Designer",
            icon: "paintbrush.fill",
            description: "Creative and design applications",
            casks: [
                AppEntry(caskName: "figma", displayName: "Figma", homepageURL: "https://www.figma.com", desc: "Design tool"),
                AppEntry(caskName: "sketch", displayName: "Sketch", homepageURL: "https://www.sketch.com", desc: "Design tool for macOS"),
                AppEntry(caskName: "imageoptim", displayName: "ImageOptim", homepageURL: "https://imageoptim.com", desc: "Image compression"),
                AppEntry(caskName: "blender", displayName: "Blender", homepageURL: "https://www.blender.org", desc: "3D creation suite"),
                AppEntry(caskName: "gimp", displayName: "GIMP", homepageURL: "https://www.gimp.org", desc: "Image editor"),
            ]
        ),
        SetupProfile(
            name: "Office",
            icon: "briefcase.fill",
            description: "Productivity and office essentials",
            casks: [
                AppEntry(caskName: "google-chrome", displayName: "Google Chrome", homepageURL: "https://www.google.com/chrome", desc: "Web browser"),
                AppEntry(caskName: "slack", displayName: "Slack", homepageURL: "https://slack.com", desc: "Team messaging"),
                AppEntry(caskName: "zoom", displayName: "Zoom", homepageURL: "https://zoom.us", desc: "Video conferencing"),
                AppEntry(caskName: "notion", displayName: "Notion", homepageURL: "https://www.notion.so", desc: "Workspace & notes"),
                AppEntry(caskName: "1password", displayName: "1Password", homepageURL: "https://1password.com", desc: "Password manager"),
                AppEntry(caskName: "rectangle", displayName: "Rectangle", homepageURL: "https://rectangleapp.com", desc: "Window management"),
            ]
        ),
        SetupProfile(
            name: "Media",
            icon: "play.circle.fill",
            description: "Music, video, and streaming apps",
            casks: [
                AppEntry(caskName: "spotify", displayName: "Spotify", homepageURL: "https://www.spotify.com", desc: "Music streaming"),
                AppEntry(caskName: "vlc", displayName: "VLC", homepageURL: "https://www.videolan.org/vlc", desc: "Media player"),
                AppEntry(caskName: "handbrake-app", displayName: "HandBrake", homepageURL: "https://handbrake.fr", desc: "Video transcoder"),
                AppEntry(caskName: "obs", displayName: "OBS Studio", homepageURL: "https://obsproject.com", desc: "Streaming & recording"),
                AppEntry(caskName: "iina", displayName: "IINA", homepageURL: "https://iina.io", desc: "Modern media player"),
            ]
        ),
    ]

    static let categories: [AppCategory] = [
        AppCategory(name: "Browsers", icon: "globe", apps: [
            AppEntry(caskName: "google-chrome", displayName: "Google Chrome", homepageURL: "https://www.google.com/chrome", desc: "Web browser by Google"),
            AppEntry(caskName: "firefox", displayName: "Mozilla Firefox", homepageURL: "https://www.mozilla.org/firefox", desc: "Open-source web browser"),
            AppEntry(caskName: "arc", displayName: "Arc", homepageURL: "https://arc.net", desc: "Modern web browser"),
            AppEntry(caskName: "brave-browser", displayName: "Brave", homepageURL: "https://brave.com", desc: "Privacy-focused browser"),
            AppEntry(caskName: "microsoft-edge", displayName: "Microsoft Edge", homepageURL: "https://www.microsoft.com/edge", desc: "Chromium-based browser"),
        ]),
        AppCategory(name: "Dev Tools", icon: "wrench.and.screwdriver.fill", apps: [
            AppEntry(caskName: "visual-studio-code", displayName: "Visual Studio Code", homepageURL: "https://code.visualstudio.com", desc: "Code editor"),
            AppEntry(caskName: "iterm2", displayName: "iTerm2", homepageURL: "https://iterm2.com", desc: "Terminal emulator"),
            AppEntry(caskName: "docker-desktop", displayName: "Docker Desktop", homepageURL: "https://www.docker.com", desc: "Container platform"),
            AppEntry(caskName: "postman", displayName: "Postman", homepageURL: "https://www.postman.com", desc: "API development"),
            AppEntry(caskName: "sublime-text", displayName: "Sublime Text", homepageURL: "https://www.sublimetext.com", desc: "Text editor"),
            AppEntry(caskName: "warp", displayName: "Warp", homepageURL: "https://www.warp.dev", desc: "Modern terminal"),
        ]),
        AppCategory(name: "Productivity", icon: "checkmark.seal.fill", apps: [
            AppEntry(caskName: "notion", displayName: "Notion", homepageURL: "https://www.notion.so", desc: "Workspace & notes"),
            AppEntry(caskName: "obsidian", displayName: "Obsidian", homepageURL: "https://obsidian.md", desc: "Knowledge base"),
            AppEntry(caskName: "todoist-app", displayName: "Todoist", homepageURL: "https://todoist.com", desc: "Task management"),
            AppEntry(caskName: "rectangle", displayName: "Rectangle", homepageURL: "https://rectangleapp.com", desc: "Window management"),
            AppEntry(caskName: "alfred", displayName: "Alfred", homepageURL: "https://www.alfredapp.com", desc: "Launcher & productivity"),
            AppEntry(caskName: "raycast", displayName: "Raycast", homepageURL: "https://www.raycast.com", desc: "Launcher & extensions"),
        ]),
        AppCategory(name: "Communication", icon: "bubble.left.and.bubble.right.fill", apps: [
            AppEntry(caskName: "slack", displayName: "Slack", homepageURL: "https://slack.com", desc: "Team messaging"),
            AppEntry(caskName: "zoom", displayName: "Zoom", homepageURL: "https://zoom.us", desc: "Video conferencing"),
            AppEntry(caskName: "discord", displayName: "Discord", homepageURL: "https://discord.com", desc: "Voice & text chat"),
            AppEntry(caskName: "microsoft-teams", displayName: "Microsoft Teams", homepageURL: "https://www.microsoft.com/microsoft-teams", desc: "Team collaboration"),
            AppEntry(caskName: "telegram", displayName: "Telegram", homepageURL: "https://telegram.org", desc: "Messaging app"),
        ]),
        AppCategory(name: "Utilities", icon: "wrench.fill", apps: [
            AppEntry(caskName: "1password", displayName: "1Password", homepageURL: "https://1password.com", desc: "Password manager"),
            AppEntry(caskName: "the-unarchiver", displayName: "The Unarchiver", homepageURL: "https://theunarchiver.com", desc: "Archive utility"),
            AppEntry(caskName: "appcleaner", displayName: "AppCleaner", homepageURL: "https://freemacsoft.net/appcleaner", desc: "App uninstaller"),
            AppEntry(caskName: "stats", displayName: "Stats", homepageURL: "https://github.com/exelban/stats", desc: "System monitor"),
            AppEntry(caskName: "aldente", displayName: "AlDente", homepageURL: "https://apphousekitchen.com", desc: "Battery manager"),
            AppEntry(caskName: "monitorcontrol", displayName: "MonitorControl", homepageURL: "https://github.com/MonitorControl/MonitorControl", desc: "Display brightness control"),
        ]),
        AppCategory(name: "Media", icon: "play.circle.fill", apps: [
            AppEntry(caskName: "spotify", displayName: "Spotify", homepageURL: "https://www.spotify.com", desc: "Music streaming"),
            AppEntry(caskName: "vlc", displayName: "VLC", homepageURL: "https://www.videolan.org/vlc", desc: "Media player"),
            AppEntry(caskName: "iina", displayName: "IINA", homepageURL: "https://iina.io", desc: "Modern media player"),
            AppEntry(caskName: "obs", displayName: "OBS Studio", homepageURL: "https://obsproject.com", desc: "Streaming & recording"),
            AppEntry(caskName: "handbrake-app", displayName: "HandBrake", homepageURL: "https://handbrake.fr", desc: "Video transcoder"),
        ]),
    ]
}

// MARK: - App Store

/// Persists the user's app list to UserDefaults and tracks installation status.
@MainActor
class AppStore: ObservableObject {
    private static let storageKey = "savedApps"

    @Published var apps: [AppEntry] = []
    @Published var statuses: [String: InstallStatus] = [:]  // keyed by caskName

    init() {
        load()
    }

    // MARK: - Status

    func status(for caskName: String) -> InstallStatus {
        statuses[caskName] ?? .notInstalled
    }

    func setStatus(_ status: InstallStatus, for caskName: String) {
        statuses[caskName] = status
    }

    /// Checks which apps in the list are installed and which are outdated.
    func refreshStatuses() async {
        for app in apps {
            statuses[app.caskName] = .checking
        }

        // Get installed casks
        let installedCasks = await runBrewCommand("brew list --cask")
        let installedSet = Set(
            installedCasks
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        // Get outdated casks
        let outdatedOutput = await runBrewCommand("brew outdated --cask --quiet")
        let outdatedSet = Set(
            outdatedOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )

        for app in apps {
            if outdatedSet.contains(app.caskName) {
                statuses[app.caskName] = .outdated
            } else if installedSet.contains(app.caskName) {
                statuses[app.caskName] = .installed
            } else {
                statuses[app.caskName] = .notInstalled
            }
        }
    }

    private func runBrewCommand(_ command: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.environment = ShellRunner.brewEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    // MARK: - Mutating

    func add(_ app: AppEntry) {
        guard AppEntry.isValidCaskName(app.caskName) else { return }
        guard !apps.contains(where: { $0.caskName == app.caskName }) else { return }
        apps.append(app)
        save()
    }

    func addAll(_ newApps: [AppEntry]) {
        for app in newApps {
            guard AppEntry.isValidCaskName(app.caskName) else { continue }
            guard !apps.contains(where: { $0.caskName == app.caskName }) else { continue }
            apps.append(app)
        }
        save()
    }

    func remove(_ app: AppEntry) {
        apps.removeAll { $0.caskName == app.caskName }
        statuses.removeValue(forKey: app.caskName)
        save()
    }

    func removeAtOffsets(_ offsets: IndexSet) {
        let removing = offsets.map { apps[$0].caskName }
        apps.remove(atOffsets: offsets)
        for name in removing {
            statuses.removeValue(forKey: name)
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([AppEntry].self, from: data)
        else { return }
        apps = decoded
    }
}
