//
//  FileRowView.swift
//  FolderDrop
//
//  Renders a single row in the file list.
//  Isolating rows makes the list easy to extend later (icons, drag handles, etc.).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileRowView: View {
    let entry: FolderEntry
    /// The security-scoped root folder this entry lives under. Needed to briefly
    /// reopen sandbox access while handing the file off to a drag session.
    var root: URL?
    /// Owned by ContentView; whether this row is the one persistently selected entry.
    var isSelected: Bool = false
    /// The full current selection, purely so the drag modifier can tell whether
    /// this row is part of an existing multi-selection. Not used for rendering.
    var selectedEntries: Set<FolderEntry> = []
    /// Notifies callers of hover changes, purely so ContentView can seed keyboard
    /// navigation from the hovered row. The visual highlight below stays local state.
    var onHoverChange: (Bool) -> Void = { _ in }
    /// Same click-intent callbacks FileListView's tap gesture already uses. The
    /// multi-file drag source needs them too, to replicate a plain click when a
    /// mouse-down on a multi-selected row turns out not to be a drag.
    var onSelect: (FolderEntry) -> Void = { _ in }
    var onCommandSelect: (FolderEntry) -> Void = { _ in }
    var onShiftSelect: (FolderEntry) -> Void = { _ in }

    /// Hover is purely transient and local to this row, unlike selection.
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: FileIconProvider.icon(for: entry.url))
                .resizable()
                .frame(width: 16, height: 16)

            Text(entry.name)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(highlightColor)
        )
        .animation(.easeInOut(duration: 0.16), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            onHoverChange(hovering)
        }
        .modifier(FileDragModifier(
            entry: entry,
            root: root,
            selectedEntries: selectedEntries,
            onSelect: onSelect,
            onCommandSelect: onCommandSelect,
            onShiftSelect: onShiftSelect
        ))
    }

    /// Selection keeps the same emphasized color AppKit gives a selected, key-window
    /// list row. Hover uses a light system-accent-color tint instead of gray, so it
    /// still reads as "not yet selected" rather than competing with selection.
    private var highlightColor: Color {
        if isSelected {
            return Color(nsColor: .selectedContentBackgroundColor)
        } else if isHovering {
            return Color(nsColor: .controlAccentColor).opacity(0.12)
        } else {
            return .clear
        }
    }
}

/// Applies native drag-and-drop only to file rows, leaving folder rows unaffected.
private struct FileDragModifier: ViewModifier {
    let entry: FolderEntry
    let root: URL?
    var selectedEntries: Set<FolderEntry> = []
    var onSelect: (FolderEntry) -> Void = { _ in }
    var onCommandSelect: (FolderEntry) -> Void = { _ in }
    var onShiftSelect: (FolderEntry) -> Void = { _ in }

    func body(content: Content) -> some View {
        if entry.isDirectory {
            content
        } else if selectedEntries.contains(entry) && selectedEntries.count > 1 {
            // Dragging a member of an existing multi-selection: .onDrag can only ever
            // produce one NSDraggingItem, so a genuine N-file drag needs the raw
            // AppKit bridge below instead. Every other case below still uses the
            // original, untouched .onDrag path.
            content.overlay(
                MultiFileDragSourceView(
                    entries: Array(selectedEntries),
                    root: root,
                    targetEntry: entry,
                    onSelect: onSelect,
                    onCommandSelect: onCommandSelect,
                    onShiftSelect: onShiftSelect
                )
            )
        } else {
            content.onDrag {
                // Dragging a file that isn't part of the current selection collapses
                // the selection to just that file first, matching Finder, then falls
                // straight through to the exact single-file path used previously.
                if !selectedEntries.contains(entry) {
                    onSelect(entry)
                }
                return Self.dragItemProvider(for: entry.url, root: root)
            } preview: {
                HStack(spacing: 4) {
                    Image(nsImage: FileIconProvider.icon(for: entry.url))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(entry.name)
                }
                .padding(6)
            }
        }
    }

    /// NSItemProvider(contentsOf:) reads the file lazily, whenever the destination asks
    /// for it — which happens well after the drag starts, by which point our sandbox
    /// scope would already be closed. Instead we copy the file to a plain temp location
    /// ourselves up front, under an open scope, and hand that (already sandbox-free)
    /// copy to two representations:
    ///  - registerFileRepresentation, for AppKit apps (Finder, Mail) that negotiate the
    ///    coordinated/promise file protocol.
    ///  - registerObject(NSURL), for Chromium/Electron apps (Chrome, Slack, VS Code,
    ///    ChatGPT) that read a `public.file-url` straight off the pasteboard and expect
    ///    it to already resolve to a real file, with no negotiation.
    fileprivate static func dragItemProvider(for url: URL, root: URL?) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = url.deletingPathExtension().lastPathComponent

        let typeIdentifier = UTType(filenameExtension: url.pathExtension)?.identifier
            ?? UTType.data.identifier

        let stagedURL = stageCopy(of: url, root: root)

