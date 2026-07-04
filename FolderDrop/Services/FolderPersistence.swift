//
//  FolderPersistence.swift
//  FolderDrop
//
//  Saves and restores the user's chosen root folders across launches using
//  security-scoped bookmarks. Hides all UserDefaults and bookmark details from callers.
//

import Foundation

/// Persists root folders as security-scoped bookmarks rather than plain paths.
/// A sandboxed app loses filesystem access to a user-chosen location the
/// moment the process that received it (via NSOpenPanel) exits — a bookmark is
/// the only mechanism macOS provides for re-deriving that same grant on a
/// future launch without asking the user to re-pick the folder every time.
enum FolderPersistence {
    private static let bookmarksKey = "rootFolderBookmarks"

    /// Adds a new root folder to the persisted set.
    static func add(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            return
        }

        var bookmarks = loadBookmarks()
        bookmarks.append(bookmark)
        saveBookmarks(bookmarks)
    }

    /// Resolves every saved bookmark into a folder URL.
    /// Bookmarks that no longer resolve or whose folder no longer exists are dropped.
    /// Stale-but-valid bookmarks are transparently refreshed.
    static func restore() -> [URL] {
        var resolvedURLs: [URL] = []
        var bookmarksToKeep: [Data] = []

        for bookmark in loadBookmarks() {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }

            guard url.startAccessingSecurityScopedResource() else { continue }
            let folderExists = FileManager.default.fileExists(atPath: url.path)
            url.stopAccessingSecurityScopedResource()

            guard folderExists else { continue }

            if isStale {
                guard let refreshed = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) else {
                    continue
                }
                bookmarksToKeep.append(refreshed)
            } else {
                bookmarksToKeep.append(bookmark)
            }

            resolvedURLs.append(url)
        }

        saveBookmarks(bookmarksToKeep)
        return resolvedURLs
    }

    /// Removes the bookmark matching the given folder, if one exists.
    static func remove(_ url: URL) {
        let target = url.standardizedFileURL
        let remaining = loadBookmarks().filter { bookmark in
            var isStale = false
            guard let resolved = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return false
            }
            return resolved.standardizedFileURL != target
        }
        saveBookmarks(remaining)
    }

    private static func loadBookmarks() -> [Data] {
        UserDefaults.standard.array(forKey: bookmarksKey) as? [Data] ?? []
    }

    private static func saveBookmarks(_ bookmarks: [Data]) {
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
    }
}
