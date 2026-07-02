//
//  RootFolderRow.swift
//  FolderDrop
//
//  A row in the top-level root folder list.
//  Reuses FileRowView for visuals and adds the root-folder-specific context menu.
//

import SwiftUI

struct RootFolderRow: View {
    let entry: FolderEntry
    var isSelected: Bool = false
    let onOpen: (FolderEntry) -> Void
    let onReveal: (FolderEntry) -> Void
    let onRequestRemove: (FolderEntry) -> Void

    var body: some View {
        FileRowView(entry: entry, isSelected: isSelected)
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
