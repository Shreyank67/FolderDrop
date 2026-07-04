//
//  DragStagingArea.swift
//  FolderDrop
//
//  Defines the one location FileDragModifier stages temporary drag copies,
//  so drag staging and startup cleanup always agree on exactly where those
//  files live instead of each keeping their own copy of the path.
//

import Foundation

/// Every dragged file is briefly copied outside the sandbox into its own
/// UUID-named subdirectory under `rootDirectory` (see
/// FileDragModifier.stageCopy) and removed again a short delay after the
/// drag completes (see FileDragModifier.scheduleCleanup). If FolderDrop
/// quits, crashes, or macOS restarts before that delayed cleanup fires, the
/// copy is orphaned here — `removeOrphanedFiles()` sweeps those away on the
/// next launch.
enum DragStagingArea {
    static let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FolderDropDrag", isDirectory: true)

    /// Called once at launch, before the user can start dragging anything of
    /// their own — nothing here can race a fresh drag's own staging
    /// directory, since drags only ever add new, uniquely-named UUID
    /// subdirectories after this has already run.
    ///
    /// Each leftover entry is removed independently so one locked or
    /// already-gone file can't stop the rest from being cleaned up. Safe to
    /// call on every launch regardless of whether anything was left behind:
    /// a missing directory (the common case) is treated the same as an empty
    /// one, and re-running it once nothing remains is a no-op.
    static func removeOrphanedFiles() {
        let fileManager = FileManager.default

        guard let leftovers = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in leftovers {
            try? fileManager.removeItem(at: url)
        }
    }
}
