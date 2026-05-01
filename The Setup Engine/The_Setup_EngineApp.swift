//
//  The_Setup_EngineApp.swift
//  The Setup Engine
//
//  Created by Jamie Cras on 09/03/2026.
//

import SwiftUI

@main
struct The_Setup_EngineApp: App {
    init() {
        IconPrewarm.start()
    }

    var body: some Scene {
        WindowGroup {
            SetupContainerView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 880, height: 660)
        .commands {
            AppCommands()

            CommandGroup(after: .windowArrangement) {
                Button("Find App…") { AppShortcuts.shared.quickSearchOpen = true }
                    .keyboardShortcut("k", modifiers: .command)
            }
            #if DEBUG
            DebugCommands(state: DebugState.shared)
            #endif
        }
    }
}
