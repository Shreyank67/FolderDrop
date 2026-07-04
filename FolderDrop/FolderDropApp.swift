//
//  FolderDropApp.swift
//  FolderDrop
//
//  Created by Shreyank Patil on 25/06/26.
//

import SwiftUI

@main
struct FolderDropApp: App {
    init() {
        // DEBUG-INSTRUMENTATION: temporary focus/responder-chain investigation (R0.1).
        #if DEBUG
        FocusDebugObserver.shared.start()
        #endif
    }

    var body: some Scene {
        MenuBarExtra("FolderDrop", image: "MenuIcon") {
            ContentView()
        }
        .menuBarExtraStyle(.window)

        // A native Settings scene is a singleton window by construction: SwiftUI
        // brings the existing window to front on a repeat openSettings() call
        // rather than creating another one, so no custom "already open" tracking
        // is needed for that requirement.
        Settings {
            SettingsView()
        }
    }
}
