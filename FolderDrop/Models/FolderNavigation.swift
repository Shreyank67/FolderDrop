//
//  FolderNavigation.swift
//  FolderDrop
//
//  Small helper for folder navigation rules.
//  Keeps "can I go back?" logic out of ContentView so state stays easy to read.
//

import Foundation

/// Pure navigation predicates shared between the Back button's visibility and
/// the Escape key handler in ContentView. Kept as stateless functions over
/// `currentFolder` rather than inline checks at each call site so the "can I
/// go back?" rule can't silently drift out of sync between the two.
enum FolderNavigation {
    /// True when there's somewhere to go back to — either up a level inside a root folder,
    /// or back to the top-level list of root folders.
    static func canGoBack(current: URL?) -> Bool {
        current != nil
    }
}
