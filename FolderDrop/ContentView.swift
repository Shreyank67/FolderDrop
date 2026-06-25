//
//  ContentView.swift
//  FolderDrop
//
//  Created by Shreyank Patil on 25/06/26.
//

import AppKit
import SwiftUI

// Identifiable lets SwiftUI track each row in a List. `id` must be unique per item.
private struct FolderEntry: Identifiable {
    let url: URL
    let isDirectory: Bool

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

struct ContentView: View {
    @State private var selectedFolder: URL?
    @State private var folderEntries: [FolderEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FolderDrop")
                .font(.headline)

            if let folder = selectedFolder {
                Text(folder.lastPathComponent)
                    .font(.body.weight(.medium))
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                List(folderEntries) { entry in
                    Text(entry.name)
                }
                .frame(minHeight: 120, maxHeight: 300)

                Button("Change Folder") {
                    selectFolder()
                }
            } else {
                Text("No folder selected")
                    .foregroundStyle(.secondary)

                Button("Select Folder") {
                    selectFolder()
                }
            }
        }
        .padding()
        .frame(minWidth: 280)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                selectedFolder = url
                loadFolderContents(from: url)
            }
        }
    }

    private func loadFolderContents(from folder: URL) {
        // Sandboxed apps need permission to read user-chosen folders.
        guard folder.startAccessingSecurityScopedResource() else {
            folderEntries = []
            return
        }
        defer { folder.stopAccessingSecurityScopedResource() }

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

            // Folders first, then files; alphabetical within each group.
            folderEntries = entries.sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        } catch {
            folderEntries = []
        }
    }
}

#Preview {
    ContentView()
}
