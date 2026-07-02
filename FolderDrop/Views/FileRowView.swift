//
//  FileRowView.swift
//  FolderDrop
//
//  Renders a single row in the file list.
//  Isolating rows makes the list easy to extend later (icons, drag handles, etc.).
//

import SwiftUI
import UniformTypeIdentifiers

struct FileRowView: View {
    let entry: FolderEntry
    /// The security-scoped root folder this entry lives under. Needed to briefly
    /// reopen sandbox access while handing the file off to a drag session.
    var root: URL?

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: FileIconProvider.icon(for: entry.url))
                .resizable()
                .frame(width: 16, height: 16)

            Text(entry.name)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .modifier(FileDragModifier(entry: entry, root: root))
    }
}

/// Applies native drag-and-drop only to file rows, leaving folder rows unaffected.
private struct FileDragModifier: ViewModifier {
    let entry: FolderEntry
    let root: URL?

    func body(content: Content) -> some View {
        if entry.isDirectory {
            content
        } else {
            content.onDrag {
                Self.dragItemProvider(for: entry.url, root: root)
            } preview: {
                HStack(spacing: 4) {
                    Image(nsImage: FileIconProvider.icon(for: entry.url))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(entry.name)
                }
                .padding(6)
            }
        }
    }

    /// NSItemProvider(contentsOf:) reads the file lazily, whenever the destination asks
    /// for it — which happens well after the drag starts, by which point our sandbox
    /// scope would already be closed. Instead we copy the file to a plain temp location
    /// ourselves up front, under an open scope, and hand that (already sandbox-free)
    /// copy to two representations:
    ///  - registerFileRepresentation, for AppKit apps (Finder, Mail) that negotiate the
    ///    coordinated/promise file protocol.
    ///  - registerObject(NSURL), for Chromium/Electron apps (Chrome, Slack, VS Code,
    ///    ChatGPT) that read a `public.file-url` straight off the pasteboard and expect
    ///    it to already resolve to a real file, with no negotiation.
    private static func dragItemProvider(for url: URL, root: URL?) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = url.deletingPathExtension().lastPathComponent

        let typeIdentifier = UTType(filenameExtension: url.pathExtension)?.identifier
            ?? UTType.data.identifier

        let stagedURL = stageCopy(of: url, root: root)

        if let stagedURL {
            provider.registerObject(stagedURL as NSURL, visibility: .all)
        }

        provider.registerFileRepresentation(
            forTypeIdentifier: typeIdentifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            guard let stagedURL else {
                completion(nil, false, CocoaError(.fileReadNoPermission))
                return nil
            }
            completion(stagedURL, false, nil)
            return nil
        }

        scheduleCleanup(of: stagedURL)

        return provider
    }

    /// Copies the file into its own throwaway directory under an open security scope.
    /// The copy carries plain file permissions, so destination apps can read it without
    /// needing any access to our sandbox container.
    private static func stageCopy(of url: URL, root: URL?) -> URL? {
        let didAccess = root?.startAccessingSecurityScopedResource() ?? false
        defer { if didAccess { root?.stopAccessingSecurityScopedResource() } }

        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderDropDrag", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagedURL = stagingDirectory.appendingPathComponent(url.lastPathComponent)

        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: stagedURL)
            return stagedURL
        } catch {
            return nil
        }
    }

    /// AppKit doesn't delete the source file it copies from during a drag, so we own its
    /// lifecycle. The delay gives slower destinations (network drives, large uploads)
    /// enough time to finish reading before the copy is removed.
    private static func scheduleCleanup(of stagedURL: URL?) {
        guard let stagedURL else { return }
        let stagingDirectory = stagedURL.deletingLastPathComponent()

        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            try? FileManager.default.removeItem(at: stagingDirectory)
        }
    }
}
