//
//  FileIconProvider.swift
//  FolderDrop
//
//  Looks up the native macOS icon for a file or folder.
//  The only place in the app that talks to NSWorkspace/AppKit for icons.
//

import AppKit

/// Wraps `NSWorkspace`'s icon lookup so the rest of the app never imports
/// AppKit just to draw a file icon. Using the system-provided icon (rather
/// than bundling our own file-type glyphs) means FolderDrop automatically
/// stays current with custom app icons, document type icons, and any future
/// macOS icon style changes.
enum FileIconProvider {
    /// Looks up the same icon Finder would show for this path, resolved
    /// directly from the file's UTType — no caching, since NSWorkspace already
    /// caches internally and call sites here render infrequently (one row/header
    /// icon at a time, not a scrolling grid).
    static func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}
