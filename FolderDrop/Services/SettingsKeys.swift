//
//  SettingsKeys.swift
//  FolderDrop
//
//  The UserDefaults keys shared between SettingsView (which edits them via
//  @AppStorage) and the rest of the app (which reads them to change behavior).
//  Keeping the key strings in one place is the only thing that needs to be
//  shared — the values themselves live in UserDefaults, not duplicated state.
//

import Foundation

enum SettingsKeys {
    static let quickLookEnabled = "quickLookEnabled"
    static let restoresLastOpenedFolder = "restoresLastOpenedFolder"
    static let dragCleanupDelaySeconds = "dragCleanupDelaySeconds"
    static let lastOpenedFolderPath = "lastOpenedFolderPath"
}
