//
//  LaunchAtLoginService.swift
//  FolderDrop
//
//  Isolates ServiceManagement's SMAppService so SettingsView doesn't need to
//  know about it directly. Registration status lives in SMAppService itself —
//  this is not backed by UserDefaults, there's nothing to persist ourselves.
//

import ServiceManagement

/// Registers/unregisters FolderDrop as a login item via the modern
/// `SMAppService` API (macOS 13+), which replaces the deprecated
/// `SMLoginItemSetEnabled`/helper-app-bundle approach — no separate helper
/// target or Info.plist wiring is needed for FolderDrop itself.
enum LaunchAtLoginService {
    /// Always queries `SMAppService` directly rather than caching, since the
    /// user can toggle this outside FolderDrop entirely (System Settings >
    /// General > Login Items), and a cached value would silently go stale.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registration can fail (e.g. the user denies it, or macOS rate-limits
    /// repeated toggling) — callers must handle the thrown error rather than
    /// assuming the toggle always succeeds.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
