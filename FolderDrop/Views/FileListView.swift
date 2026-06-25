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
    let onOpenFile: (FolderEntry) -> Void
    let onOpenFolder: (FolderEntry) -> Void

    var body: some View {
        List(entries) { entry in
            FileRowView(entry: entry)
                .contentShape(Rectangle())
                .onTapGesture {
                    if entry.isDirectory {
                        onOpenFolder(entry)
                    } else {
                        onOpenFile(entry)
                    }
                }
        }
        .frame(minHeight: 120, maxHeight: 300)
    }
}
