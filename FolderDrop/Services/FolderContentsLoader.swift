//
//  FolderContentsLoader.swift
//  FolderDrop
//
//  Reads a folder's immediate children from disk and returns sorted FolderEntry values.
//  Separated from ContentView so loading logic can be reused without duplicating FileManager code.
//

import Foundation

enum FolderContentsLoader {
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
