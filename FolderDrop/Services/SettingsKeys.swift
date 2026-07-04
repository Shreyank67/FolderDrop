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

/// Central registry of `UserDefaults` key strings. Referencing `SettingsKeys.x`
/// instead of a string literal at every `@AppStorage`/`UserDefaults` call site
/// means a typo'd key fails to compile instead of silently reading/writing the
/// wrong (or a brand-new, empty) default.
enum SettingsKeys {
    static let quickLookEnabled = "quickLookEnabled"
    static let restoresLastOpenedFolder = "restoresLastOpenedFolder"
    static let dragCleanupDelaySeconds = "dragCleanupDelaySeconds"
    static let lastOpenedFolderPath = "lastOpenedFolderPath"
}
