//
//  RootFolderRow.swift
//  FolderDrop
//
//  A row in the top-level root folder list.
//  Reuses FileRowView for visuals and adds the root-folder-specific context menu.
//

import SwiftUI

/// Root folders get their own context menu (Open / Reveal / Remove) instead of
/// FileRowView's — "delete" for a root folder means detaching it from
/// FolderDrop, not deleting anything on disk, so the copy and available
/// actions are deliberately different from a regular file or subfolder row.
struct RootFolderRow: View {
    let entry: FolderEntry
    /// Owned by ContentView; keyboard navigation now reaches the root list too,
    /// so root folders need the same selection highlight subfolders already have.
    var isSelected: Bool = false
    var onHoverChange: (Bool) -> Void = { _ in }
    let onOpen: (FolderEntry) -> Void
    let onReveal: (FolderEntry) -> Void
    let onRequestRemove: (FolderEntry) -> Void

    var body: some View {
        FileRowView(entry: entry, isSelected: isSelected, onHoverChange: onHoverChange)
            .contextMenu {
                Button("Open") {
                    onOpen(entry)
                }
                Button("Reveal in Finder") {
                    onReveal(entry)
                }

                Divider()

                Button("Remove Root Folder…", role: .destructive) {
                    onRequestRemove(entry)
                }
            }
    }
}
