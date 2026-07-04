//
//  FocusRestoration.swift
//  FolderDrop
//
//  Restores keyboard focus to a specific window on demand. Exists because
//  MenuBarExtra's backing window is a non-activating auxiliary panel: AppKit
//  does not automatically hand key status back to it once another real
//  window (like QLPreviewPanel) has taken and relinquished it — the same gap
//  a manual click on FolderDrop currently papers over by triggering AppKit's
//  own click-to-focus path. This gives that same restoration an explicit,
//  single call site instead of requiring an actual click.
//

import AppKit

/// A single, explicit "give FolderDrop keyboard focus back" call site — see the
/// file-level comment above for why this gap exists in the first place.
final class FocusRestoration {
    /// The window to restore focus to. A mutable reference rather than a
    /// value captured at setup time, since the MenuBarExtra window is
    /// resolved asynchronously (see WindowAccessor in ContentView) and may
    /// be set after callers have already registered to call restore().
    var targetWindow: NSWindow?

    /// Re-keys FolderDrop's panel. Safe to call even if targetWindow hasn't
    /// resolved yet (a no-op) or if FolderDrop is already key (redundant but
    /// harmless) — callers don't need to check either condition themselves.
    func restore() {
        targetWindow?.makeKeyAndOrderFront(nil)
    }
}
