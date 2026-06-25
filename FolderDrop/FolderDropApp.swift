//
//  FolderDropApp.swift
//  FolderDrop
//
//  Created by Shreyank Patil on 25/06/26.
//

import SwiftUI

@main
struct FolderDropApp: App {
    var body: some Scene {
        MenuBarExtra("FolderDrop", systemImage: "folder") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
