//
//  FolderHeaderView.swift
//  FolderDrop
//
//  Displays the app title and either the selected folder details or a placeholder.
//  Pure display component — it receives data and does not own any @State.
//

import SwiftUI

struct FolderHeaderView: View {
    let currentFolder: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FolderDrop")
                .font(.headline)

            if let folder = currentFolder {
                Text(folder.lastPathComponent)
                    .font(.body.weight(.medium))
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else {
                Text("No folder selected")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
