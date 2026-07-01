//
//  FileRowView.swift
//  FolderDrop
//
//  Renders a single row in the file list.
//  Isolating rows makes the list easy to extend later (icons, drag handles, etc.).
//

import SwiftUI

struct FileRowView: View {
    let entry: FolderEntry

    var body: some View {
        HStack {
            Image(nsImage: FileIconProvider.icon(for: entry.url))
                .resizable()
                .frame(width: 16, height: 16)

            Text(entry.name)
        }
    }
}
