import Foundation

/// Single source of truth for version strings shown in the UI.
/// Reads from Info.plist so it stays in lockstep with the .xcodeproj's
/// MARKETING_VERSION / CURRENT_PROJECT_VERSION.
enum AppVersion {
    /// "1.0.0" — semantic version users see.
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// "1" — build number, increments per build.
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// "v1.0.0" — short label for footers / badges.
    static var shortLabel: String {
        "v\(marketing)"
    }

    /// "v1.0.0 (build 1)" — verbose label for About / log bundles.
    static var fullLabel: String {
        "v\(marketing) (build \(build))"
    }
}
