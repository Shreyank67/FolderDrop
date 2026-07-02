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
    @State private var selectionState = SelectionState()
    /// Only ever read once, inside moveSelection, to seed where keyboard navigation
    /// starts from when nothing is active yet — never written from selectionState.
    @State private var hoveredEntry: FolderEntry?
    @State private var quickLookService = QuickLookService()
    /// A process-global slot, deliberately not @State: MenuBarExtra's .window-style
    /// content can be torn down and recreated across open/close cycles without a
    /// reliable .onDisappear, which would otherwise leak a stale monitor from a
    /// previous ContentView instance. A static var survives that regardless, so
    /// installKeyboardShortcutsMonitor can always remove any prior one before
    /// installing a new one — guaranteeing exactly one live monitor at a time.
    private static var keyboardShortcutsMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            FolderHeaderView(currentFolder: currentFolder, rootFolderCount: rootFolders.count)

            if currentFolder != nil || !rootFolders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if FolderNavigation.canGoBack(current: currentFolder) {
                        BackButton(action: goBack)
                    }

                    if currentFolder != nil && folderEntries.isEmpty {
                        EmptyStateView(
                            systemImage: "tray",
                            title: "This folder is empty",
                            subtitle: "Files added here will appear automatically."
                        )
                        .frame(minHeight: 260, maxHeight: 380)
                        .transition(.opacity)
                    } else {
                        FileListView(
                            entries: folderEntries,
                            isRootList: currentFolder == nil,
                            root: currentRoot,
                            selectedEntries: selectionState.selectedEntries,
                            activeEntry: selectionState.activeEntry,
                            onOpenFile: openFile,
                            onOpenFolder: navigateIntoFolder,
                            onReveal: revealInFinder,
                            onRequestRemove: requestRemoval,
                            onSelect: { selectionState.selectOnly($0) },
                            onCommandSelect: { selectionState.toggle($0) },
                            onShiftSelect: { selectionState.selectRange(to: $0, in: folderEntries) },
                            onHover: { entry, isHovering in
                                if isHovering {
                                    hoveredEntry = entry
                                } else if hoveredEntry == entry {
                                    hoveredEntry = nil
                                }
                            },
                            onDeselectAll: deselectAll
                        )
                        .transition(.opacity)
                    }

                    Button {
                        selectFolder()
                    } label: {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .padding(.top, 8)
                }
            } else {
                VStack(spacing: 10) {
                    EmptyStateView(
                        systemImage: "folder.badge.plus",
                        title: "No folders added yet",
                        subtitle: "Add a folder to start browsing its files here."
                    )

                    Button {
                        selectFolder()
                    } label: {
                        Label("Add Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentFolder)
        .animation(.easeInOut(duration: 0.2), value: rootFolders.isEmpty)
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .frame(minWidth: 304)
        .onAppear {
            restoreRootFolders()
            installKeyboardShortcutsMonitor()
        }
        .onDisappear {
            removeKeyboardShortcutsMonitor()
        }
        .onChange(of: selectionState.activeEntry) { _, newEntry in
            guard quickLookService.isShowing else { return }
            guard let newEntry, !newEntry.isDirectory else {
                quickLookService.close()
                return
            }
            quickLookService.show(entries: previewEntries(for: newEntry), activeEntry: newEntry, root: currentRoot)
        }
    }

    /// Centralized keyboard shortcuts for the file list: Space toggles Quick Look,
    /// Enter opens the selected file, and Up/Down move selection. Every other key
    /// (and Space/Enter with no file selected) passes through untouched so List
    /// scrolling, buttons, etc. keep working as before. Escape isn't handled here —
    /// QLPreviewPanel is a real NSPanel that already closes itself on Escape natively.
    private func installKeyboardShortcutsMonitor() {
        // Unconditionally clear any prior monitor first — even one left behind by a
        // ContentView instance that was torn down without .onDisappear ever firing —
        // so there can never be more than one alive competing for the same keyDown.
        if let existing = Self.keyboardShortcutsMonitor {
            NSEvent.removeMonitor(existing)
            Self.keyboardShortcutsMonitor = nil
        }

        Self.keyboardShortcutsMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isExtending = event.modifierFlags.contains(.shift)

            switch event.keyCode {
            case 125: // Down Arrow
                moveSelection(by: 1, extending: isExtending)
                return nil
            case 126: // Up Arrow
                moveSelection(by: -1, extending: isExtending)
                return nil
            case 53: // Escape — only ours to handle once Quick Look has had first refusal.
                guard !quickLookService.isShowing else { return event }
                guard FolderNavigation.canGoBack(current: currentFolder) else { return event }
                goBack()
                return nil
            case 0 where event.modifierFlags.contains(.command): // ⌘A / ⌘⇧A
                if event.modifierFlags.contains(.shift) {
                    deselectAll()
                } else {
                    selectAll()
                }
                return nil
            default:
                break
            }

            guard let entry = selectionState.activeEntry else { return event }

            switch event.keyCode {
            case 49: // Space
                guard !entry.isDirectory else { return event }
                quickLookService.toggle(entries: previewEntries(for: entry), activeEntry: entry, root: currentRoot)
                return nil
            case 36, 76: // Return, keypad Enter
                if entry.isDirectory {
                    navigateIntoFolder(entry)
                    if let first = folderEntries.first {
                        selectionState.selectOnly(first)
                    }
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
        if let existing = Self.keyboardShortcutsMonitor {
            NSEvent.removeMonitor(existing)
        }
        Self.keyboardShortcutsMonitor = nil
    }

    /// Moves the active entry by one position within folderEntries via SelectionState.
    /// Nothing active yet seeds from the hovered row (if still present), else the
    /// first entry, regardless of direction or Shift.
    private func moveSelection(by offset: Int, extending: Bool) {
        guard !folderEntries.isEmpty else { return }

        guard selectionState.activeEntry != nil else {
            let seed = (hoveredEntry.flatMap { folderEntries.contains($0) ? $0 : nil }) ?? folderEntries.first
            if let seed {
                selectionState.selectOnly(seed)
            }
            return
        }

        selectionState.moveActive(by: offset, in: folderEntries, extending: extending)
    }

    /// Space should preview just the active file when it's the only one selected,
    /// or the whole selection (in on-screen order) when there's more than one —
    /// the active file is still what Quick Look initially displays either way.
    private func previewEntries(for activeEntry: FolderEntry) -> [FolderEntry] {
        let selected = folderEntries.filter { selectionState.selectedEntries.contains($0) }
        return selected.count > 1 ? selected : [activeEntry]
    }

    /// ⌘A: select every file in the current folder (folders themselves never take
    /// part in selection, consistent with click/⌘-click/⇧-click elsewhere). Reuses
    /// SelectionState's existing toggle(_:) from a cleared state rather than adding
    /// a dedicated method, so activeEntry/selectionAnchor end up on the last file —
    /// keyboard navigation continues normally from there afterward.
    private func selectAll() {
        selectionState.clear()
        for entry in folderEntries where !entry.isDirectory {
            selectionState.toggle(entry)
        }
    }

    /// ⌘⇧A and whitespace clicks: clear the selection and close Quick Look if open.
    private func deselectAll() {
        selectionState.clear()
        quickLookService.close()
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
        selectionState.clear()
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

/// A lightweight, Finder-style back affordance: no permanent border or fill, just
/// a chevron + label that brightens on hover. .buttonStyle(.plain) strips all of
/// AppKit's default button chrome so the only feedback is the color change below —
/// deliberately not a bordered/rounded push button.
private struct BackButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Back")
            }
            .font(.callout)
            .foregroundStyle(isHovering ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    ContentView()
}
