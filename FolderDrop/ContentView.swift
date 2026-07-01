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
    @State private var rootFolders: [URL] = []
    @State private var currentRoot: URL?
    @State private var currentFolder: URL?
    @State private var folderEntries: [FolderEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FolderHeaderView(currentFolder: currentFolder, rootFolderCount: rootFolders.count)

            if currentFolder != nil || !rootFolders.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    if FolderNavigation.canGoBack(current: currentFolder) {
                        Button("Back") {
                            goBack()
                        }
                    }

                    FileListView(
                        entries: folderEntries,
                        onOpenFile: openFile,
                        onOpenFolder: navigateIntoFolder
                    )

                    Button("Add Folder") {
                        selectFolder()
                    }
                }
            } else {
                Button("Add Folder") {
                    selectFolder()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(minWidth: 280)
        .onAppear {
            restoreRootFolders()
        }
    }

    private func restoreRootFolders() {
        guard rootFolders.isEmpty else { return }
        rootFolders = FolderPersistence.restore()
        reloadContents()
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard !rootFolders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }

            FolderPersistence.add(url)
            rootFolders.append(url)
            reloadContents()
        }
    }

    private func navigateIntoFolder(_ entry: FolderEntry) {
        if currentFolder == nil {
            currentRoot = entry.url
        }
        currentFolder = entry.url
        reloadContents()
    }

    private func goBack() {
        guard let current = currentFolder else { return }

        if current == currentRoot {
            currentFolder = nil
            currentRoot = nil
        } else {
            currentFolder = current.deletingLastPathComponent()
        }
        reloadContents()
    }

    private func reloadContents() {
        guard let folder = currentFolder else {
            folderEntries = rootFolders
                .map { FolderEntry(url: $0, isDirectory: true) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return
        }
        folderEntries = loadFolderContents(from: folder)
    }

    private func loadFolderContents(from folder: URL) -> [FolderEntry] {
        // Sandbox access is tied to currentRoot (the root folder that owns this browsing session).
        guard let root = currentRoot else { return [] }
        guard root.startAccessingSecurityScopedResource() else { return [] }
        defer { root.stopAccessingSecurityScopedResource() }

        return FolderContentsLoader.load(from: folder)
    }

    private func openFile(_ entry: FolderEntry) {
        guard !entry.isDirectory, let root = currentRoot else { return }

        guard root.startAccessingSecurityScopedResource() else { return }
        NSWorkspace.shared.open(entry.url)
        root.stopAccessingSecurityScopedResource()
    }
}

#Preview {
    ContentView()
}
