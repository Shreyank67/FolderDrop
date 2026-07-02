//
//  SettingsView.swift
//  FolderDrop
//
//  Native Settings window content, split into dedicated pages (General,
//  Hotkeys, About) via TabView — the classic macOS Settings pattern, where
//  each tab renders as an icon in the window's toolbar.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            HotkeysSettingsView()
                .tabItem {
                    Label("Hotkeys", systemImage: "keyboard")
                }

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 420, height: 460)
    }
}

#Preview {
    SettingsView()
}
