//
//  ContentView.swift
//  FolderDrop
//
//  Root view for the menu bar panel.
//  Owns @State and coordinates child views — it does not render UI details directly.
//

import AppKit
import SwiftUI

/// Every user-facing feature in FolderDrop — navigation, selection, Quick
/// Look, drag-and-drop entry points, keyboard shortcuts, filesystem watching —
/// is coordinated from this one view's @State. Child views (FileListView,
/// FileRowView, FolderHeaderView, ...) are intentionally kept stateless and
/// receive everything as parameters/callbacks, so there is exactly one place
/// that needs to reason about how these features interact with each other.
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
    @State private var folderWatcher = FolderWatcher()
    /// One watcher per root folder, always live regardless of navigation depth —
    /// unlike folderWatcher (which only watches whatever's currently on screen),
    /// these exist purely to catch a root folder itself being deleted/renamed/
    /// moved (e.g. in Finder), even while browsing several levels beneath it or
    /// while sitting at the top-level root list where nothing else is watched.
    @State private var rootFolderWatchers: [URL: FolderWatcher] = [:]
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
                        Label("Add Root Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .padding(.top, 8)
                }
            } else {
                VStack(spacing: 10) {
                    EmptyStateView(
                        systemImage: "folder.badge.plus",
                        iconSize: 32,
                        title: "No root folders added yet",
                        subtitle: "Add a root folder to start browsing your files."
                    )

                    Button {
                        selectFolder()
                    } label: {
                        Label("Add Root Folder", systemImage: "folder.badge.plus")
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.regular)
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
        .onChange(of: currentFolder) { _, newFolder in
            updateFolderWatcher(for: newFolder)
        }
        .onChange(of: rootFolders) { _, newRootFolders in
            syncRootFolderWatchers(newRootFolders)
        }
    }

    /// Keeps exactly one live watcher pointed at whatever folder is currently
    /// displayed. Called whenever currentFolder changes for any reason
    /// (navigating in/out, restoring last session, removing the active root),
    /// so ContentView never has to reason about filesystem monitoring itself —
    /// it just reacts to FolderWatcher's change callback with reloadContents().
    private func updateFolderWatcher(for folder: URL?) {
        folderWatcher.stop()
        guard let folder, let root = currentRoot else { return }
        folderWatcher.start(folder: folder, root: root) {
            reloadContents()
        }
    }

    /// Keeps one live FolderWatcher per root folder, independent of navigation
    /// depth. Called whenever rootFolders changes for any reason (initial
    /// restore, add, remove, or a root disappearing on its own) so a watcher
    /// always exists for exactly the roots currently known, no more, no less.
    private func syncRootFolderWatchers(_ currentRootFolders: [URL]) {
        let current = Dictionary(uniqueKeysWithValues: currentRootFolders.map { ($0.standardizedFileURL, $0) })

        for key in rootFolderWatchers.keys where current[key] == nil {
            rootFolderWatchers[key]?.stop()
            rootFolderWatchers.removeValue(forKey: key)
        }

        for (key, url) in current where rootFolderWatchers[key] == nil {
            let watcher = FolderWatcher()
            watcher.start(folder: url, root: url) {
                handleRootFolderMaybeRemoved(url)
            }
            rootFolderWatchers[key] = watcher
        }
    }

    /// Fires on any write/rename/delete event on a root folder's own file
    /// descriptor. Most such events are harmless — e.g. a file dropped directly
    /// into the root itself fires .write even though the root is unaffected —
    /// so the actual existence check below is what decides whether this was a
    /// real deletion. Only then do we tear down every piece of state that
    /// referenced this root: persistence, the in-memory list (which in turn
    /// stops this very watcher via syncRootFolderWatchers), and — if we were
    /// browsing anywhere inside it, no matter how deep — the current navigation,
    /// which falls back to the root list and stops the leaf folderWatcher via
    /// the existing currentFolder onChange handler above.
    private func handleRootFolderMaybeRemoved(_ url: URL) {
        guard !rootFolderExists(url) else { return }

        FolderPersistence.remove(url)
        rootFolders.removeAll { $0.standardizedFileURL == url.standardizedFileURL }

        if currentRoot?.standardizedFileURL == url.standardizedFileURL {
            currentRoot = nil
            currentFolder = nil
        }

        reloadContents()
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

            guard let entry = selectionState.activeEntry else {
                return event
            }

            switch event.keyCode {
            case 49: // Space
                guard !entry.isDirectory, isQuickLookEnabled else {
                    return event
                }
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

    /// Runs once per launch — guarded on rootFolders already being empty since
    /// `MenuBarExtra`'s `.window` style keeps this view's @State alive across
    /// open/close cycles of the panel rather than recreating it, so `.onAppear`
    /// can fire again later in the same process without this re-running.
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
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"

        // FolderDrop is an accessory (LSUIElement) app: becoming key doesn't
        // make the app itself active, and some panel controls — the sidebar's
        // NSOutlineView in particular — render/behave as inactive until the
        // app is genuinely active, not just key-windowed.
        NSApp.activate()

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard !rootFolders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else {
                NSSound.beep()
                return
            }

            FolderPersistence.add(url)
            rootFolders.append(url)
            reloadContents()
        }
    }

    /// currentRoot only changes when stepping from the root list into a root
    /// folder for the first time (currentFolder was nil); descending further
    /// into subfolders leaves it untouched. currentRoot is what every
    /// security-scoped access call anchors to for the rest of this browsing
    /// session, however deep currentFolder goes.
    private func navigateIntoFolder(_ entry: FolderEntry) {
        if currentFolder == nil {
            currentRoot = entry.url
        }
        currentFolder = entry.url
        reloadContents()
        persistLastOpenedFolder()
    }

    /// Steps up one directory level, or all the way out to the root list if
    /// already at the root folder's own top — the two cases are distinguished
    /// by comparing against currentRoot rather than counting path components,
    /// since currentRoot is the one boundary FolderDrop actually cares about
    /// (it's also the boundary of the security scope).
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

    /// The single place folderEntries gets recomputed, from whatever
    /// currentFolder/rootFolders currently are — called after every
    /// navigation, add/remove, and filesystem-watcher callback, rather than
    /// each call site patching folderEntries incrementally itself.
    private func reloadContents() {
        selectionState.clear()
        hoveredEntry = nil

        guard let folder = currentFolder else {
            pruneDeadRootFolders()
            folderEntries = rootFolders
                .map { FolderEntry(url: $0, isDirectory: true) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return
        }
        folderEntries = loadFolderContents(from: folder)
    }

    /// Drops any root folder that's been deleted (or moved) outside FolderDrop —
    /// e.g. in Finder — from both rootFolders and FolderPersistence. Runs every
    /// time the root list is rebuilt (app launch, going back to the root list,
    /// adding/removing a folder), not just once at launch: ContentView's @State
    /// persists across MenuBarExtra open/close cycles within a single launch, so
    /// FolderPersistence.restore()'s own validation at startup isn't enough to
    /// catch a folder deleted mid-session.
    private func pruneDeadRootFolders() {
        let deadFolders = rootFolders.filter { !rootFolderExists($0) }
        guard !deadFolders.isEmpty else { return }

        for url in deadFolders {
            FolderPersistence.remove(url)
        }
        rootFolders.removeAll { url in
            deadFolders.contains { $0.standardizedFileURL == url.standardizedFileURL }
        }
    }

    /// Used only to decide whether an automatic removal (pruneDeadRootFolders,
    /// handleRootFolderMaybeRemoved) is justified — never for user-initiated
    /// removal, which always honors the user's explicit choice regardless.
    /// Failing to start the security scope is not evidence the folder is
    /// gone (the same distinction FolderPersistence.restore() makes): an
    /// external drive or network share that isn't currently mounted, or a
    /// transient sandbox hiccup, will fail here too, and none of those mean
    /// the folder no longer exists. Only a confirmed, in-scope fileExists
    /// check counts as strong enough evidence to report "gone."
    private func rootFolderExists(_ url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return true }
        defer { url.stopAccessingSecurityScopedResource() }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func loadFolderContents(from folder: URL) -> [FolderEntry] {
        // Sandbox access is tied to currentRoot (the root folder that owns this browsing session).
        guard let root = currentRoot else { return [] }
        guard root.startAccessingSecurityScopedResource() else { return [] }
        defer { root.stopAccessingSecurityScopedResource() }

        return FolderContentsLoader.load(from: folder)
    }

    /// Opens with the user's default app for this file type. The security
    /// scope only needs to stay open long enough for NSWorkspace to hand the
    /// file off — unlike Quick Look, nothing here keeps reading the file after
    /// this call returns, so the scope can close immediately afterward.
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

    /// User-initiated removal (after confirming in requestRemoval above) shares
    /// its cleanup shape with handleRootFolderMaybeRemoved — clear persistence,
    /// clear the in-memory list, and bail out of the removed root's navigation
    /// if we were browsing inside it — since both ultimately mean "this root no
    /// longer belongs in FolderDrop," whether the user removed it explicitly or
    /// it simply stopped existing on disk.
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
            // Both the enlarged hit-testing shape AND the hover tracker must be
            // declared on this exact label view, in this order. Button builds its
            // own internal press gesture from the label's shape at the moment
            // Button is constructed — a contentShape applied afterward, outside
            // the label (as a previous attempt did, chained after .buttonStyle),
            // is invisible to that internal gesture, even though a trailing
            // .onHover at that same outer position *does* pick it up. That
            // mismatch — click bound to the label's original small shape, hover
            // bound to the outer enlarged one — is exactly why hover extended
            // beyond where clicks registered. Declaring both here, on the same
            // node, guarantees they read the identical shape.
            .contentShape(Rectangle().inset(by: -6))
            .onHover { isHovering = $0 }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
