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
    @State private var selectedEntry: FolderEntry?
    /// Only ever read once, inside moveSelection, to seed where keyboard navigation
    /// starts from when nothing is selected yet — never written from selectedEntry.
    @State private var hoveredEntry: FolderEntry?
    @State private var quickLookService = QuickLookService()
    @State private var keyboardShortcutsMonitor: Any?

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
                        isRootList: currentFolder == nil,
                        root: currentRoot,
                        selectedEntry: selectedEntry,
                        onOpenFile: openFile,
                        onOpenFolder: navigateIntoFolder,
                        onReveal: revealInFinder,
                        onRequestRemove: requestRemoval,
                        onSelect: { selectedEntry = $0 },
                        onHover: { entry, isHovering in
                            if isHovering {
                                hoveredEntry = entry
                            } else if hoveredEntry == entry {
                                hoveredEntry = nil
                            }
                        }
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
            installKeyboardShortcutsMonitor()
        }
        .onDisappear {
            removeKeyboardShortcutsMonitor()
        }
        .onChange(of: selectedEntry) { _, newEntry in
            guard quickLookService.isShowing else { return }
            if let newEntry, !newEntry.isDirectory {
                quickLookService.show(entry: newEntry, root: currentRoot)
            } else {
                quickLookService.close()
            }
        }
    }

    /// Centralized keyboard shortcuts for the file list: Space toggles Quick Look,
    /// Enter opens the selected file, and Up/Down move selection. Every other key
    /// (and Space/Enter with no file selected) passes through untouched so List
    /// scrolling, buttons, etc. keep working as before. Escape isn't handled here —
    /// QLPreviewPanel is a real NSPanel that already closes itself on Escape natively.
    private func installKeyboardShortcutsMonitor() {
        guard keyboardShortcutsMonitor == nil else { return }
        keyboardShortcutsMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.keyCode {
            case 125: // Down Arrow
                moveSelection(by: 1)
                return nil
            case 126: // Up Arrow
                moveSelection(by: -1)
                return nil
            case 53: // Escape — only ours to handle once Quick Look has had first refusal.
                guard !quickLookService.isShowing else { return event }
                guard FolderNavigation.canGoBack(current: currentFolder) else { return event }
                goBack()
                return nil
            default:
                break
            }

            guard let entry = selectedEntry else { return event }

            switch event.keyCode {
            case 49: // Space
                guard !entry.isDirectory else { return event }
                quickLookService.toggle(entry: entry, root: currentRoot)
                return nil
            case 36, 76: // Return, keypad Enter
                if entry.isDirectory {
                    navigateIntoFolder(entry)
                    selectedEntry = folderEntries.first
                } else {
                    openFile(entry)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyboardShortcutsMonitor() {
        if let keyboardShortcutsMonitor {
            NSEvent.removeMonitor(keyboardShortcutsMonitor)
        }
        keyboardShortcutsMonitor = nil
    }

    /// Moves selectedEntry by one position within folderEntries. Nothing selected
    /// selects the first entry regardless of direction; at either edge, no-ops.
    private func moveSelection(by offset: Int) {
        guard !folderEntries.isEmpty else { return }

        guard let currentIndex = selectedEntry.flatMap({ folderEntries.firstIndex(of: $0) }) else {
            if let hoveredEntry, let hoveredIndex = folderEntries.firstIndex(of: hoveredEntry) {
                selectedEntry = folderEntries[hoveredIndex]
            } else {
                selectedEntry = folderEntries.first
            }
            return
        }

        let nextIndex = currentIndex + offset
        guard folderEntries.indices.contains(nextIndex) else { return }
        selectedEntry = folderEntries[nextIndex]
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
        selectedEntry = nil
        hoveredEntry = nil

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

    private func revealInFinder(_ entry: FolderEntry) {
        guard entry.url.startAccessingSecurityScopedResource() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
        entry.url.stopAccessingSecurityScopedResource()
    }

    // NSAlert.runModal() is used instead of SwiftUI's .confirmationDialog because the dialog's
    // window sits outside MenuBarExtra's own panel bounds. That panel dismisses itself on any
    // click it sees as "outside," which raced with and swallowed the dialog button's tap before
    // the SwiftUI action closure could run. NSAlert resolves its button click inside its own
    // modal session before returning, so the removal is guaranteed to fire.
    private func requestRemoval(of entry: FolderEntry) {
        let alert = NSAlert()
        alert.messageText = "Remove \"\(entry.name)\" from FolderDrop?"
        alert.informativeText = "This only removes the shortcut from FolderDrop.\nThe folder and its contents will remain on your Mac."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            removeRootFolder(entry)
        }
    }

    private func removeRootFolder(_ entry: FolderEntry) {
        let url = entry.url
        FolderPersistence.remove(url)
        rootFolders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }

        if currentRoot?.standardizedFileURL == url.standardizedFileURL {
            currentRoot = nil
            currentFolder = nil
        }

        reloadContents()
    }
}

#Preview {
    ContentView()
}
