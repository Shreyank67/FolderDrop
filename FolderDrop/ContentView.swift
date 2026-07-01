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
    @State private var rootFolder: URL?
    @State private var currentFolder: URL?
    @State private var folderEntries: [FolderEntry] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FolderHeaderView(currentFolder: currentFolder)

            if currentFolder != nil {
                VStack(alignment: .leading, spacing: 10) {
                    if FolderNavigation.canGoBack(root: rootFolder, current: currentFolder) {
                        Button("Back") {
                            goBack()
                        }
                    }

                    FileListView(
                        entries: folderEntries,
                        onOpenFile: openFile,
                        onOpenFolder: navigateIntoFolder
                    )

                    Button("Change Folder") {
                        selectFolder()
                    }
                }
            } else {
                Button("Select Folder") {
                    selectFolder()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
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
                rootFolder = url
                currentFolder = url
                reloadContents()
            }
        }
    }

    private func navigateIntoFolder(_ entry: FolderEntry) {
        currentFolder = entry.url
        reloadContents()
    }

    private func goBack() {
        guard let current = currentFolder else { return }
        currentFolder = current.deletingLastPathComponent()
        reloadContents()
    }

    private func reloadContents() {
        guard let folder = currentFolder else {
            folderEntries = []
            return
        }
        folderEntries = loadFolderContents(from: folder)
    }

    private func loadFolderContents(from folder: URL) -> [FolderEntry] {
        // Sandbox access is tied to rootFolder (the URL the user picked in NSOpenPanel).
        guard let root = rootFolder else { return [] }
        guard root.startAccessingSecurityScopedResource() else { return [] }
        defer { root.stopAccessingSecurityScopedResource() }

        return FolderContentsLoader.load(from: folder)
    }

    private func openFile(_ entry: FolderEntry) {
        guard !entry.isDirectory, let root = rootFolder else { return }

        guard root.startAccessingSecurityScopedResource() else { return }
        NSWorkspace.shared.open(entry.url)
        root.stopAccessingSecurityScopedResource()
    }
}

#Preview {
    ContentView()
}
