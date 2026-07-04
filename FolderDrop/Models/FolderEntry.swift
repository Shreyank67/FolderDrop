//
//  FolderEntry.swift
//  FolderDrop
//
//  A lightweight model representing one item inside the selected folder.
//  Lives in Models/ so views and ContentView can share the same data shape.
//

import Foundation

/// One file or folder inside the currently displayed directory. Identity and
/// equality are both keyed on `url`, so two entries pointing at the same path
/// are always interchangeable — this is what lets SelectionState and SwiftUI's
/// diffing treat entries as stable identifiers across reloads.
struct FolderEntry: Identifiable, Equatable, Hashable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
}
