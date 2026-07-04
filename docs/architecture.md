# Architecture

This document explains the major pieces of FolderDrop and, more importantly,
*why* each one exists in its current shape. The code itself is the source of
truth for exact behavior; this document is the source of truth for the
reasoning behind the decisions. For a phase-by-phase account of how each piece
was actually built (including bugs found and rejected approaches), see
[implementation-history.md](implementation-history.md).

FolderDrop is a native macOS app built with SwiftUI, with targeted AppKit
bridging wherever SwiftUI has no equivalent API. It is sandboxed
(`ENABLE_APP_SANDBOX = YES`), which shapes several of the decisions below —
most notably persistence and Quick Look.

---

## MenuBarExtra

FolderDrop has no Dock icon and no regular window — it declares
`LSUIElement` and its entire UI is a single `MenuBarExtra("FolderDrop", ...)`
scene in `.window` style, hosting `ContentView` as a borderless panel anchored
under the menu bar icon.

**Why:** a utility meant to be opened dozens of times a day shouldn't compete
for Dock space or behave like a regular app window (Cmd-Tab, full window
chrome, etc.). `.window` style specifically was chosen over `.menu` because it
supports arbitrary SwiftUI content (lists, buttons, hover states) rather than
being restricted to a simple menu-item layout.

**A consequence worth knowing:** `.window`-style `MenuBarExtra` content can be
torn down and recreated across open/close cycles without a reliable
`.onDisappear`, or — depending on how SwiftUI decides to manage it — kept
alive across the whole process lifetime. FolderDrop's code cannot assume
either one; state that must never be duplicated (like the keyboard shortcuts
monitor) is kept in a process-global `static var` rather than `@State`
specifically because of this.

---

## Folder hierarchy & navigation

`ContentView` tracks three pieces of state to represent "where the user is":

- `rootFolders: [URL]` — every folder the user has added
- `currentRoot: URL?` — which root folder owns the current browsing session
- `currentFolder: URL?` — where the user currently is (may be several levels
  below `currentRoot`)

**Why split root from folder:** sandboxed access is granted per security-scoped
bookmark, and only root folders have one. Reading any file or subfolder
several levels deep only requires `currentRoot`'s scope to be open — child
paths are read directly via `FileManager` — so `currentRoot` is the one
boundary every filesystem operation actually needs to know about, regardless
of how deep `currentFolder` goes. This became a load-bearing assumption for
every later feature that touches the filesystem (drag, Quick Look, watching).

Navigating in (`navigateIntoFolder`) only reassigns `currentRoot` when
stepping out of the root list for the first time; going back (`goBack`) steps
up one directory level, or exits to the root list entirely once `currentFolder
== currentRoot`. `FolderNavigation` centralizes the "can I go back?" predicate
so the Back button and the Escape key handler can't drift out of sync with
each other.

---

## FolderWatcher (live folder refresh)

FolderDrop reloads its file list automatically when the displayed folder's
contents change on disk — a new download appearing, a file renamed in Finder,
and so on — without polling.

`FolderWatcher` wraps `DispatchSourceFileSystemObject`, a GCD interface over
the BSD kqueue vnode API: it opens a single file descriptor on a folder and
lets the kernel notify it when that specific path is written to, renamed, or
deleted. **Why not polling:** the kernel only wakes FolderDrop when something
actually changes, instead of the app repeatedly re-reading a folder that
almost never changes between checks.

FolderDrop runs more than one watcher at once, for a specific reason:

- One watcher tracks whatever folder is currently displayed, for **content**
  changes (files added/removed/renamed inside it).
- One watcher per root folder tracks the **root folder itself**, for
  deletion/rename of the root. A single "watch the current location" design
  would miss a root folder being deleted while browsing several levels beneath
  it — the vnode event for a delete/rename fires on the item that was
  deleted/renamed, not on unrelated descendants that still exist unchanged, so
  a subfolder's own watcher has no way to observe its ancestor disappearing.

Bursts of filesystem events (e.g. a multi-file copy) are debounced — each
event cancels and reschedules a single pending reload a short delay later — so
a burst collapses into one UI refresh instead of one per event. This is a
one-shot delayed dispatch, not a repeating timer: nothing is scheduled until a
real event arrives.

---

## Selection

`SelectionState` reproduces Finder's three selection gestures — plain click,
⌘-click (toggle), and ⇧-click/⇧-arrow (range) — as a plain value type: no
callbacks, no side effects, just old state plus an intent producing new state.

**Why a value type instead of a class/view model:** selection logic is pure
enough to test and reason about as data transformations, and `ContentView`
already owns it as `@State`, so there's no need for reference semantics or
`ObservableObject`.

**Why the persistent selection and the live Shift range are two separate sets**
rather than one: a single `Set` cannot correctly express "Command-selected
items that must survive a Shift range shrinking or growing." An early
single-`Set` design lost ⌘-selected items to a later Shift range; naively
union-ing the range in fixed that but then let a *shrinking* Shift range leave
stale items stuck selected forever, since union only grows. Splitting into
`committedEntries` (touched only by click/⌘-click) and `shiftRangeEntries`
(reassigned from scratch on every Shift action) lets the range grow or shrink
freely without disturbing anything Command already committed.

