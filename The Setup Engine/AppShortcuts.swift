import Combine
import Foundation

/// Cross-cutting UI signals (e.g. Cmd+K). Singleton so menu commands can poke it from outside the view tree.
final class AppShortcuts: ObservableObject {
    static let shared = AppShortcuts()

    @Published var quickSearchOpen: Bool = false

    private init() {}
}
