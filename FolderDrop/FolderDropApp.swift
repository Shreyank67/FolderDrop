//
//  FolderDropApp.swift
//  FolderDrop
//
//  Created by Shreyank Patil on 25/06/26.
//

import SwiftUI

/// FolderDrop has no Dock icon or regular window (`LSUIElement` in Info.plist)
/// — `MenuBarExtra` in `.window` style is the entire UI, giving ContentView a
/// borderless panel anchored under the menu bar icon instead of a normal
/// window. The Settings scene is the one exception: it's a real window,
/// created here so `openSettings()` (used from FolderHeaderView) has a scene
/// to target.
@main
struct FolderDropApp: App {
    init() {
        // Runs once per launch, before any UI is shown, so it can never race
        // a drag the user hasn't started yet.
        DragStagingArea.removeOrphanedFiles()
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
