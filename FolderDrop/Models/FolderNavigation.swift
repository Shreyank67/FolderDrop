//
//  FolderNavigation.swift
//  FolderDrop
//
//  Small helper for folder navigation rules.
//  Keeps "can I go back?" logic out of ContentView so state stays easy to read.
//

import Foundation

enum FolderNavigation {
    /// True when the user has navigated into a subfolder below their originally chosen folder.
    static func canGoBack(root: URL?, current: URL?) -> Bool {
        guard let root, let current else { return false }
        return current != root
    }
}
