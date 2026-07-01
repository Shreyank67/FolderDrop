//
//  FileIconProvider.swift
//  FolderDrop
//
//  Looks up the native macOS icon for a file or folder.
//  The only place in the app that talks to NSWorkspace/AppKit for icons.
//

import AppKit

enum FileIconProvider {
    static func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
