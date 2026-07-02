//
//  FocusDebugLog.swift
//  FolderDrop
//
//  TEMPORARY instrumentation for the R0.1 Quick Look focus/responder-chain
//  investigation. Everything in this file is compiled out of Release builds
//  via #if DEBUG, and every call site elsewhere is tagged with the comment
//  `// DEBUG-INSTRUMENTATION` so this file plus all its call sites can be
//  found and deleted in a single commit once the root cause is identified.
//  Nothing here changes production behavior — logging only.
//

#if DEBUG
import AppKit

enum FocusDebugLog {
    static func key(_ message: @autoclosure () -> String) {
        print("[DEBUG-INSTRUMENTATION][Key] \(message())")
    }

    static func quickLook(_ message: @autoclosure () -> String) {
        print("[DEBUG-INSTRUMENTATION][QuickLook] \(message())")
    }

    static func focusChain(_ message: @autoclosure () -> String) {
        print("[DEBUG-INSTRUMENTATION][Focus] \(message())")
    }

    /// Snapshot of app-wide activation/window state. Call immediately before
    /// focus-sensitive operations (opening/closing Quick Look, handling Space)
    /// so the state that led to a decision is visible in the log, not just
    /// the state after.
    static func appStateSnapshot(context: String) {
        focusChain("""
        [\(context)] NSApp.isActive=\(NSApp.isActive) \
        NSApp.keyWindow=\(describe(NSApp.keyWindow)) \
        NSApp.mainWindow=\(describe(NSApp.mainWindow))
        """)
    }

    static func describe(_ window: NSWindow?) -> String {
        guard let window else { return "nil" }
        return "\(type(of: window))(title: \"\(window.title)\", isVisible: \(window.isVisible), isKey: \(window.isKeyWindow), isMain: \(window.isMainWindow))"
    }

    /// Full dump of NSApp.windows plus NSApp's own key/main/active state, for
    /// the R0.3 investigation into what AppKit believes the window hierarchy
    /// is at a specific moment (immediately after Quick Look closes, and
    /// immediately after a mouse click restores focus).
    static func logWindowHierarchy(context: String) {
        focusChain("===== window hierarchy: \(context) =====")
        for window in NSApp.windows {
            focusChain("""
            window=\(type(of: window)) number=\(window.windowNumber) \
            title="\(window.title)" isVisible=\(window.isVisible) \
            isKeyWindow=\(window.isKeyWindow) isMainWindow=\(window.isMainWindow) \
            canBecomeKey=\(window.canBecomeKey) canBecomeMain=\(window.canBecomeMain) \
            level=\(window.level.rawValue) \
            collectionBehavior=\(window.collectionBehavior.rawValue)
            """)
        }
        focusChain("""
        NSApp.keyWindow=\(describe(NSApp.keyWindow)) \
        NSApp.mainWindow=\(describe(NSApp.mainWindow)) \
        NSApp.isActive=\(NSApp.isActive)
        """)
        focusChain("===== end window hierarchy: \(context) =====")
    }

    /// Recursively dumps a view hierarchy's class names and frames, flagging
    /// NSOutlineView instances and any class whose name mentions "sidebar" —
    /// for the NSOpenPanel sidebar-responder investigation, to find exactly
    /// which private AppKit view the sidebar actually is.
    static func dumpViewHierarchy(_ view: NSView, indent: String = "") {
        let className = String(describing: type(of: view))
        var markers = ""
        if view is NSOutlineView { markers += " <-- NSOutlineView" }
        if className.lowercased().contains("sidebar") { markers += " <-- class name contains 'sidebar'" }
        focusChain("\(indent)\(className) frame=\(view.frame)\(markers)")
        for subview in view.subviews {
            dumpViewHierarchy(subview, indent: indent + "  ")
        }
    }

    /// Full responder/key-state snapshot for a specific window — used for the
    /// NSOpenPanel sidebar investigation to see exactly who owns first
    /// responder, before and after the path popup is clicked.
    static func logResponderState(context: String, window: NSWindow?) {
        guard let window else {
            focusChain("[\(context)] window=nil")
            return
        }
        let firstResponder = window.firstResponder
        let initialFirstResponder = window.initialFirstResponder
        focusChain("""
        [\(context)] firstResponder=\(String(describing: type(of: firstResponder))) (\(firstResponder)) \
        initialFirstResponder=\(initialFirstResponder.map { String(describing: type(of: $0)) } ?? "nil") \
        window.isKeyWindow=\(window.isKeyWindow) window.isMainWindow=\(window.isMainWindow) \
        NSApp.keyWindow=\(describe(NSApp.keyWindow)) NSApp.mainWindow=\(describe(NSApp.mainWindow))
        """)
    }
}

/// Installs temporary NotificationCenter observers to trace window key/main
/// transitions and app activation state during the focus-chain investigation.
/// Started once from FolderDropApp at launch. Delete this whole class (and its
/// call site in FolderDropApp.init) once the investigation concludes.
final class FocusDebugObserver {
    static let shared = FocusDebugObserver()
    private var didStart = false

    func start() {
        guard !didStart else { return }
        didStart = true

        let center = NotificationCenter.default

        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            FocusDebugLog.focusChain("NSWindow.didBecomeKeyNotification: \(FocusDebugLog.describe(note.object as? NSWindow))")
        }
        center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { note in
            FocusDebugLog.focusChain("NSWindow.didResignKeyNotification: \(FocusDebugLog.describe(note.object as? NSWindow))")
        }
        center.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { note in
            FocusDebugLog.focusChain("NSWindow.didBecomeMainNotification: \(FocusDebugLog.describe(note.object as? NSWindow))")
        }
        center.addObserver(forName: NSWindow.didResignMainNotification, object: nil, queue: .main) { note in
            FocusDebugLog.focusChain("NSWindow.didResignMainNotification: \(FocusDebugLog.describe(note.object as? NSWindow))")
        }
        center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            FocusDebugLog.focusChain("NSApplication.didBecomeActiveNotification")
        }
        center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            FocusDebugLog.focusChain("NSApplication.didResignActiveNotification")
        }

        // R0.3: snapshot the window hierarchy right after a click inside FolderDrop
        // restores focus, for comparison against the post-Quick-Look-close snapshot.
        // Never consumes the event (always returns it unchanged) — observation only.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            DispatchQueue.main.async {
                FocusDebugLog.logWindowHierarchy(context: "immediately after mouse click inside FolderDrop")
            }
            return event
        }
    }
}
#endif