        if let stagedURL {
            provider.registerObject(stagedURL as NSURL, visibility: .all)
        }

        provider.registerFileRepresentation(
            forTypeIdentifier: typeIdentifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            guard let stagedURL else {
                completion(nil, false, CocoaError(.fileReadNoPermission))
                return nil
            }
            completion(stagedURL, false, nil)
            return nil
        }

        scheduleCleanup(of: stagedURL)

        return provider
    }

    /// Copies the file into its own throwaway directory under an open security scope.
    /// The copy carries plain file permissions, so destination apps can read it without
    /// needing any access to our sandbox container.
    fileprivate static func stageCopy(of url: URL, root: URL?) -> URL? {
        let didAccess = root?.startAccessingSecurityScopedResource() ?? false
        defer { if didAccess { root?.stopAccessingSecurityScopedResource() } }

        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderDropDrag", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagedURL = stagingDirectory.appendingPathComponent(url.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: stagedURL)
            return stagedURL
        } catch {
            return nil
        }
    }

    /// AppKit doesn't delete the source file it copies from during a drag, so we own its
    /// lifecycle. The delay gives slower destinations (network drives, large uploads)
    /// enough time to finish reading before the copy is removed.
    fileprivate static func scheduleCleanup(of stagedURL: URL?) {
        guard let stagedURL else { return }
        let stagingDirectory = stagedURL.deletingLastPathComponent()

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            try? FileManager.default.removeItem(at: stagingDirectory)
        }
    }
}

/// Bridges into raw AppKit for the one thing SwiftUI's .onDrag cannot do on macOS:
/// start a single NSDraggingSession carrying multiple NSDraggingItems. Only ever
/// instantiated when the row being dragged is part of an existing 2+ file selection
/// (see FileDragModifier above) — every other case still goes through the untouched
/// .onDrag path. AppKit fans/stacks multi-item drags and shows a count badge natively,
/// so no custom preview view is needed here.
private struct MultiFileDragSourceView: NSViewRepresentable {
    let entries: [FolderEntry]
    let root: URL?
    let targetEntry: FolderEntry
    let onSelect: (FolderEntry) -> Void
    let onCommandSelect: (FolderEntry) -> Void
    let onShiftSelect: (FolderEntry) -> Void

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: DragSourceNSView) {
        view.entries = entries
        view.root = root
        view.targetEntry = targetEntry
        view.onSelect = onSelect
        view.onCommandSelect = onCommandSelect
        view.onShiftSelect = onShiftSelect
    }
}

private final class DragSourceNSView: NSView, NSDraggingSource {
    var entries: [FolderEntry] = []
    var root: URL?
    var targetEntry: FolderEntry?
    var onSelect: (FolderEntry) -> Void = { _ in }
    var onCommandSelect: (FolderEntry) -> Void = { _ in }
    var onShiftSelect: (FolderEntry) -> Void = { _ in }

    /// Same drag-vs-click distance threshold every AppKit drag source uses to
    /// distinguish an intentional drag from a stationary click.
    private let dragThreshold: CGFloat = 4

    override func mouseDown(with event: NSEvent) {
        let startPoint = event.locationInWindow

        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                handlePlainClick(with: next)
                return
            }

            let distance = hypot(next.locationInWindow.x - startPoint.x, next.locationInWindow.y - startPoint.y)
            if distance > dragThreshold {
                beginMultiFileDrag(with: event)
                return
            }
        }
    }

    /// No drag happened — mouseDown here means SwiftUI's own tap gesture never saw
    /// this click, so we replicate exactly what FileListView's onTapGesture does.
    private func handlePlainClick(with event: NSEvent) {
        guard let targetEntry else { return }

        if event.modifierFlags.contains(.command) {
            onCommandSelect(targetEntry)
        } else if event.modifierFlags.contains(.shift) {
            onShiftSelect(targetEntry)
        } else {
            onSelect(targetEntry)
        }
    }

    /// NSItemProvider (used by the single-file .onDrag path) isn't NSPasteboardWriting,
    /// so it can't back an NSDraggingItem directly here. Each file is staged with the
    /// same stageCopy(of:root:) used everywhere else, then handed to NSDraggingItem as
    /// a plain NSURL — the same public.file-url representation the single-file path
    /// already registers via registerObject(NSURL), which is what Finder, Mail, Chrome,
    /// Slack, VS Code, and ChatGPT all already accept.
    private func beginMultiFileDrag(with event: NSEvent) {
        let draggingItems: [NSDraggingItem] = entries.compactMap { entry in
            guard let stagedURL = FileDragModifier.stageCopy(of: entry.url, root: root) else { return nil }
            FileDragModifier.scheduleCleanup(of: stagedURL)

            let item = NSDraggingItem(pasteboardWriter: stagedURL as NSURL)
            let icon = FileIconProvider.icon(for: entry.url)
            item.setDraggingFrame(NSRect(origin: .zero, size: NSSize(width: 32, height: 32)), contents: icon)
            return item
        }

        guard !draggingItems.isEmpty else { return }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
