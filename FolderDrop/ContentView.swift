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
    /// Points at the exact NSWindow hosting this ContentView instance, kept
    /// current by WindowAccessor below, and used to restore key status once
    /// quickLookService reports Quick Look has closed. A reference type (see
    /// FocusRestoration) so the closure registered on quickLookService.onClose
    /// always sees the latest window even though it's resolved asynchronously,
    /// after that closure is registered.
    @State private var focusRestoration = FocusRestoration()
    @AppStorage(SettingsKeys.quickLookEnabled) private var isQuickLookEnabled = true
    @AppStorage(SettingsKeys.restoresLastOpenedFolder) private var restoresLastOpenedFolder = false
    @AppStorage(SettingsKeys.lastOpenedFolderPath) private var lastOpenedFolderPath: String?
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
        .background(WindowAccessor { focusRestoration.targetWindow = $0 })
        .onAppear {
            restoreRootFolders()
            installKeyboardShortcutsMonitor()
            // Restoring focus is a generic reaction to "Quick Look just closed,"
            // however that happened — Space, deselecting, navigating away while
            // it's open, or Escape closing it natively — so it's wired once here
            // rather than duplicated at every call site that can close it.
            quickLookService.onClose = { [focusRestoration] in
                #if DEBUG
                FocusDebugLog.logWindowHierarchy(context: "immediately after Quick Look closed (before any mouse interaction)")
                #endif
                focusRestoration.restore()
            }
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
            // DEBUG-INSTRUMENTATION: every keyDown that reaches this monitor.
            #if DEBUG
            FocusDebugLog.key("reached monitor: keyCode=\(event.keyCode) modifierFlags=\(event.modifierFlags.rawValue)")
            #endif

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

            guard let entry = selectionState.activeEntry else {
                #if DEBUG
                if event.keyCode == 49 {
                    FocusDebugLog.key("Space received but no active entry -> returning event (passthrough)")
                }
                #endif
                return event
            }

            switch event.keyCode {
            case 49: // Space
                // DEBUG-INSTRUMENTATION: full trace of Space handling, since this is
                // the key implicated in the Quick Look focus-chain investigation.
                #if DEBUG
                FocusDebugLog.key("Space received: keyCode=49 modifierFlags=\(event.modifierFlags.rawValue) entry=\(entry.url.lastPathComponent) isDirectory=\(entry.isDirectory) isQuickLookEnabled=\(isQuickLookEnabled)")
                FocusDebugLog.appStateSnapshot(context: "before Space handling")
                #endif
                guard !entry.isDirectory, isQuickLookEnabled else {
                    #if DEBUG
                    FocusDebugLog.key("Space: guard failed (isDirectory or QuickLook disabled) -> returning event (passthrough)")
                    #endif
                    return event
                }
                quickLookService.toggle(entries: previewEntries(for: entry), activeEntry: entry, root: currentRoot)
                #if DEBUG
                FocusDebugLog.key("Space: quickLookService.toggle() called -> returning nil (consumed)")
                FocusDebugLog.appStateSnapshot(context: "after Space handling")
                #endif
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
        restoreLastOpenedFolderIfNeeded()
    }

    /// Only meaningful right after restoreRootFolders() runs at launch. Requires
    /// the saved folder to still exist under one of the restored roots — if the
    /// toggle is off, or the match/existence check fails, we simply stay on the
    /// root list, exactly like today.
    private func restoreLastOpenedFolderIfNeeded() {
        guard restoresLastOpenedFolder,
              let savedPath = lastOpenedFolderPath,
              let root = rootFolders.first(where: {
                  savedPath == $0.path || savedPath.hasPrefix($0.path + "/")
              })
        else { return }

        let savedFolder = URL(fileURLWithPath: savedPath)
        let didAccess = root.startAccessingSecurityScopedResource()
        defer { if didAccess { root.stopAccessingSecurityScopedResource() } }
        guard didAccess, FileManager.default.fileExists(atPath: savedFolder.path) else { return }

        currentRoot = root
        currentFolder = savedFolder
        reloadContents()
    }

    /// Records where the user is browsing so it can be restored on next launch,
    /// only while the preference is on — otherwise there's nothing to save.
    private func persistLastOpenedFolder() {
        guard restoresLastOpenedFolder else { return }
        lastOpenedFolderPath = currentFolder?.path
    }

    private func selectFolder() {
        // DEBUG-INSTRUMENTATION: timing/window-state trace for the Add Folder /
        // NSOpenPanel lag investigation.
        #if DEBUG
        let buttonPressedAt = Date()
        FocusDebugLog.focusChain("[AddFolder] button pressed at \(buttonPressedAt.timeIntervalSinceReferenceDate)")
        FocusDebugLog.appStateSnapshot(context: "AddFolder pressed, before creating NSOpenPanel")
        FocusDebugLog.logWindowHierarchy(context: "AddFolder pressed, before creating NSOpenPanel")
        #endif

        let panel = NSOpenPanel()

        #if DEBUG
        let panelCreatedAt = Date()
        FocusDebugLog.focusChain("[AddFolder] NSOpenPanel() created, elapsed since press: \(panelCreatedAt.timeIntervalSince(buttonPressedAt))s")
        #endif

        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"

        // FolderDrop is an accessory (LSUIElement) app: becoming key doesn't
        // make the app itself active, and some panel controls — the sidebar's
        // NSOutlineView in particular — render/behave as inactive until the
        // app is genuinely active, not just key-windowed.
        NSApp.activate()

        #if DEBUG
        let beforeBeginAt = Date()
        FocusDebugLog.focusChain("[AddFolder] calling panel.begin(completionHandler:), elapsed since creation: \(beforeBeginAt.timeIntervalSince(panelCreatedAt))s")
        FocusDebugLog.appStateSnapshot(context: "AddFolder immediately before panel.begin()")
        #endif

        panel.begin { response in
            #if DEBUG
            let dismissedAt = Date()
            FocusDebugLog.focusChain("[AddFolder] completion handler fired, elapsed since begin() was called: \(dismissedAt.timeIntervalSince(beforeBeginAt))s, response=\(response == .OK ? "OK" : "Cancel")")
            FocusDebugLog.appStateSnapshot(context: "AddFolder in panel.begin completion handler")
            #endif
            guard response == .OK, let url = panel.url else { return }
            guard !rootFolders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else { return }

            FolderPersistence.add(url)
            rootFolders.append(url)
            reloadContents()

            #if DEBUG
            let doneAt = Date()
            FocusDebugLog.focusChain("[AddFolder] reloadContents() finished, elapsed since dismissal: \(doneAt.timeIntervalSince(dismissedAt))s")
            #endif
        }

        #if DEBUG
        // R-investigation: dump the panel's view hierarchy (to find exactly which
        // view is the sidebar) and its first responder shortly after presentation,
        // then poll for first-responder changes until the panel is dismissed — the
        // sidebar is a private AppKit view we can't subclass or hook directly, so
        // detecting the responder change after clicking the path popup requires
        // watching for it rather than intercepting the click itself.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            FocusDebugLog.focusChain("[AddFolder] === NSOpenPanel view hierarchy dump ===")
            if let contentView = panel.contentView {
                FocusDebugLog.dumpViewHierarchy(contentView)
            }
            FocusDebugLog.logResponderState(context: "AddFolder shortly after presentation", window: panel)

            var lastResponderDescription = String(describing: panel.firstResponder)
            var pollTimer: Timer?
            pollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
                guard panel.isVisible else {
                    FocusDebugLog.focusChain("[AddFolder] panel no longer visible, stopping first-responder poll")
                    timer.invalidate()
                    return
                }
                let currentDescription = String(describing: panel.firstResponder)
                if currentDescription != lastResponderDescription {
                    FocusDebugLog.focusChain("[AddFolder] firstResponder changed:\n  from: \(lastResponderDescription)\n  to:   \(currentDescription)")
                    FocusDebugLog.logResponderState(context: "AddFolder firstResponder changed", window: panel)
                    lastResponderDescription = currentDescription
                }
            }
            _ = pollTimer
        }
        #endif

        #if DEBUG
        let beginReturnedAt = Date()
        FocusDebugLog.focusChain("[AddFolder] panel.begin() call returned to caller, elapsed since call: \(beginReturnedAt.timeIntervalSince(beforeBeginAt))s (should be ~0 if truly non-blocking)")
        #endif
    }

    private func navigateIntoFolder(_ entry: FolderEntry) {
        if currentFolder == nil {
            currentRoot = entry.url
        }
        currentFolder = entry.url
        reloadContents()
        persistLastOpenedFolder()
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
        persistLastOpenedFolder()
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

/// Resolves the exact NSWindow hosting the view it's attached to. MenuBarExtra
/// exposes no SwiftUI-level API for its backing window, so this bridges to
/// AppKit for the one property (NSView.window) that answers it deterministically:
/// it's read directly off a view inside our own hierarchy, not searched for
/// among NSApp.windows, so it can never resolve to Settings/About/any other
/// window even as the app grows more of them. Deferred one runloop tick since
/// the view isn't attached to its window yet at makeNSView/updateNSView time.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onResolve(nsView.window) }
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
