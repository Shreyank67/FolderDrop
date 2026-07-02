//
//  LaunchAtLoginService.swift
//  FolderDrop
//
//  Isolates ServiceManagement's SMAppService so SettingsView doesn't need to
//  know about it directly. Registration status lives in SMAppService itself —
//  this is not backed by UserDefaults, there's nothing to persist ourselves.
//

import ServiceManagement

enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