---

## Quick Look

`QuickLookService` wraps `QLPreviewPanel` — the only native Quick Look API
available on macOS (unlike iOS's `QLPreviewController`, there is no SwiftUI-
native equivalent). It's driven directly as a singleton, since FolderDrop is
the sole invoker of Quick Look for its own content rather than participating
in a system-wide responder-chain search.

**Why the service owns its own `isPanelOpen` boolean** instead of reading
`QLPreviewPanel.shared()?.isVisible` directly: AppKit's own delegate callback
(`previewPanelWillClose`) only fires for the panel's *native* close path
(e.g. Escape), not for FolderDrop's own programmatic `close()`, which would
otherwise leave state stale immediately after closing it ourselves. Making the
service the single source of truth for "is this open" — updated synchronously
by `show()`/`close()` — avoids relying on that asynchronous, native-close-only
signal for state used deterministically by callers (like Space-to-toggle).

**Sandboxing consequence:** `quicklookd` is a separate system process that
reads the file directly off disk, so the security scope must stay open for as
long as the panel is *displaying* the file — not just for the instant it's
requested. Every file in a preview session lives under the same root bookmark,
so one open/close bracket around `show()`/`close()` covers any number of
previewed files.

Quick Look temporarily owns keyboard focus, which FolderDrop's borderless
panel doesn't automatically get back once Quick Look closes — see
[Focus restoration](#focus-restoration) below.

---

## Focus restoration

`FocusRestoration` exists to solve one narrow problem: `MenuBarExtra`'s
backing window is a non-activating auxiliary panel, and AppKit does not
automatically hand key status back to it once another real window (like
`QLPreviewPanel`) has taken and then relinquished it. Ordinarily a user's next
click on FolderDrop would trigger AppKit's own click-to-focus path and paper
over this — `FocusRestoration` gives that same recovery an explicit call site,
triggered the moment AppKit *confirms* (via `NSWindow.didResignKeyNotification`
on the Quick Look panel, not merely FolderDrop's own decision to close it)
that Quick Look has actually resigned key status.

---

## Persistence & security-scoped bookmarks

Sandboxed apps lose filesystem access to a user-chosen location the instant
the process that received it (here, `NSOpenPanel`) exits. A security-scoped
bookmark is the mechanism macOS provides for re-deriving that same grant on a
future launch without asking the user to re-pick the folder every time.

`FolderPersistence` wraps `UserDefaults` plus
`URL.bookmarkData(options: .withSecurityScope, ...)`:

- **Adding** a folder stores a bookmark alongside the existing set.
- **Restoring** resolves every stored bookmark, drops any that no longer
  resolve or whose target no longer exists on disk, and transparently
  re-writes any bookmark macOS reports as stale (`bookmarkDataIsStale`) — the
  user is never asked to re-grant access for a folder that still exists.

Access is always bracketed tightly around the operation that needs it
(`startAccessingSecurityScopedResource()` / `defer { stop... }`), never held
open persistently — a pattern established early and reused by every feature
that touches the filesystem (loading contents, opening files, dragging,
Quick Look, and the root-folder watchers).

Because a security-scoped bookmark only exists for *root* folders, deleting a
root folder in Finder (rather than the app) needs its own detection path — see
[FolderWatcher](#folderwatcher-live-folder-refresh) above and
`ContentView.pruneDeadRootFolders`/`handleRootFolderMaybeRemoved`, which drop a
root from both `UserDefaults` and the in-memory list the moment its watcher
(or a routine reload) confirms it no longer exists.

---

## Settings

Settings is a native `Settings { SettingsView() }` scene, separate from the
`MenuBarExtra` scene — SwiftUI's `Settings` scene is a singleton window by
construction, so repeated `openSettings()` calls (wired to the header's gear
icon) just refocus the existing window with no custom "already open" tracking
needed.

`SettingsView` splits into three pages (`TabView`: General, Hotkeys, About) —
the classic macOS Settings pattern, one icon per tab in the window toolbar.
`SettingsKeys` is the only artifact shared between `SettingsView` and the rest
of the app: a single set of `UserDefaults` key strings. There is no settings
"manager" or view model — `@AppStorage`, backed by the same key, is what keeps
every observer (both `SettingsView` and `ContentView`) in sync, because
there's exactly one copy of each preference's value, living in `UserDefaults`
itself.

**Launch at Login is the one exception:** it's backed by `SMAppService`, not
`UserDefaults`, because `SMAppService.mainApp.status` is itself the real
source of truth and can change outside the app (e.g. the user removes it via
System Settings). `SettingsView` mirrors that status into local `@State`,
refreshed every time the Settings window opens rather than cached, and
"Restore Defaults" deliberately excludes it — resetting the three
`UserDefaults`-backed preferences was requested; touching login-item
registration was not.
