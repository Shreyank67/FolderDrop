# Implementation History

This document describes how FolderDrop was built, feature by feature, in the
order the work actually happened. It's written for whoever picks this project
up next — the goal is to explain *why* the code looks the way it does, not
just what it does. The codebase itself is the source of truth for current
behavior; this document is the source of truth for the reasoning behind it.

For the current feature set, known limitations, and what's planned next, see
[roadmap.md](roadmap.md). For the "why" behind the architecture as it exists
today (rather than how it evolved), see [architecture.md](architecture.md).

FolderDrop is a native macOS `MenuBarExtra` (`.window` style) app, built with
SwiftUI plus targeted AppKit bridging where SwiftUI has no native equivalent.
It is sandboxed (`ENABLE_APP_SANDBOX = YES`), which shaped several of the
decisions below.

Each phase below is presented as **Problem → Solution → Files Changed →
Outcome**, in the order the work happened.

---

## Folder Navigation

### Problem

Let the user pick one or more folders once, browse into their contents from
the menu bar, and have that access persist across app restarts — without
re-prompting for permission every time. This is the foundation of the app:
everything else (drag, Quick Look, selection) operates on the entries this
feature produces.

### Solution

**Root folder persistence.** `FolderPersistence` wraps `UserDefaults` and
macOS's security-scoped bookmark API. Adding a folder (`NSOpenPanel`) stores a
bookmark (`URL.bookmarkData(options: .withSecurityScope, ...)`); restoring at
launch resolves each stored bookmark, drops any that no longer resolve or
whose target no longer exists, and transparently refreshes stale bookmarks.
Multiple root folders were supported from early on — `rootFolders` is an
array, not a single URL.

**Browsing and back navigation.** `ContentView` owns `currentRoot` (which root
bookmark grants access to the current browsing session) and `currentFolder`
(where the user currently is, which may be several levels below
`currentRoot`). Reading a folder's contents (`FolderContentsLoader`) only
requires `currentRoot.startAccessingSecurityScopedResource()` — child paths
are read directly via `FileManager`, without needing their own bookmarks. This
became a load-bearing assumption for later features (drag, Quick Look): **any
operation on a file only needs the security scope of the root it lives under,
opened for the duration of that operation, not a bookmark of its own.**

**Root folder management.** Root folders gained a native context menu
(Open / Reveal in Finder / Remove), implemented in `RootFolderRow`. Removal
uses `NSAlert.runModal()` rather than SwiftUI's `.confirmationDialog` —
`MenuBarExtra`'s panel dismisses itself on any click it perceives as
"outside," which raced with and swallowed the SwiftUI dialog's button tap
before the action closure could run. `NSAlert`'s modal session resolves the
button click before returning, sidestepping that race entirely.

**Header, breadcrumbs, back button.** `FolderHeaderView` shows the app title,
either the root folder count or the current folder's name plus a
"›"-joined breadcrumb of its parent path. The Back button was iterated on
several times during UI Polish (see below) — it started as a bordered push
button and ended as a plain, hover-tinted, borderless affordance closer to
Finder.

**Architectural decisions:** Security-scoped access is always bracketed
tightly around the operation that needs it (`start...` / `defer { stop... }`),
never held open persistently — established here, reused by every later
feature that touches the filesystem. Folder navigation state (`currentRoot`,
`currentFolder`, `folderEntries`) lives in `ContentView`; child views are
given data and callbacks, not direct access to this state.

### Files Changed

`Services/FolderPersistence.swift`, `Services/FolderContentsLoader.swift`,
`ContentView.swift`, `Views/RootFolderRow.swift`, `Views/FolderHeaderView.swift`

### Outcome

Users can add any number of root folders, browse into subfolders, go back up
(one level, or all the way to the root list), and the whole session survives
an app relaunch with folders restored automatically.

Security-scoped bookmarks can go stale (e.g. after an OS update or the
underlying volume changing) without becoming fully invalid — `restore()`
detects `bookmarkDataIsStale` and re-writes a fresh bookmark transparently, so
the user never has to re-grant access for a folder that still exists.

---

## Multi-File Drag & Drop

### Problem

Let users drag a file straight from FolderDrop into Finder, Mail, Chrome,
Slack, VS Code, or ChatGPT — matching how dragging works from Finder — and
later, drag a whole multi-selection at once. FolderDrop's whole purpose is to
get files into other apps faster than opening Finder first; drag-and-drop is
the primary way users do that.

### Solution

**Phase 1 — Single-file drag via `.onDrag`.** `FileRowView` attaches SwiftUI's
`.onDrag(_:preview:)` to file rows (never folders). The naive first attempt —
`NSItemProvider(contentsOf: url)` — turned out to be wrong: it registers a
*lazy* read that only fires when a consumer asks for the data, by which point
our security scope (opened only around the synchronous call) had already
closed. The fix was to copy the file to a plain, unscoped temp location
*before* handing anything to the destination: `registerFileRepresentation`/
`registerObject(NSURL)` both point at a synchronously-staged copy
(`stageCopy(of:root:)`), made under a briefly-opened root scope. The
destination app never touches our sandbox at all — it reads a completely
ordinary file.

**Fixing cross-app compatibility.** The staged file was initially registered
only via `registerFileRepresentation` (the coordinated/promise protocol
AppKit apps like Finder and Mail negotiate). Chromium/Electron apps (Chrome,
Slack, VS Code, ChatGPT) don't negotiate that protocol — they read a
`public.file-url` pasteboard entry directly and expect it to already resolve.
Adding `registerObject(stagedURL as NSURL, visibility: .all)` alongside the
existing representation fixed this without touching the AppKit-facing path.

**Filename and cleanup fixes.** `suggestedName` was initially set to the full
filename (`"a1.PNG"`), which some destinations then appended their own
canonical extension to, producing `"a1.PNG.PNG"`. Fixed by setting
`suggestedName` to the base name only. Staged files are cleaned up on a delay
(`scheduleCleanup`, later made configurable — see Settings) since AppKit
doesn't delete the source it read from.

