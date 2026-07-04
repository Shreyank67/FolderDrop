//
//  FolderWatcher.swift
//  FolderDrop
//
//  Watches a single folder URL for filesystem changes and reports them via a
//  callback. Built on DispatchSourceFileSystemObject (a GCD wrapper around the
//  BSD kqueue vnode API) rather than polling: the kernel wakes us only when the
//  watched directory's contents actually change, so there's no timer running
//  while nothing happens.
//

import Foundation

final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    /// Multiple filesystem events (e.g. a multi-file copy) often arrive in a
    /// burst. Each event cancels any pending callback and reschedules a single
    /// one a short delay later, so a burst collapses into exactly one reload
    /// instead of one per event. This is not a repeating timer — nothing is
    /// scheduled until an actual event arrives, and it fires at most once per
    /// burst.
    private let debounceInterval: TimeInterval = 0.25

    /// Begins watching `folder` for content changes. `root` is the
    /// security-scoped bookmark URL that grants access to `folder`; access is
    /// only needed for the instant the directory is opened — once we hold an
    /// open file descriptor, the kernel lets us keep monitoring it without the
    /// security scope remaining active.
    func start(folder: URL, root: URL, onChange: @escaping () -> Void) {
        stop()

        let didAccess = root.startAccessingSecurityScopedResource()
        let descriptor = open(folder.path, O_EVTONLY)
        if didAccess {
            root.stopAccessingSecurityScopedResource()
        }
        guard descriptor >= 0 else { return }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        newSource.setEventHandler { [weak self] in
            self?.scheduleDebouncedReload(onChange)
        }

        newSource.setCancelHandler {
            close(descriptor)
        }

        newSource.resume()
        source = newSource
    }

    func stop() {
        pendingReload?.cancel()
        pendingReload = nil
        source?.cancel()
        source = nil
    }

    private func scheduleDebouncedReload(_ onChange: @escaping () -> Void) {
        pendingReload?.cancel()
        let workItem = DispatchWorkItem(block: onChange)
        pendingReload = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    deinit {
        stop()
    }
}
