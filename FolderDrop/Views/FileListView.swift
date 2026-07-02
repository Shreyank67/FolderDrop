//
//  FileListView.swift
//  FolderDrop
//
//  Scrollable list of folder contents.
//  Takes an array of FolderEntry values and delegates each row to FileRowView.
//

import SwiftUI

struct FileListView: View {
    let entries: [FolderEntry]
    var isRootList: Bool = false
    /// The security-scoped root folder backing this browsing session, passed to
    /// file rows so they can access the file when a drag session requests it.
    var root: URL?
    /// Owned by ContentView; the single persistently selected entry, if any.
    var selectedEntry: FolderEntry?
    let onOpenFile: (FolderEntry) -> Void
    let onOpenFolder: (FolderEntry) -> Void
    var onReveal: (FolderEntry) -> Void = { _ in }
    var onRequestRemove: (FolderEntry) -> Void = { _ in }
    var onSelect: (FolderEntry) -> Void = { _ in }

    var body: some View {
        List(entries) { entry in
            Group {
                if isRootList {
                    RootFolderRow(
                        entry: entry,
                        isSelected: selectedEntry?.id == entry.id,
                        onOpen: onOpenFolder,
                        onReveal: onReveal,
                        onRequestRemove: onRequestRemove
                    )
                } else {
                    FileRowView(entry: entry, root: root, isSelected: selectedEntry?.id == entry.id)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(entry)
                if entry.isDirectory {
                    onOpenFolder(entry)
                } else {
                    onOpenFile(entry)
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        }
        .listStyle(.plain)
        .frame(minHeight: 260, maxHeight: 380)
    }
}
