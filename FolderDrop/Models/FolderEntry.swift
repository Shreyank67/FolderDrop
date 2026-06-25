//
//  FolderEntry.swift
//  FolderDrop
//
//  A lightweight model representing one item inside the selected folder.
//  Lives in Models/ so views and ContentView can share the same data shape.
//

import Foundation

struct FolderEntry: Identifiable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
}
