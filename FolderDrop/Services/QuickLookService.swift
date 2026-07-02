//
//  QuickLookService.swift
//  FolderDrop
//
//  Presents and dismisses the native Quick Look panel for one or more files.
//  Isolated from selection/navigation state — callers just hand it the files to
//  show and which one should be active; SelectionState never touches this class.
//

import AppKit
import QuickLookUI

final class QuickLookService: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    /// The ordered set of files currently loaded into the panel. QLPreviewPanel
    /// natively handles Left/Right navigation across these once it knows there's
    /// more than one, via numberOfPreviewItems/previewItemAt below.
    private(set) var previewItems: [URL] = []
    /// The index we told the panel to start on. QLPreviewPanel manages navigation
    /// internally from there; this just records where "active" pointed at show time.
    private(set) var currentIndex: Int = 0
    private var root: URL?

    /// The single source of truth for "is Quick Look currently open," updated
    /// synchronously by show()/close(). Deliberately not derived from
    /// QLPreviewPanel.shared()?.isVisible: that's AppKit's own live window state,
    /// and querying it directly would mean waiting on AppKit's own async
    /// window-ordering rather than reflecting the decision we already made.
    private var isPanelOpen = false

    var isShowing: Bool { isPanelOpen }

    /// Fires once AppKit has actually confirmed QLPreviewPanel relinquished
    /// key status — not merely when we've decided to close it. Driven by
    /// NSWindow.didResignKeyNotification (see observePanelDidResignKey/
    /// handlePanelDidResignKey below), the genuine AppKit completion signal,
    /// rather than by close()/previewPanelWillClose() themselves, which are
    /// both "will" moments that fire before AppKit's own state has settled.
    /// Purely a completion signal: this class has no notion of what a caller
    /// does with it (focus, UI state, anything else), keeping it responsible
    /// only for Quick Look itself.
    var onClose: (() -> Void)?

    /// Registered once, lazily, the first time show() runs — see
    /// observePanelDidResignKey(_:). Removed in deinit so a QuickLookService
    /// instance recreated across MenuBarExtra open/close cycles never leaks
    /// an observer on QLPreviewPanel's long-lived shared singleton.
    private var didResignKeyObserver: NSObjectProtocol?

    deinit {
        if let didResignKeyObserver {
            NotificationCenter.default.removeObserver(didResignKeyObserver)
        }
    }

    /// Callers just say "toggle Quick Look for this set of files" — the service
    /// decides whether that means opening it, switching to different content, or
    /// closing it. Folders never open the panel.
    func toggle(entries: [FolderEntry], activeEntry: FolderEntry, root: URL?) {
        // DEBUG-INSTRUMENTATION: trace every toggle() call and which branch it takes.
        #if DEBUG
        Self.debugLogPanelState(context: "toggle() entry", isPanelOpen: isPanelOpen, previewedURL: activeEntry.url)
        #endif
        guard !activeEntry.isDirectory, !entries.isEmpty else { return }

        if isPanelOpen && previewItems == entries.map(\.url) {
            #if DEBUG
            FocusDebugLog.quickLook("toggle() -> panel already open with same entries, calling close()")
            #endif
            close()
        } else {
            #if DEBUG
            FocusDebugLog.quickLook("toggle() -> calling show()")
            #endif
            show(entries: entries, activeEntry: activeEntry, root: root)
        }
    }

    /// quicklookd (a separate system process) reads the files directly, so our
    /// security scope must stay open for as long as the panel is displaying them —
    /// not just at the moment we present it. Every file here lives under the same
    /// root bookmark, so one open/close bracket on root covers all of them exactly
    /// as it already did for a single file.
    func show(entries: [FolderEntry], activeEntry: FolderEntry, root: URL?) {
        // DEBUG-INSTRUMENTATION: trace show() calls and panel/app state before/after.
        #if DEBUG
        Self.debugLogPanelState(context: "show() entry", isPanelOpen: isPanelOpen, previewedURL: activeEntry.url)
        FocusDebugLog.appStateSnapshot(context: "before opening Quick Look (show())")
        #endif
        guard !activeEntry.isDirectory, !entries.isEmpty, let panel = QLPreviewPanel.shared() else { return }
        observePanelDidResignKey(panel)

        if !previewItems.isEmpty {
            self.root?.stopAccessingSecurityScopedResource()
        }

        self.root = root
        previewItems = entries.map(\.url)
        currentIndex = previewItems.firstIndex(of: activeEntry.url) ?? 0
        isPanelOpen = true
        _ = root?.startAccessingSecurityScopedResource()

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = currentIndex
        panel.makeKeyAndOrderFront(nil)

        #if DEBUG
        Self.debugLogPanelState(context: "show() exit", isPanelOpen: isPanelOpen, previewedURL: activeEntry.url)
        #endif
    }

    func close() {
        // DEBUG-INSTRUMENTATION: trace close() calls and panel/app state before/after.
        #if DEBUG
        Self.debugLogPanelState(context: "close() entry", isPanelOpen: isPanelOpen, previewedURL: previewItems.indices.contains(currentIndex) ? previewItems[currentIndex] : nil)
        FocusDebugLog.appStateSnapshot(context: "before closing Quick Look (close())")
        #endif
        guard isPanelOpen else {
            #if DEBUG
            FocusDebugLog.quickLook("close() -> isPanelOpen already false, no-op")
            #endif
            return
        }
        isPanelOpen = false
        root?.stopAccessingSecurityScopedResource()
        root = nil
        previewItems = []
        currentIndex = 0

        QLPreviewPanel.shared()?.close()

        #if DEBUG
        Self.debugLogPanelState(context: "close() exit", isPanelOpen: isPanelOpen, previewedURL: nil)
        #endif
        // onClose fires from handlePanelDidResignKey() once AppKit actually
        // confirms the key-status transition, not synchronously from here.
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewItems.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard previewItems.indices.contains(index) else { return nil }
        return previewItems[index] as NSURL
    }

    // MARK: - QLPreviewPanelDelegate

    /// Safety net for native closes (Escape, panel losing key status) that don't
    /// go through our own close(). Guarded so it's a no-op if close() already ran.
    /// Never touches selection — closing Quick Look this way or via close() both
    /// leave SelectionState completely untouched, so selection is always preserved.
    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        // DEBUG-INSTRUMENTATION: native close path (Escape, panel losing key status).
        #if DEBUG
        FocusDebugLog.quickLook("previewPanelWillClose() called (native close path)")
        Self.debugLogPanelState(context: "previewPanelWillClose() entry", isPanelOpen: isPanelOpen, previewedURL: nil)
        #endif
        guard isPanelOpen else { return }
        isPanelOpen = false
        root?.stopAccessingSecurityScopedResource()
        root = nil
        previewItems = []
        currentIndex = 0
        // onClose fires from handlePanelDidResignKey(), not here — see close().
    }

    // MARK: - Focus completion signal

    /// Registered once, idempotently. QLPreviewPanel.shared() is a long-lived
    /// singleton, so re-registering on every show() would accumulate duplicate
    /// observers across repeated open/close cycles.
    private func observePanelDidResignKey(_ panel: QLPreviewPanel) {
        guard didResignKeyObserver == nil else { return }
        didResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.handlePanelDidResignKey()
        }
    }

    /// Not every resignation of key status means Quick Look actually closed —
    /// e.g. Cmd-Tabbing to another app while it's still showing also resigns
    /// key. Only treat this as "closed" if we already recorded the close
    /// ourselves (isPanelOpen already false), whether via close() or via the
    /// native Escape path (previewPanelWillClose). That's what distinguishes
    /// a real close from an unrelated key-status change.
    private func handlePanelDidResignKey() {
        guard !isPanelOpen else { return }
        #if DEBUG
        Self.debugLogPanelState(context: "handlePanelDidResignKey() -> firing onClose", isPanelOpen: isPanelOpen, previewedURL: nil)
        #endif
        onClose?()
    }

    // MARK: - DEBUG-INSTRUMENTATION

    #if DEBUG
    private static func debugLogPanelState(context: String, isPanelOpen: Bool, previewedURL: URL?) {
        let panel = QLPreviewPanel.shared()
        FocusDebugLog.quickLook("""
        [\(context)] previewedURL=\(previewedURL?.path ?? "nil") \
        isPanelOpen=\(isPanelOpen) \
        panel.isVisible=\(panel?.isVisible ?? false) \
        panel.isKeyWindow=\(panel?.isKeyWindow ?? false) \
        panel.isMainWindow=\(panel?.isMainWindow ?? false)
        """)
    }
    #endif
}
