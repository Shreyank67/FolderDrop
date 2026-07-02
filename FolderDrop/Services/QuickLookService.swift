//
//  QuickLookService.swift
//  FolderDrop
//
//  Presents and dismisses the native Quick Look panel for a single file.
//  Isolated from selection/navigation state — callers just hand it an entry to show.
//

import AppKit
import QuickLookUI

final class QuickLookService: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private(set) var previewedURL: URL?
    private var root: URL?

    /// The single source of truth for "is Quick Look currently open," updated
    /// synchronously by show()/close(). Deliberately not derived from
    /// QLPreviewPanel.shared()?.isVisible: that's AppKit's own live window state,
    /// and previewPanelWillClose (the callback that used to be our only place to
    /// clear previewedURL) only fires for the panel's own native close sequence —
    /// not for our orderOut(nil) call — so querying isVisible or waiting on that
    /// delegate left previewedURL stale immediately after our own close().
    private var isPanelOpen = false

    var isShowing: Bool { isPanelOpen }

    /// Callers just say "toggle Quick Look for this entry" — the service decides
    /// whether that means opening it, switching to a different file, or closing it.
    /// Folders never open the panel.
    func toggle(entry: FolderEntry, root: URL?) {
        guard !entry.isDirectory else { return }

        if isPanelOpen && previewedURL == entry.url {
            close()
        } else {
            show(entry: entry, root: root)
        }
    }

    /// quicklookd (a separate system process) reads the file directly, so our
    /// security scope must stay open for as long as the panel is displaying it —
    /// not just at the moment we present it.
    func show(entry: FolderEntry, root: URL?) {
        guard !entry.isDirectory, let panel = QLPreviewPanel.shared() else { return }

        if previewedURL != nil {
            self.root?.stopAccessingSecurityScopedResource()
        }

        self.root = root
        previewedURL = entry.url
        isPanelOpen = true
        _ = root?.startAccessingSecurityScopedResource()

        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard isPanelOpen else { return }
        isPanelOpen = false
        root?.stopAccessingSecurityScopedResource()
        root = nil
        previewedURL = nil

        QLPreviewPanel.shared()?.orderOut(nil)
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewedURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewedURL as NSURL?
    }

    // MARK: - QLPreviewPanelDelegate

    /// Safety net for native closes (Escape, panel losing key status) that don't
    /// go through our own close(). Guarded so it's a no-op if close() already ran.
    func previewPanelWillClose(_ panel: QLPreviewPanel!) {
        guard isPanelOpen else { return }
        isPanelOpen = false
        root?.stopAccessingSecurityScopedResource()
        root = nil
        previewedURL = nil
    }
}
