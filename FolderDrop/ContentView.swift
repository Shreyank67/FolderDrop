//
//  ContentView.swift
//  FolderDrop
//
//  Created by Shreyank Patil on 25/06/26.
//

import AppKit
import SwiftUI

struct ContentView: View {
    // @State keeps this value alive across view redraws. When it changes, SwiftUI refreshes the UI.
    @State private var selectedFolder: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FolderDrop")
                .font(.headline)

            if let folder = selectedFolder {
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

            Button("Select Folder") {
                selectFolder()
            }
        }
        .padding()
        .frame(minWidth: 280)
    }

    private func selectFolder() {
        // NSOpenPanel is AppKit's standard "open file/folder" dialog (Finder-style picker).
        let panel = NSOpenPanel()
        panel.canChooseFiles = false    // files not selectable
        panel.canChooseDirectories = true   // folders only
        panel.allowsMultipleSelection = false  // only one folder at a time
        panel.prompt = "Select"  // button text "Select"

        panel.begin { response in
            // `if let` safely unwraps the optional URL — only runs when the user picked a folder.
            if response == .OK, let url = panel.url {
                selectedFolder = url
            }
        }
    }
}

#Preview {
    ContentView()
}