**Phase 2 — Multi-file drag.** Once multi-selection existed, dragging any
member of a 2+ file selection needed to carry *all* selected files as one
drag operation (Finder-style). SwiftUI's `.onDrag` cannot do this — it always
produces exactly one `NSDraggingItem` per call, with no array-returning
overload on macOS. The only way to get a genuine multi-item
`NSDraggingSession` is the native AppKit API:
`NSView.beginDraggingSession(with:event:source:)`. A small
`NSViewRepresentable` (`MultiFileDragSourceView` / `DragSourceNSView`,
implementing `NSDraggingSource`) overlays a row *only* when it's part of an
existing 2+ selection; every other case (single file, or dragging a file
that isn't currently selected — which first collapses the selection to just
that file, matching Finder) still goes through the original, untouched
`.onDrag` path.

The multi-item bridge tracks `mouseDown` → `mouseDragged`/`mouseUp` using the
standard AppKit drag-vs-click distance-threshold idiom. Past the threshold it
calls `beginDraggingSession` with one `NSDraggingItem` per selected file,
each staged via the *same* `stageCopy`/`scheduleCleanup` functions as the
single-file path (no duplicated staging logic). Below the threshold — a plain
click, not a drag — it replicates the exact plain/⌘/⇧ click decision
`FileListView`'s own tap gesture makes, because overriding `mouseDown` means
SwiftUI's gesture never sees that event otherwise.

One correction made along the way: `NSDraggingItem(pasteboardWriter:)` needs a
type conforming to `NSPasteboardWriting`, and `NSItemProvider` does **not**
conform to that on macOS (confirmed by the compiler, not assumed) — so the
multi-item path hands `NSDraggingItem` the staged file's plain `NSURL`
instead, the same `public.file-url` representation the single-file path
already registers for Chromium/Electron.

**Architectural decisions:** Two drag mechanisms coexist deliberately —
`.onDrag` (SwiftUI-native, used for the single-file case, functionally
unchanged since Phase 1) and the AppKit bridge (used only for genuine
multi-item drags) — rather than unifying everything under the AppKit bridge,
to avoid risking regressions in the already-verified single-file path. All
staging/cleanup logic lives in one place (`FileDragModifier`'s static
functions, marked `fileprivate` so the AppKit bridge in the same file can
reuse them).

### Files Changed

`Views/FileRowView.swift` (`FileDragModifier`, `MultiFileDragSourceView`,
`DragSourceNSView`)

### Outcome

Dragging a single file (or a file outside the current selection, which
collapses selection to it first) works exactly as a native single-file drag.
Dragging any member of an existing multi-selection carries the entire
selection as one native multi-item drag session, with AppKit's automatic
fan/stack preview and item-count badge — no custom preview view was needed
for that.

Multi-item drag previews are entirely native AppKit behavior once more than
one `NSDraggingItem` is supplied. `List`/`NSTableView`'s own automatic
multi-item drag bundling (tied to `List(selection:)`) was considered and
rejected, because FolderDrop's click/⌘-click/⇧-click semantics are handled
entirely by custom gesture code, not `List`'s native selection.

---

## Quick Look

### Problem

Let the user preview a file (or the whole current selection) without opening
it, matching Finder's Space-bar Quick Look — requested as a natural companion
to selection/keyboard navigation: "inspect, don't necessarily open."

### Solution

