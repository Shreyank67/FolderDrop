//
//  FolderPersistence.swift
//  FolderDrop
//
//  Saves and restores the user's chosen root folder across launches using a
//  security-scoped bookmark. Hides all UserDefaults and bookmark details from callers.
//

import Foundation

enum FolderPersistence {
    private static let bookmarkKey = "rootFolderBookmark"

    /// Replaces any previously saved folder with the given one.
    static func save(_ url: URL) {
        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } catch {
            clear()
        }
    }

    /// Resolves the saved bookmark back into a folder URL, or nil if none exists or restoration fails.
    static func restore() -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            clear()
            return nil
        }

        if isStale {
            save(url)
        }

        return url
    }

    /// Removes the saved folder bookmark.
    static func clear() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }
}
