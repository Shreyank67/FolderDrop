//
//  ContentView.swift
//  FolderDrop
//
//  Root view for the menu bar panel.
//  Owns @State and coordinates child views — it does not render UI details directly.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @State private var selectedFolder: URL?
    @State private var folderEntries: [FolderEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FolderHeaderView(selectedFolder: selectedFolder)

            if selectedFolder != nil {
                FileListView(entries: folderEntries, onOpenFile: openFile)

                Button("Change Folder") {
                    selectFolder()
                }
            } else {
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

    private func openFile(_ entry: FolderEntry) {
        guard !entry.isDirectory, let folder = selectedFolder else { return }

        // Re-acquire sandbox access before opening a file inside the user-chosen folder.
        guard folder.startAccessingSecurityScopedResource() else { return }
        NSWorkspace.shared.open(entry.url)
        folder.stopAccessingSecurityScopedResource()
    }
}

#Preview {
    ContentView()
}