**Phase 1 — Single-file preview.** `QuickLookService` wraps `QLPreviewPanel`,
conforming to `QLPreviewPanelDataSource`/`Delegate`. macOS has no SwiftUI-
native Quick Look (unlike iOS's `QLPreviewController`), so `QLPreviewPanel` is
the only native option. The panel is driven directly as a singleton (no
`NSResponder acceptsPreviewPanelControl` dance, since FolderDrop is the sole
invoker of Quick Look for its own content). Keyboard handling required a
similar investigation: SwiftUI gives no supported hook to insert a custom
`NSResponder` for a global Space-bar shortcut inside a `MenuBarExtra`, so a
local `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` monitor was used
instead, intercepting only the keys FolderDrop cares about and passing
everything else through untouched.

Sandboxing detail: `quicklookd` (a separate system process) reads the file
directly, so the security scope must stay open for the *entire time the
panel is displaying it* — not just the instant it's requested, the same
lesson learned in Drag & Drop.

**Bug: toggle got stuck.** Space → open worked, but a second Space press did
nothing. Root cause: `isShowing` was derived from
`QLPreviewPanel.shared()?.isVisible` (AppKit's live state) and `close()` only
called `orderOut(nil)`, relying on the `previewPanelWillClose` delegate
callback to clear our own state — but that callback only fires for the
panel's own native close sequence, not for our own `orderOut` call, leaving
state stale immediately after our own `close()`. Fixed by making
`QuickLookService` the sole source of truth: an internal `isPanelOpen`
boolean, flipped synchronously by `show()`/`close()`, with
`previewPanelWillClose` reduced to a guarded safety net for genuinely native
closes (Escape) that don't go through our own `close()`.

**Regression after SelectionState/multi-drag work.** The exact same
"second Space press does nothing" symptom reappeared later, but
`QuickLookService`'s logic was unchanged. Root cause this time:
`keyboardShortcutsMonitor` and `quickLookService` were `@State`, scoped to one
`ContentView` *instance*. `MenuBarExtra`'s `.window`-style content can be torn
down and recreated across open/close cycles without a reliable
`.onDisappear`, leaking a stale monitor. Since `NSEvent` local monitors
dispatch in registration order and an earlier one returning `nil` suppresses
*later* monitors too, a leaked monitor could silently intercept every Space
press meant for the current session. Fixed by making the monitor slot a
`private static var` (genuinely process-global, unlike `@State`) and having
`installKeyboardShortcutsMonitor()` unconditionally remove any existing
monitor before installing a new one.

**Phase 2 — Multi-item preview.** Once multi-selection existed, Space needed
to preview the *entire* selection (not just the active file) when more than
one file was selected, with Left/Right arrow cycling through them inside the
panel. `QuickLookService` was extended from a single `previewedURL` to
`previewItems: [URL]` + `currentIndex: Int`; `numberOfPreviewItems`/
`previewItemAt:` report the full array, and `QLPreviewPanel` handles
Left/Right navigation across them **natively** — no custom navigation code
was needed once the data source reports more than one item.
`panel.currentPreviewItemIndex` is set after `reloadData()` so the panel
initially displays the active file, not just the first item. Root-scope
lifetime didn't need to change: every file in a selection lives under the
same root bookmark, so the existing single open/close bracket already
covered any number of them.

**Settings integration.** An "Enable Quick Look" toggle (see Settings &
Preferences) gates the Space handler; when off, Space is simply a no-op for
files while Enter-to-open and context menus are unaffected, since they never
depended on `quickLookService`.

**Architectural decisions:** `QuickLookService` never touches `SelectionState`
or vice versa — it receives already-resolved `[FolderEntry]` plus an active
entry from `ContentView`. `isPanelOpen` (and later `previewItems`) is the
single source of truth, deliberately not derived from AppKit's own live
window state, after the first toggle bug proved that indirection unreliable.

### Files Changed

`Services/QuickLookService.swift`, `ContentView.swift`

### Outcome

Space previews the active file (or the whole selection, arranged in
on-screen order, if more than one file is selected), with the active file
shown first. Space again closes it immediately. Escape closes it natively
(unhandled by FolderDrop's own monitor when the panel is open). Closing Quick
Look — by any means — never changes the current selection.

`QLPreviewPanel` closes itself on Escape natively; FolderDrop's own Escape
handling explicitly defers to it rather than trying to duplicate that
behavior. Multi-item Left/Right cycling inside the panel is entirely native —
a direct consequence of reporting `numberOfPreviewItems > 1`.

---

## Keyboard Navigation

### Problem

Let the whole app — folder browsing, file selection, opening, previewing,
going back — be operable from the keyboard, matching Finder's list-view
conventions. A menu bar utility that requires mouse-only interaction is
slower than just using Finder; keyboard-first interaction is a core
differentiator.

### Solution

**Enter to open.** Added to the same `NSEvent` local monitor Quick Look
already used — reusing one monitor was a deliberate choice over adding a
second, to keep all keyboard handling centralized and avoid multiple monitors
racing over the same events. Enter opens files (`openFile`) and navigates
into folders (`navigateIntoFolder`), branching on `entry.isDirectory`.

**Up/Down arrow navigation.** `moveSelection(by:)` computes the current index
via `folderEntries.firstIndex(of:)` and steps by one; at either edge it's a
no-op. This required making `FolderEntry` `Equatable`.

**Enabling it for the root folder list, plus hover-seeded start.** Arrow
navigation initially only visibly worked for subfolder browsing — root list
rows had lost their `isSelected` wiring in an earlier click-model refactor
(folders don't participate in mouse-click selection, so the wiring was
dropped, then had to be restored specifically for *keyboard* selection).
Separately, a `hoveredEntry` concept was introduced — purely to decide where
Up/Down should *start* when nothing is selected yet (seed from whatever row
is currently hovered, falling back to the first entry). Hover state stays
local/visual to each row otherwise; only this one seed value is surfaced
upward, and it's never written back from selection changes.

**Scroll-follows-selection.** `FileListView` wraps its `List` in a
`ScrollViewReader` and calls `proxy.scrollTo(activeEntry.id, anchor: .center)`
on change — `anchor: .center` specifically so repeatedly pressing an arrow
key past the visible edge keeps re-centering rather than only nudging the
selected row barely into view.

**Escape → Back, deferring to Quick Look.** Escape only triggers `goBack()`
if Quick Look isn't currently showing (checked first) and there's actually
somewhere to go back to — otherwise the key passes through untouched.

**Interaction model iterations.** The click model itself changed direction
several times during development (documented in more detail under
Multi-Selection): double-click-to-open was introduced, then deliberately
removed again because pairing `.onTapGesture(count: 1)` with `(count: 2)`
forces SwiftUI to hold every single click for the OS's double-click window
before committing it — a perceptible delay for a menu-bar utility. The final
model: a single, uncounted tap per row (folders navigate immediately, files
select immediately), with Enter covering "open."

**⌘A / ⌘⇧A.** Added to the same monitor. Select All reuses `SelectionState`'s
existing `toggle(_:)` in a loop from a cleared state, so `activeEntry`/
`selectionAnchor` end up on the last file and keyboard navigation continues
normally afterward. Deselect All (⌘⇧A) and clicking empty list whitespace
both clear `SelectionState` and close Quick Look if it's open.

**Architectural decisions:** Exactly one `NSEvent` keyDown monitor exists for
the whole app, made process-global (`static var`, not `@State`) after the
leaked-monitor regression described under Quick Look. Every keyboard shortcut
— arrows, Enter, Space, Escape, ⌘A, ⌘⇧A — is a `case` in that same monitor's
`switch`. Hover, selection, and keyboard navigation are three separate pieces
of state that only interact at one narrow seam (seeding Up/Down's starting
point from hover), deliberately not merged into one model.

### Files Changed

`ContentView.swift`, `Models/FolderEntry.swift`, `Views/FileListView.swift`

### Outcome

Arrow keys move/extend selection (Shift extends); Enter opens files or
navigates into folders (auto-selecting the new folder's first entry so
navigation can continue immediately); Space toggles Quick Look; Escape goes
back (deferring to an open Quick Look panel first); ⌘A/⌘⇧A select/deselect
everything in the current folder. All of it works identically whether
browsing the root folder list or a subfolder.

`NSEvent.addLocalMonitorForEvents` monitors are dispatched in registration
order, and a monitor returning `nil` suppresses *later-registered* monitors
from seeing that event too — this is what caused the leaked-monitor Quick
Look regression, and is worth remembering before ever adding a second local
monitor anywhere in this app.

---

## Multi-Selection

### Problem

Finder-style multi-selection: single click, ⌘-click (toggle), ⇧-click/
⇧-arrow (range), all interoperating the way Finder actually behaves —
including non-obvious cases (a ⌘-selected item surviving a later ⇧-range
operation, a ⇧-range shrinking cleanly without leaving stale items behind).
Required for multi-file drag and multi-item Quick Look; also a baseline
expectation for any Finder-like file browser.

### Solution

**Interaction-model prerequisite.** Before multi-selection could be built,
the click model had to stop conflating "select" and "open." Several turns of
back-and-forth iteration led to the final rule: a single, uncounted tap per
row — folders navigate instantly, files select instantly — with no
double-click anywhere.

**`SelectionState` (Phase 1).** A plain `struct`, not a class, not
`ObservableObject`, not MVVM — deliberately a value type computing new state
from old state plus an intent, with no callbacks or side effects. Holds
`selectedEntries: Set<FolderEntry>`, `activeEntry: FolderEntry?`,
`selectionAnchor: FolderEntry?`, and mutating methods (`selectOnly`,
`toggle`, `selectRange(to:in:)`, `moveActive(by:in:extending:)`, `clear`) that
implement each of plain-click / ⌘-click / ⇧-click(-arrow) / arrow-key
behavior. `FolderEntry` gained `Hashable` to go into a `Set`. Click-intent
detection (which modifier was held) lives in `FileListView`'s tap gesture,
reading `NSEvent.modifierFlags` — SwiftUI's `.onTapGesture` doesn't expose
modifier state itself, so this is the standard native way to get it.

**Bug: ⌘-click items were lost by a later ⇧-range.** The first
`selectRange(to:in:)` implementation *replaced* `selectedEntries` outright
with just the anchor-to-target range, silently dropping any independently
⌘-selected item outside that range. The naive fix (`formUnion` the range in)
was rejected up front — it would have stopped items from disappearing, but
made a *shrinking* ⇧-range leave previously-covered items stuck selected
forever, since union only grows. The actual fix split what had been one
`Set` into two: `committedEntries` (persistent, touched only by
`selectOnly`/`toggle`) and `shiftRangeEntries` (transient, *reassigned* from
scratch on every `selectRange` call, so it can grow or shrink freely with
nothing left behind). `selectedEntries` became a computed union of the two.
`toggle` folds any live `shiftRangeEntries` into `committedEntries` before
applying its own change, so a later ⌘-click doesn't strand whatever Shift had
already covered.

**Wiring multi-file drag and multi-item Quick Look.** Both features consume
`selectionState.selectedEntries`/`activeEntry` directly — no separate
selection model was introduced for either.

**Architectural decisions:** `SelectionState` never touches drag, Quick Look,
or keyboard-monitor code directly; `ContentView` is the only thing that calls
its mutating methods. The committed/transient split exists specifically
because a single `Set` cannot correctly express "persistent selections
independent of the current live Shift range" — arrived at only after the
naive single-`Set` and single-`Set`-plus-`formUnion` approaches were each
shown to be wrong for a specific, reproducible scenario.

### Files Changed

`Models/SelectionState.swift`, `Models/FolderEntry.swift`,
`Views/FileListView.swift`

### Outcome

Plain click selects only that item. ⌘-click toggles one item without
disturbing the rest of the selection. ⇧-click/⇧-arrow selects/extends/shrinks
a range from a fixed anchor, live, without touching independently ⌘-selected
items outside that range. ⌘A selects every file in the current folder;
⌘⇧A (or clicking empty list whitespace) clears the selection.

---

## Settings & Preferences

### Problem

A native Settings window (not a custom in-panel screen) for the preferences
that had accumulated implicit hardcoded behavior (Quick Look always on, drag
cleanup always 60 seconds, no folder-restore option, no Launch at Login).
Once there was more than one piece of tunable behavior, hardcoding it all
stopped being reasonable, and a menu-bar utility with zero settings surface
is unusual for macOS users' expectations.

### Solution

**Phase B.1 — Infrastructure only.** A `Settings { SettingsView() }` scene was
added alongside the existing `MenuBarExtra` scene in `FolderDropApp`.
SwiftUI's `Settings` scene is a singleton window by construction — calling
`openSettings()` (via `@Environment(\.openSettings)`, wired to the header's
gear icon) while it's already open just brings the existing window to front.
`SettingsView` started as a single "General" tab (`TabView`) with placeholder
content only.

**Phase B.2 — General preferences (UI only).** The placeholder was replaced
with a native `Form` / `.formStyle(.grouped)` layout (matching System
Settings' grouped-box look): a Behavior section (Quick Look toggle,
restore-last-folder toggle), a Drag & Drop section (cleanup-delay picker:
30/60/120s), and a read-only Keyboard Shortcuts list. This phase deliberately
built UI only — local `@State`, not yet backed by persistence.

**Phase B.3 — Wiring to the application.** `SettingsKeys.swift` defines the
`UserDefaults` key strings shared between `SettingsView` and the rest of the
app — the only thing that needs to be shared is the key string; the value
itself lives in `UserDefaults`, observed via `@AppStorage`. Behavior wired up:

- **Enable Quick Look** gates the Space handler; when off, Space is a no-op
  for files.
- **Restore last opened folder** persists the plain folder path (not a
  bookmark — child paths only need the root's bookmark) whenever
  `navigateIntoFolder`/`goBack` run, gated by the toggle. At launch, the saved
  path is matched by prefix against the restored roots and existence-checked
  under a briefly-reopened root scope before being applied.
- **Cleanup delay**: `FileRowView`'s previously-hardcoded 60-second delay now
  reads the same `UserDefaults` key the picker writes (falling back to 60 if
  unset).

**Contextual help.** A small helper (title + a `.help(...)`-carrying
`info.circle` icon, later replaced by always-visible inline descriptions —
see "Later — split into dedicated pages" below) was reused for every setting
rather than duplicating the
icon/tooltip wiring per control. SwiftUI's `.help()` has no delay/timing
parameter, and the native AppKit tooltip system it's built on doesn't expose
one either — tooltip delay is a system-wide, undocumented setting, not a
per-app customization point, so no code was written to try to change it.

**Phase B4.1 — Launch at Login.** Isolated in its own `LaunchAtLoginService`,
wrapping `SMAppService.mainApp` (the modern ServiceManagement API — no
deprecated login-item APIs used). Deliberately **not** stored in
`UserDefaults`: `SMAppService`'s own `.status` is the actual source of truth
(and can change outside the app, e.g. via System Settings › Login Items), so
`SettingsView` just mirrors it into one `@State` bool, refreshed on
`.onAppear`. The toggle uses a custom `Binding` rather than a plain one plus
`.onChange`: on a thrown register/unregister error, the backing state is left
untouched (so the `Toggle` visually reverts on its own) and the error's
`localizedDescription` drives a native `.alert(...)`.

**Phase B4.2 — Restore Defaults, Check for Updates, footer.** "Restore
Defaults…" resets the three `UserDefaults`-backed preferences back to their
defaults via a native `.confirmationDialog` — explicitly **not** touching
Launch at Login. "Check for Updates…" is a placeholder `.alert` for a future
real updater. The footer shows the app name and version.

**Later — split into dedicated pages.** As the General page grew, Settings
was reorganized into three pages (`GeneralSettingsView`, `HotkeysSettingsView`,
`AboutSettingsView`) under one `TabView`, each rendering as its own toolbar
icon — matching how System Settings itself is organized once there's more
than one logical group of preferences. The `info.circle` tooltip pattern was
also replaced with `SettingTitleDescription`, an always-visible title +
description underneath each control, matching native System Settings more
closely than a hover-triggered tooltip.

**Architectural decisions:** `SettingsKeys` is the only shared artifact
between `SettingsView` and the rest of the app — no settings "manager" or
view model was introduced. Launch at Login is architecturally separate from
the other three preferences on purpose: its source of truth is
`SMAppService`, not `UserDefaults`, and the two were never allowed to blend.

### Files Changed

`Views/SettingsView.swift`, `Views/GeneralSettingsView.swift`,
`Views/HotkeysSettingsView.swift`, `Views/AboutSettingsView.swift`,
`Views/SettingsComponents.swift`, `Services/SettingsKeys.swift`,
`Services/LaunchAtLoginService.swift`, `FolderDropApp.swift`

### Outcome

A native Settings window (⌘, or the header gear icon) with three pages:
General (Launch at Login, Enable Quick Look, Restore Last Opened Folder,
drag cleanup delay, Restore Defaults), Hotkeys (read-only shortcuts
reference), and About (app info, project links, Check for Updates
placeholder). `Settings` scenes are native singleton windows; repeated
`openSettings()` calls just refocus the existing window.
`SMAppService.mainApp.status` reflects system-level state that can change
outside the app's control, which is why it's read fresh every time the
Settings window opens rather than cached.

---

## UI Polish

### Problem

Bring FolderDrop's visual feel in line with Finder/native macOS conventions,
iteratively, across rows, header, controls, empty states, and overall layout
density. Functionality was built first; once the interaction model
stabilized, the visual presentation was refined in several focused passes.

### Solution

**Row & List Polish (Phase A.1).** Row height, padding, icon-to-text
spacing, and corner radius were tuned iteratively — including one explicit
"overcorrection and revert" (padding went to 13pt, was judged too tall for a
menu-bar utility, and was brought back down to 7pt). Hover color went
through two iterations: first a light system-accent-color tint, then the
neutral, semantic `NSColor.unemphasizedSelectedContentBackgroundColor` (the
same gray AppKit itself uses for a selected-but-not-key-window row), paired
with `NSColor.selectedContentBackgroundColor` for actual selection. Row
separators were hidden so whitespace became the primary separator.

**Header & Navigation (Phase A.2).** Breadcrumb/subtitle typography shrunk
and switched to `NSColor.secondaryLabelColor`; the Back button gained a
`chevron.left` SF Symbol via `Label`.

**Window & Layout Polish (Phase A.3).** Outer padding, window `minWidth`, and
list row insets were each adjusted twice — once outward, then walked back
inward — landing at `minWidth: 304`, 15pt horizontal content padding, and
6pt list row insets.

**Header & Toolbar / Controls Polish (Phase A.4–A.5).** A borderless
`gearshape` Settings button was added beside the title. The Back and Add
Folder buttons were converted to `Label`-based, `.buttonStyle(.borderless)` +
`.controlSize(.small)` controls for a lighter, more Finder-like weight.

**Empty States & Transitions (Phase A.6).** A reusable `EmptyStateView`
(icon + title + subtitle) replaced the bare "no folders" button-only screen
and was added for browsing into a genuinely empty folder. Small
`.animation(...)`/`.transition(.opacity)` fades were added between
navigation states, keyed on existing state rather than introducing new state
for the purpose.

**Column-alignment investigation and fix.** After several rounds of
per-element padding tweaks, the header title, subtitle, breadcrumb, Back
button, and file rows stopped sharing one visual left edge. A full trace
found the root cause: **three independent mechanisms were each reproducing
the "same" offset by convention, not by a shared reference.** Rather than
introduce a new shared layout constant (considered and explicitly rejected
as over-engineering), the fix was simplification: every explicit
`.padding(.leading, ...)` added during the prior passes was removed, leaving
`ContentView`'s single outer `.padding(.horizontal, 15)` as the only
alignment source everything shares.

**Architectural decisions:** Visual/spacing changes were kept strictly
separate from behavior changes throughout — no UI Polish phase touched
`SelectionState`, drag-and-drop, Quick Look, or keyboard handling logic. When
column alignment broke, the fix was to *remove* scattered compensating
padding rather than add a new abstraction.

### Files Changed

`ContentView.swift`, `Views/FileRowView.swift`, `Views/FolderHeaderView.swift`,
`Views/EmptyStateView.swift`

### Outcome

A denser, Finder-adjacent layout: hidden row separators, neutral-gray hover
distinct from accent-colored selection, borderless/light-weight Back and Add
Folder controls, populated empty states instead of blank space, subtle fade
transitions between navigation states, and every text element sharing one
left edge derived from a single padding value.

`NSTrackingArea`-based hover (`.onHover`) dispatch is independent of standard
click hit-testing order — multiple overlapping views can each receive
enter/exit events regardless of which is topmost for clicks, which is why the
multi-file-drag `NSView` overlay was judged safe for hover without needing to
manually re-implement hover forwarding. `List`/`NSTableView` may carry
margins not fully exposed by `contentMargins`/`listRowInsets` — flagged as a
residual, only-verifiable-at-runtime uncertainty during the alignment
investigation.

---

## Live Folder Refresh

### Problem

FolderDrop only reloaded folder contents when its own navigation code called
`reloadContents()`. Downloading a file into the currently-open folder, or any
other external filesystem change, left the UI showing stale contents until
the user manually navigated away and back — for every folder, not just one.

### Solution

`FolderWatcher` (`Services/`) wraps `DispatchSourceFileSystemObject`, a GCD
interface over the BSD kqueue vnode API, watching a single directory's file
descriptor for `.write`/`.rename`/`.delete` events. This was chosen over
polling specifically because the kernel only wakes FolderDrop when something
actually changes, rather than the app repeatedly re-reading a folder that
almost never changes between checks.

`ContentView` owns exactly one `FolderWatcher` for whatever `currentFolder`
currently is, started/stopped from a single `.onChange(of: currentFolder)`
hook — stopping the previous watcher and starting a new one whenever
navigation changes, and stopping outright when `currentFolder` becomes `nil`.
Bursts of filesystem events (e.g. a multi-file copy) are debounced inside
`FolderWatcher` itself: each event cancels and reschedules a single pending
callback a short delay later, collapsing a burst into one reload instead of
one per event — a one-shot delayed dispatch, not a repeating timer.

Security-scoped access is only needed for the instant the watched directory
is `open()`ed — once a file descriptor is held, monitoring continues without
the scope remaining active, consistent with every other filesystem feature's
scope-bracketing pattern.

### Files Changed

`Services/FolderWatcher.swift` (new), `ContentView.swift`

### Outcome

Whenever the currently displayed folder's contents change — new files,
deletions, renames, moves, new subfolders — FolderDrop refreshes
automatically, with no user interaction required and no polling loop running
in the background.

---

## RC1 Interface & Settings UX Polish

### Problem

A UI polish pass ahead of the RC1 milestone: clearer terminology around
adding folders, a more obvious primary action in the onboarding empty state,
and a Back button whose clickable area was too easy to miss.

### Solution

Every user-facing "Add Folder" label was renamed to "Add Root Folder" for
clarity, since "folder" alone was ambiguous next to regular subfolder
browsing. The onboarding empty state's icon was enlarged (~14%), its copy
rewritten ("No root folders added yet" / "Add a root folder to start
browsing your files."), and its action button changed from a small
borderless button to a `.buttonStyle(.bordered)` capsule — more prominent
without becoming a bright filled/blue button, keeping a native, minimal feel.
The Back button's hit area was widened using `.contentShape(Rectangle().inset(by: -6))`
rather than real padding, so the clickable region grows without shifting any
visible layout.

### Files Changed

`ContentView.swift`, `Views/EmptyStateView.swift`

### Outcome

Clearer terminology throughout, a more discoverable primary action on first
launch, and a more forgiving Back button — with zero changes to navigation,
persistence, or any other application behavior (this was explicitly scoped
as a UI-only pass).

---

## Root Folder Lifecycle & RC1 Stability

### Problem

Three related RC1 stability issues: (1) a root folder deleted in Finder
stayed visible in FolderDrop until an unrelated UI action happened to
trigger a reload, and if the user was actively browsing several levels
beneath a deleted root, FolderDrop kept displaying that now-unreachable
location indefinitely; (2) the Back button's hover-highlighted region and
its actual clickable region didn't match; (3) adding a folder that was
already a root folder produced no feedback at all.

### Solution

**Dead root folder detection.** `FolderWatcher`'s single "watch the current
location" design couldn't detect a root folder being deleted while browsing
beneath it — a vnode delete/rename event fires on the item that was actually
deleted or renamed, not on unrelated descendants that still exist unchanged
one level down. The fix adds one additional `FolderWatcher` per root folder,
always live regardless of navigation depth, watching each root's own path
for deletion/rename. When one fires, `ContentView` re-verifies the folder is
actually gone (filtering out harmless events like a file dropped directly
into the root), then removes it from `FolderPersistence` and `rootFolders`,
and — if the user was browsing anywhere inside it — clears `currentRoot`/
`currentFolder` to fall back to the root list, which in turn stops the
leaf-level watcher via the existing `currentFolder` change handler.
`pruneDeadRootFolders()` (an existence re-check run every time the root list
is rebuilt) was kept as a defensive fallback for cases the watcher can't
cover, like a folder deleted while FolderDrop wasn't running at all.

**Back button hover/click mismatch.** Root cause: a `Button`'s own tap
gesture is built from its label's `contentShape` at construction time — a
`contentShape` applied afterward, outside the label (as an earlier attempt
had done, to sit next to `.onHover`), is invisible to that internal gesture,
even though a trailing `.onHover` at that same outer position *does* pick it
up. That mismatch — click bound to the label's original small shape, hover
bound to the outer enlarged one — is what let the hover highlight extend
beyond where clicks actually registered. The fix declares both `contentShape`
and `.onHover` on the exact same view node, inside the label, so both read
the identical shape.

**Duplicate-folder feedback.** `NSSound.beep()` was added to the existing
duplicate-folder guard clause in `selectFolder()` — a one-line addition to a
check that previously did nothing.

### Files Changed

`ContentView.swift`

### Outcome

A root folder deleted outside FolderDrop — whether the user is sitting at
the root list or browsing several levels beneath it — is detected and
removed automatically, with navigation falling back safely to the root list.
The Back button's hover and click regions are now identical. Attempting to
re-add an existing root folder produces an audible beep instead of silently
doing nothing.

---

## Debug Instrumentation Removal

### Problem

Two closed investigations — Quick Look's focus/responder-chain behavior and
`NSOpenPanel`'s presentation from a `MenuBarExtra` — had left behind
temporary, `#if DEBUG`-gated tracing code (`FocusDebugLog`, `FocusDebugObserver`,
and dozens of call sites) that was explicitly marked in its own header
comment for deletion once each investigation concluded. Both had: Quick Look
focus restoration was fixed and verified reliable, and the `NSOpenPanel`
investigation's findings were documented in its commit message with the one
real fix (`NSApp.activate()`) already kept in production code.

### Solution

Deleted `Services/FocusDebugLog.swift` entirely, along with every
`// DEBUG-INSTRUMENTATION`-tagged block and `FocusDebugLog`/
`FocusDebugObserver` call site across `FolderDropApp.swift`, `ContentView.swift`,
and `QuickLookService.swift`. The one genuine behavioral fix each
investigation produced — `NSApp.activate()` before presenting `NSOpenPanel`,
and the real `NSWindow.didResignKeyNotification` observer driving Quick
Look's `onClose` — was left completely untouched.

### Files Changed

`Services/FocusDebugLog.swift` (deleted), `FolderDropApp.swift`,
`ContentView.swift`, `Services/QuickLookService.swift`

### Outcome

No behavior change in either Debug or Release builds — verified by building
both configurations. The codebase no longer carries tracing code for
questions that have already been answered.

---

## Code Documentation Pass

### Problem

Ahead of open-sourcing FolderDrop, most of the codebase's "why" reasoning
lived only in file-header comments — which Xcode's Quick Help, jump bar, and
any generated documentation never surface, since they sit above the
`import` statements rather than directly on the types/methods themselves.

### Solution

Added `///` documentation comments directly on types and previously
under-documented methods across the codebase — models, services, non-obvious
view components, and `ContentView`'s navigation/security-scope methods —
without touching existing comments, renaming anything, or altering any
production logic.

### Files Changed

Comment-only additions across `ContentView.swift`, `FolderDropApp.swift`,
every file in `Models/` and `Services/`, and most files in `Views/`.

### Outcome

Verified as a pure documentation change: every diff was an insertion with no
lines removed or modified, and both Debug and Release builds succeeded
unchanged.

---

## Open-Source Documentation Overhaul

### Problem

FolderDrop's README and docs had grown organically alongside the code (see
every phase above) but had never been written *for* an outside reader —
there was no CONTRIBUTING guide, no CHANGELOG, no issue/PR templates, and
the README still read like a personal learning-project log rather than a
project someone could land on cold and get productive with.

### Solution

**README rewrite.** Restructured around GitHub open-source conventions: a
one-sentence pitch, a hero-GIF placeholder with explicit notes on what it
should show, an implemented-only feature checklist, labeled screenshot
placeholders, Installation/Building/Keyboard Shortcuts/Project Structure
sections, and a condensed Roadmap — with the heavier technical material moved
into `docs/` rather than duplicated inline.

**New `docs/` structure.** Added `docs/architecture.md` (the *why* behind
MenuBarExtra, folder hierarchy, FolderWatcher, selection, Quick Look, focus
restoration, persistence, and settings — deliberately not a restatement of
the code), `docs/roadmap.md` (RC1 Polish / Version 1.1 / Version 1.2 /
Long-Term Ideas / Completed Features / Known Limitations), and
`docs/release-process.md` (version bump through signing, notarization, and
GitHub Release — with explicit placeholders where the process isn't
exercised yet). `docs/IMPLEMENTATION_HISTORY.md` was replaced by this file,
restructured into the Problem/Solution/Files Changed/Outcome format, with
every existing phase's content preserved rather than summarized away.

**Contributor infrastructure.** Expanded `CONTRIBUTING.md` with explicit
Build Instructions, a Coding Style section, Commit Message Guidelines
(documented against this project's actual git history rather than an
invented convention), a Pull Request Checklist, and an Issue Reporting
section. Added `CHANGELOG.md` in Keep a Changelog format, and
`.github/ISSUE_TEMPLATE/bug_report.md` / `feature_request.md` /
`PULL_REQUEST_TEMPLATE.md`, each cross-linking back to the roadmap and
implementation history so duplicate or already-rejected proposals surface
early. Added an MIT `LICENSE` file, which the app's own About page already
claimed but the repository didn't yet contain.

**Repository hygiene pass.** A first-time-visitor review caught several
concrete issues: a placeholder `<your-org>` GitHub path left in clone
commands and changelog links (replaced with the real repository), README/
CONTRIBUTING build requirements that still said "macOS 13 / Xcode 15" when
the project's actual deployment target is macOS 26 (per `project.pbxproj`),
a broken internal cross-reference in the implementation history pointing at
the wrong phase, an inconsistent heading-capitalization style in
`architecture.md`, a missing Table of Contents in the now much longer
README, and a personal Xcode scheme-state file
(`xcuserdata/.../xcschememanagement.plist`) that had been committed before
`.gitignore`'s `xcuserdata/` rule existed — untracked via `git rm --cached`
without deleting it locally.

### Files Changed

`README.md`, `CONTRIBUTING.md`, `CHANGELOG.md` (new), `LICENSE` (new),
`docs/architecture.md` (new), `docs/implementation-history.md` (replaces
`docs/IMPLEMENTATION_HISTORY.md`), `docs/roadmap.md` (new),
`docs/release-process.md` (new), `.github/ISSUE_TEMPLATE/bug_report.md` and
`feature_request.md` (new), `.github/PULL_REQUEST_TEMPLATE.md` (new);
`FolderDrop.xcodeproj/xcuserdata/.../xcschememanagement.plist` removed from
tracking (not deleted from disk).

### Outcome

A repository that reads as a maintained open-source project rather than a
personal changelog: a concise, navigable README backed by detailed `docs/`,
a documented contribution process, and the standard GitHub scaffolding
(license, changelog, issue/PR templates) a new contributor expects to find.

---

## Pre-Release Security & Privacy Audit

### Problem

Before making the repository public and eventually distributing built
binaries, FolderDrop needed a critical, assume-nothing review — not just
"does the code work," but whether anything in the codebase or its git
history could leak personal information, over-request sandbox permissions,
silently lose user data, or leave debug/temporary artifacts behind.

### Solution

**Full-repository audit.** Reviewed every Swift file, the generated sandbox
entitlements from an actual signed build (not just the source-level
`ENABLE_APP_SANDBOX` setting), and the *entire* git history — not just the
working tree — for secrets, credentials, analytics/telemetry code, personal
information, and leftover debug instrumentation. Confirmed: zero networking
code anywhere (independently corroborated by the generated entitlements
containing no network entitlement at all, meaning the sandbox itself would
block it even if code tried), zero analytics/telemetry/crash-reporting,
zero third-party dependencies, and no secrets or credentials in current
files or historical commits. The two genuine personal-information findings
— the developer's personal email address in git commit-author metadata, and
a local macOS username baked into one historically-tracked (by then already
untracked-going-forward) Xcode file — were judgment calls left to the
maintainer rather than silently rewritten, since purging them requires a git
history rewrite.

**Startup cleanup of orphaned drag-and-drop staging files.** The audit
identified that `FileDragModifier`'s staged temp copies (cleaned up via a
delayed `DispatchQueue.main.asyncAfter`) would be orphaned forever if
FolderDrop quit, crashed, or macOS restarted before that timer fired. Fixed
by extracting the staging root path out of `FileDragModifier` into a new
`DragStagingArea` service — the one place both drag staging and cleanup
agree on the location — and adding `DragStagingArea.removeOrphanedFiles()`,
called once from `FolderDropApp.init()` before any scene is built. Each
leftover entry is removed independently via `try?`, so one failure doesn't
stop the rest from being cleaned up, and a missing staging directory is
silently treated as nothing to do. No polling, timers, or retry loops were
added — the existing per-drag delayed cleanup is unchanged.

**Bookmark validation correction.** The audit's most significant functional
finding: both `FolderPersistence.restore()` and
`ContentView.rootFolderExists(_:)` treated a failed
`startAccessingSecurityScopedResource()` call as proof a root folder had
been deleted. That conflated two different things — a folder that's
genuinely gone typically still lets the security scope open fine (it's the
subsequent `fileExists` check that correctly fails), whereas *starting* the
scope itself can fail for reasons that have nothing to do with deletion: an
external drive or network share not yet mounted, or a transient sandbox
hiccup — especially plausible now that Launch at Login can start FolderDrop
before such a volume remounts. Fixed by narrowing "delete this bookmark" down
to exactly the case with real evidence (a successfully-opened scope followed
by a confirmed-absent `fileExists`); every other outcome — including a
resolvable bookmark whose scope merely fails to open — now preserves the
bookmark and keeps showing the folder, rather than silently and permanently
forgetting it. User-initiated removal (`removeRootFolder`) was left
untouched, since that's explicit user intent, not an inference.

**Bundle identifier change.** The audit flagged `shreyankpatil.FolderDrop`
as tying the app's permanent identity to the developer's personal name
rather than a project-owned identifier, and noted this was the right time
to change it — before any public or notarized release — since changing it
later would break existing users' `UserDefaults` and login-item
registration. Changed to `com.folderdrop.app` in both Debug and Release
build configurations.

### Files Changed

`FolderDrop/Services/DragStagingArea.swift` (new), `FolderDrop/Views/FileRowView.swift`,
`FolderDrop/FolderDropApp.swift`, `FolderDrop/Services/FolderPersistence.swift`,
`FolderDrop/ContentView.swift`, `FolderDrop.xcodeproj/project.pbxproj`.

### Outcome

No critical or actively exploitable issues were found — the sandbox
entitlements were already minimal and correctly scoped (read-only, no
network), and the codebase had no debug instrumentation, secrets, or
third-party dependencies to begin with. The audit's concrete yield was three
targeted fixes: orphaned drag-staging files are now cleaned up on every
launch, a root folder on removable or network media is no longer permanently
forgotten after a single transient access failure, and the app's identity is
no longer tied to the developer's personal name. The full findings —
including items intentionally left for the maintainer to decide, like the
git-history residue — are not duplicated here; this phase records what
changed as a result, not the complete audit report itself.

---

## About Page Redesign & Polish

### Problem

The About settings page had reserved space for project links since before
the repository had a public URL to put in them, and its content (a combined
"Project"/"Open Source"/"Created by" layout) didn't reflect the fact that
FolderDrop was now genuinely open source with a real repository, issue
tracker, license file, and documented privacy posture.

### Solution

**Initial redesign.** Restructured into clearly labeled sections: Links,
License, Privacy, Maintenance (unchanged), and Credits. GitHub Repository
and Report an Issue became live `Link` views pointing at this repository's
actual URL and issue-template chooser — `.buttonStyle(.plain)` strips
SwiftUI's default blue/underlined hyperlink look so they read as native
System Settings rows rather than web links. Website had no real destination
yet, so it became a disabled "Coming Soon" row rather than a hardcoded
placeholder domain that doesn't exist. Discussions was checked against the
repository's actual GitHub settings (via the API, confirming
`has_discussions: false`) and left out entirely rather than added as a
placeholder, since there's nothing to link even provisionally. License and
Privacy became their own sections with the plain, factual statements
requested; Credits carried over "Created by Shreyank Patil" and added
"Built using SwiftUI and AppKit."

**Polish pass.** A follow-up pass made three small corrections: reworded the
header description ("frequently used folders" instead of "favorite
folders"), removed the Donate row entirely rather than leaving another
placeholder (a future support/donate platform will be added once one
exists, the same way Website already works), and added one line to Credits
— "Development assisted by ChatGPT and Claude." — worded as an
acknowledgment of assistance, not a claim of authorship.

### Files Changed

`FolderDrop/Views/AboutSettingsView.swift`

### Outcome

Verified in a live, launched build (screenshots and the accessibility tree,
not just reading the code) that the app icon, version, description, all
Links rows, License, Privacy, Maintenance, and Credits render correctly in
the existing native grouped-Form style. No other settings page or
application behavior was touched.
