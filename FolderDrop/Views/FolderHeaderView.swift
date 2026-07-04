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

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("FolderDrop")
                    .font(.headline)

                Spacer(minLength: 0)

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }

            Divider()

            if let folder = currentFolder {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(nsImage: FileIconProvider.icon(for: folder))
                            .resizable()
                            .frame(width: 14, height: 14)
                        Text(folder.lastPathComponent)
                            .font(.body.weight(.medium))
                    }

                    Text(parentPathDisplay(for: folder))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .padding(.top, 3)
            } else if rootFolderCount > 0 {
                Text(rootFolderCount == 1 ? "1 Root Folder" : "\(rootFolderCount) Root Folders")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.top, 2)
            } else {
                Text("No root folder selected")
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
