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
    let rootFolderCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FolderDrop")
                .font(.headline)

            if let folder = currentFolder {
                HStack(spacing: 6) {
                    Image(nsImage: FileIconProvider.icon(for: folder))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(folder.lastPathComponent)
                        .font(.body.weight(.medium))
                }

                Text(parentPathDisplay(for: folder))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } else if rootFolderCount > 0 {
                Text(rootFolderCount == 1 ? "1 Root Folder" : "\(rootFolderCount) Root Folders")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No folder selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Renders the folder's parent path using "›" separators, e.g. "Users › shreyank › Documents".
    private func parentPathDisplay(for folder: URL) -> String {
        let parentComponents = folder.deletingLastPathComponent().pathComponents.filter { $0 != "/" }
        return parentComponents.isEmpty ? "/" : parentComponents.joined(separator: " › ")
    }
}
