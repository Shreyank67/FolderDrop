//
//  FolderContentsLoader.swift
//  FolderDrop
//
//  Reads a folder's immediate children from disk and returns sorted FolderEntry values.
//  Separated from ContentView so loading logic can be reused without duplicating FileManager code.
//

import Foundation

/// Reads exactly one directory level — never recurses into subfolders — since
/// FolderDrop always displays one folder's immediate children at a time and
/// navigates deeper by reloading, not by building a tree up front.
enum FolderContentsLoader {
    /// Folders always sort before files, then alphabetically within each group
    /// (case-insensitive), matching Finder's default "Kind" grouping without
    /// needing a live Kind lookup per item. Any error (folder deleted mid-read,
    /// permission revoked, not actually a directory) yields an empty list rather
    /// than throwing, since callers treat "empty" and "unreadable" the same way.
    static func load(from folder: URL) -> [FolderEntry] {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let entries = urls.map { url -> FolderEntry in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FolderEntry(url: url, isDirectory: isDirectory)
            }

            return entries.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        } catch {
            return []
        }
    }
}
