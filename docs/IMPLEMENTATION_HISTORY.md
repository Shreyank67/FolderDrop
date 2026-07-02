# FolderDrop — Implementation History

This document describes how FolderDrop was built, feature by feature, in the
order the work actually happened. It's written for whoever picks this project
up next — the goal is to explain *why* the code looks the way it does, not
just what it does. The codebase itself is the source of truth for current
behavior; this document is the source of truth for the reasoning behind it.

FolderDrop is a native macOS `MenuBarExtra` (`.window` style) app, built with
SwiftUI plus targeted AppKit bridging where SwiftUI has no native equivalent.
It is sandboxed (`ENABLE_APP_SANDBOX = YES`), which shaped several of the
decisions below.

---

## Folder Navigation

### Goal

Let the user pick one or more folders once, browse into their contents from
the menu bar, and have that access persist across app restarts — without
re-prompting for permission every time.

### Why it was implemented

This is the foundation of the app: everything else (drag, Quick Look,
selection) operates on the entries this feature produces.

### Phases

**Root folder persistence.** `FolderPersistence` (Services/) wraps
`UserDefaults` and macOS's security-scoped bookmark API. Adding a folder
(`NSOpenPanel`) stores a bookmark (`URL.bookmarkData(options: .withSecurityScope, ...)`);
restoring at launch resolves each stored bookmark, drops any that no longer
resolve or whose target no longer exists, and transparently refreshes stale
bookmarks. Multiple root folders were supported from early on — `rootFolders`
is an array, not a single URL.

**Browsing and back navigation.** `ContentView` owns `currentRoot` (which root
bookmark grants access to the current browsing session) and `currentFolder`
(where the user currently is, which may be several levels below `currentRoot`).
Reading a folder's contents (`FolderContentsLoader`) only requires
`currentRoot.startAccessingSecurityScopedResource()` — child paths are read
directly via `FileManager`, without needing their own bookmarks. This became
a load-bearing assumption for later features (drag, Quick Look): **any
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
either the root folder count or the current folder's name + a "›"-joined
breadcrumb of its parent path. The "Back" button was iterated on several
times during UI Polish (see below) — it started as a bordered push button and
ended as a plain, hover-tinted, borderless affordance closer to Finder.

### Architectural decisions

- Security-scoped access is always bracketed tightly around the operation
  that needs it (`start...` / `defer { stop... }`), never held open
  persistently. This pattern was established here and reused by every later
  feature that touches the filesystem.
- Folder navigation state (`currentRoot`, `currentFolder`, `folderEntries`)
  lives in `ContentView`; child views are given data and callbacks, not
  direct access to this state.

### Final behavior

Users can add any number of root folders, browse into subfolders, go back up
(one level, or all the way to the root list), and the whole session survives
an app relaunch with folders restored automatically.

### Notes on native macOS behavior

Security-scoped bookmarks can go stale (e.g., after the OS updates or the
underlying volume changes) without becoming fully invalid — `restore()`
detects `bookmarkDataIsStale` and re-writes a fresh bookmark transparently, so
the user never has to re-grant access for a folder that still exists.

---

## Multi-File Drag & Drop

### Goal

Let users drag a file straight from FolderDrop into Finder, Mail, Chrome,
Slack, VS Code, or ChatGPT — matching how dragging works from Finder — and
later, drag a whole multi-selection at once.

### Why it was implemented

FolderDrop's whole purpose is to get files into other apps faster than
opening Finder first; drag-and-drop is the primary way users do that.

### Phases

**Phase 1 — Single-file drag via `.onDrag`.** `FileRowView` attaches SwiftUI's
`.onDrag(_:preview:)` to file rows (never folders). The naive first attempt —
`NSItemProvider(contentsOf: url)` — turned out to be wrong: it registers a
*lazy* read that only fires when a consumer asks for the data, by which point
our security scope (opened only around the synchronous call) had already
closed. The fix was to copy the file to a plain, unscoped temp location
*before* handing anything to the destination:
`registerFileRepresentation`/`registerObject(NSURL)` both point at a
synchronously-staged copy (`stageCopy(of:root:)`), made under a briefly-opened
root scope. The destination app never touches our sandbox at all — it reads a
completely ordinary file.

**Fixing cross-app compatibility.** The staged file was initially registered
only via `registerFileRepresentation` (the coordinated/promise protocol AppKit
apps like Finder and Mail negotiate). Chromium/Electron apps (Chrome, Slack,
VS Code, ChatGPT) don't negotiate that protocol — they read a `public.file-url`
pasteboard entry directly and expect it to already resolve. Adding
`registerObject(stagedURL as NSURL, visibility: .all)` alongside the existing
representation fixed this without touching the AppKit-facing path.

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
`NSView.beginDraggingSession(with:event:source:)`. A small `NSViewRepresentable`
(`MultiFileDragSourceView` / `DragSourceNSView`, implementing `NSDraggingSource`)
overlays a row *only* when it's part of an existing 2+ selection; every other
case (single file, or dragging a file that isn't currently selected — which
first collapses the selection to just that file, matching Finder) still goes
through the original, untouched `.onDrag` path.

The multi-item bridge tracks `mouseDown` → `mouseDragged`/`mouseUp` using the
standard AppKit drag-vs-click distance-threshold idiom. Past the threshold it
calls `beginDraggingSession` with one `NSDraggingItem` per selected file, each
staged via the *same* `stageCopy`/`scheduleCleanup` functions as the
single-file path (no duplicated staging logic). Below the threshold — i.e. a
plain click, not a drag — it replicates the exact plain/⌘/⇧ click decision
`FileListView`'s own tap gesture makes, because overriding `mouseDown` means
SwiftUI's gesture never sees that event otherwise.

One correction made along the way: `NSDraggingItem(pasteboardWriter:)` needs a
type conforming to `NSPasteboardWriting`, and `NSItemProvider` does **not**
conform to that on macOS (confirmed by the compiler, not assumed) — so the
multi-item path hands `NSDraggingItem` the staged file's plain `NSURL`
instead, which is the same `public.file-url` representation the single-file
path already registers for Chromium/Electron.

### Architectural decisions

- Two drag mechanisms coexist deliberately: `.onDrag` (SwiftUI-native, used
  for the overwhelmingly common single-file case, functionally unchanged
  since Phase 1) and the AppKit bridge (used only for genuine multi-item
  drags). This was a conscious choice over unifying everything under the
  AppKit bridge, to avoid risking regressions in the already-verified
  single-file path for a capability only needed in the multi-select case.
- All staging/cleanup logic lives in one place (`FileDragModifier`'s static
  functions, marked `fileprivate` so the AppKit bridge in the same file can
  reuse them) rather than being duplicated per drag mechanism.

### Final behavior

Dragging a single file (or a file outside the current selection, which
collapses selection to it first) works exactly as a native single-file drag.
Dragging any member of an existing multi-selection carries the entire
selection as one native multi-item drag session, with AppKit's automatic
fan/stack preview and item-count badge — no custom preview view was needed
for that.

### Notes on native macOS behavior

- Multi-item drag previews (the fanned stack + count badge) are entirely
  native AppKit behavior once you supply more than one `NSDraggingItem` — no
  custom rendering was written for it.
- `List`/`NSTableView`'s own automatic multi-item drag bundling (tied to
  `List(selection:)`) was considered and rejected, because FolderDrop's
  click/⌘-click/⇧-click semantics are handled entirely by custom gesture code,
  not `List`'s native selection — adopting `List(selection:)` risked
  interfering with that already-hardened click model.

---

## Quick Look

### Goal

Let the user preview a file (or the whole current selection) without opening
it, matching Finder's Space-bar Quick Look.

### Why it was implemented

Requested as a natural companion to selection/keyboard navigation — "inspect,
don't necessarily open."

### Phases

**Phase 1 — Single-file preview.** `QuickLookService` (Services/) wraps
`QLPreviewPanel`, conforming to `QLPreviewPanelDataSource`/`Delegate`.
Investigated up front: macOS has no SwiftUI-native Quick Look on macOS (unlike
iOS's `QLPreviewController`), so `QLPreviewPanel` is the only native option.
The panel is a singleton driven directly (no `NSResponder`
`acceptsPreviewPanelControl` dance, since FolderDrop is the sole invoker of
Quick Look for its own content, not integrating with a system-wide
responder-chain search). Keyboard handling required a similar investigation:
SwiftUI gives no supported hook to insert a custom `NSResponder` for a global
Space-bar shortcut inside a `MenuBarExtra`, so a local
`NSEvent.addLocalMonitorForEvents(matching: .keyDown)` monitor was used
instead, intercepting only the keys FolderDrop cares about and passing
everything else through untouched.

Sandboxing detail: `quicklookd` (a separate system process) reads the file
directly, so the security scope must stay open for the *entire time the panel
is displaying it* — not just the instant it's requested, the same lesson
learned in Drag & Drop.

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
same root bookmark, so the existing single open/close bracket already covered
any number of them.

**Settings integration.** An "Enable Quick Look" toggle (see Settings &
Preferences) gates the Space handler; when off, Space is simply a no-op for
files (falls through to default handling) while Enter-to-open and context
menus are unaffected, since they never depended on `quickLookService`.

### Architectural decisions

- `QuickLookService` never touches `SelectionState` or vice versa — it
  receives already-resolved `[FolderEntry]` + an active entry from
  `ContentView`, keeping the two concerns decoupled.
- `isPanelOpen` (and later `previewItems`) is the single source of truth,
  deliberately not derived from AppKit's own live window state, after the
  first toggle bug proved that indirection unreliable.

### Final behavior

Space previews the active file (or the whole selection, arranged in
on-screen order, if more than one file is selected), with the active file
shown first. Space again closes it immediately. Escape closes it natively
(unhandled by FolderDrop's own monitor when the panel is open). Closing Quick
Look — by any means — never changes the current selection.

### Notes on native macOS behavior

- `QLPreviewPanel` closes itself on Escape natively; FolderDrop's own Escape
  handling explicitly defers to it (`guard !quickLookService.isShowing else { return event }`)
  rather than trying to duplicate that behavior.
- Multi-item Left/Right cycling inside the panel is entirely native — a
  direct consequence of reporting `numberOfPreviewItems > 1`.

---

## Keyboard Navigation

### Goal

Let the whole app — folder browsing, file selection, opening, previewing,
going back — be operable from the keyboard, matching Finder's list-view
conventions.

### Why it was implemented

A menu bar utility that requires mouse-only interaction is slower than just
using Finder; keyboard-first interaction is a core differentiator.

### Phases

**Enter to open.** Added to the same `NSEvent` local monitor Quick Look
already used (see Quick Look phase 1) — reusing one monitor was a deliberate
choice over adding a second, to keep all keyboard handling centralized and
avoid multiple monitors racing over the same events. Enter opens files
(`openFile`) and navigates into folders (`navigateIntoFolder`), branching on
`entry.isDirectory`.

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
select immediately), with Enter/double-purpose keyboard shortcuts covering
"open."

**⌘A / ⌘⇧A.** Added to the same monitor. Select All reuses `SelectionState`'s
existing `toggle(_:)` in a loop from a cleared state (rather than adding a
dedicated "select all" method to `SelectionState`), so `activeEntry`/
`selectionAnchor` end up on the last file and keyboard navigation continues
normally afterward. Deselect All (⌘⇧A) and clicking empty list whitespace
both clear `SelectionState` and close Quick Look if it's open.

### Architectural decisions

- Exactly one `NSEvent` keyDown monitor exists for the whole app, made
  process-global (`static var`, not `@State`) after the leaked-monitor
  regression described under Quick Look. Every keyboard shortcut in the app
  — arrows, Enter, Space, Escape, ⌘A, ⌘⇧A — is a `case` in that same
  monitor's `switch`.
- Hover, selection, and keyboard navigation are three separate pieces of
  state (`hoveredEntry`, `SelectionState`, the monitor's captured closures)
  that only interact at one narrow seam (seeding Up/Down's starting point
  from hover) — deliberately not merged into one model.

### Final behavior

Arrow keys move/extend selection (Shift extends); Enter opens files or
navigates into folders (auto-selecting the new folder's first entry so
navigation can continue immediately); Space toggles Quick Look; Escape goes
back (deferring to an open Quick Look panel first); ⌘A/⌘⇧A select/deselect
everything in the current folder. All of it works identically whether
browsing the root folder list or a subfolder.

### Notes on native macOS behavior

`NSEvent.addLocalMonitorForEvents` monitors are dispatched in registration
order, and a monitor returning `nil` suppresses *later-registered* monitors
from seeing that event too — this is what caused the leaked-monitor Quick
Look regression, and is worth remembering before ever adding a second local
monitor anywhere in this app.

---

## Multi-Selection

### Goal

Finder-style multi-selection: single click, ⌘-click (toggle), ⇧-click/⇧-arrow
(range), all interoperating the way Finder actually behaves — including the
non-obvious cases (a ⌘-selected item surviving a later ⇧-range operation, a
⇧-range shrinking cleanly without leaving stale items behind).

### Why it was implemented

Required for multi-file drag and multi-item Quick Look; also a baseline
expectation for any Finder-like file browser.

### Phases

**Interaction-model prerequisite.** Before multi-selection could be built,
the click model had to stop conflating "select" and "open." Several turns of
back-and-forth iteration led to the final rule: a single, uncounted tap per
row — folders navigate instantly, files select instantly — with no
double-click anywhere (removed specifically to eliminate the perceptible
delay SwiftUI's `.onTapGesture(count:)` disambiguation otherwise imposes on
every click).

**`SelectionState` (Phase 1).** A plain `struct` (Models/), not a class, not
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

**Wiring multi-file drag and multi-item Quick Look.** Both features (see
their own sections) consume `selectionState.selectedEntries`/`activeEntry`
directly — no separate selection model was introduced for either.

### Architectural decisions

- `SelectionState` never touches drag, Quick Look, or keyboard-monitor code
  directly; `ContentView` is the only thing that calls its mutating methods,
  in response to callbacks from `FileListView`/`FileRowView` or the keyboard
  monitor.
- The committed/transient split exists specifically because a single `Set`
  cannot correctly express "persistent selections independent of the current
  live Shift range" — this was arrived at only after the naive single-`Set`
  and single-`Set`-plus-`formUnion` approaches were each shown to be wrong
  for a specific, reproducible scenario.

### Final behavior

Plain click selects only that item. ⌘-click toggles one item without
disturbing the rest of the selection. ⇧-click/⇧-arrow selects/extends/shrinks
a range from a fixed anchor, live, without touching independently ⌘-selected
items outside that range. ⌘A selects every file in the current folder;
⌘⇧A (or clicking empty list whitespace) clears the selection.

### Notes on native macOS behavior

None specific to this feature beyond what's covered under Keyboard
Navigation and Drag & Drop, which both consume `SelectionState`'s output.

---

## Settings & Preferences

### Goal

A native Settings window (not a custom in-panel screen) for the preferences
that had accumulated implicit hardcoded behavior (Quick Look always on, drag
cleanup always 60 seconds, no folder-restore option, no Launch at Login).

### Why it was implemented

Once there was more than one piece of tunable behavior, hardcoding it all
stopped being reasonable, and a menu-bar utility with zero settings surface
is unusual for macOS users' expectations.

### Phases

**Phase B.1 — Infrastructure only.** A `Settings { SettingsView() }` scene was
added alongside the existing `MenuBarExtra` scene in `FolderDropApp`. SwiftUI's
`Settings` scene is a singleton window by construction — calling
`openSettings()` (via `@Environment(\.openSettings)`, wired to the header's
gear icon) while it's already open just brings the existing window to front,
with no custom "is it already open" tracking needed. `SettingsView` started
as a single "General" tab (`TabView`) with placeholder content only — no
real preferences yet.

**Phase B.2 — General preferences (UI only).** The placeholder was replaced
with a native `Form` / `.formStyle(.grouped)` layout (matching System
Settings' grouped-box look): a Behavior section (Quick Look toggle, restore-
last-folder toggle), a Drag & Drop section (cleanup-delay picker: 30/60/120s),
and a read-only Keyboard Shortcuts list. This phase deliberately built UI only
— local `@State`, not yet backed by persistence.

**Phase B.3 — Wiring to the application.** A single small file,
`SettingsKeys.swift`, defines the `UserDefaults` key strings shared between
`SettingsView` and the rest of the app — the only thing that needs to be
shared is the key string; the value itself lives in `UserDefaults`, observed
via `@AppStorage` from wherever it's needed (both `SettingsView` and
`ContentView` use `@AppStorage` with the same keys, rather than a custom
settings-object layer). Behavior wired up:
  - **Enable Quick Look**: gates the Space handler in `ContentView`'s keyboard
    monitor; when off, Space is a no-op for files.
  - **Restore last opened folder**: persists the plain folder path (not a
    bookmark — child paths only need the *root's* bookmark, already
    established under Folder Navigation) whenever `navigateIntoFolder`/
    `goBack` run, gated by the toggle. At launch, after root folders are
    restored, the saved path is matched by prefix against the restored roots
    and existence-checked under a briefly-reopened root scope before being
    applied — falling back silently to the root list otherwise.
  - **Cleanup delay**: `FileRowView`'s previously-hardcoded 60-second delay
    now reads the same `UserDefaults` key the picker writes (falling back to
    60 if unset, so existing users see the old behavior automatically).

**Contextual help.** A small `SettingLabel` helper (title + a
`.help(...)`-carrying `info.circle` icon) was added and reused for every
setting, rather than duplicating the icon/tooltip wiring per control.
Investigated and confirmed before any attempt to customize it: SwiftUI's
`.help()` has no delay/timing parameter, and the native AppKit tooltip system
it's built on doesn't expose one either — tooltip delay is a system-wide,
undocumented setting (`NSInitialToolTipDelay`), not a per-app or per-view
customization point, so no code was written to try to change it.

**Phase B4.1 — Launch at Login.** Isolated in its own
`LaunchAtLoginService` (Services/), wrapping `SMAppService.mainApp`
(the modern ServiceManagement API — no deprecated login-item APIs used).
Deliberately **not** stored in `UserDefaults`: `SMAppService`'s own `.status`
is the actual source of truth (and can change outside the app, e.g. via
System Settings › Login Items), so `SettingsView` just mirrors it into one
`@State` bool, refreshed on `.onAppear`. The toggle uses a custom `Binding`
rather than a plain one plus `.onChange`: on a thrown
register/unregister error, the backing state is left untouched (so the
`Toggle` visually reverts on its own, no separate "undo" step) and the
error's `localizedDescription` drives a native `.alert(...)`.

**Phase B4.2 — Restore Defaults, Check for Updates, footer.** "Restore
Defaults…" resets the three `UserDefaults`-backed preferences (Quick Look,
restore-folder, cleanup delay) back to their defaults via a native
`.confirmationDialog` — explicitly **not** touching Launch at Login, since
that isn't one of the `UserDefaults` preferences and resetting it wasn't
requested. "Check for Updates…" is a placeholder `.alert` for a future real
updater. The footer shows the app name and version (read from
`CFBundleShortVersionString`) in secondary styling.

### Architectural decisions

- `SettingsKeys` is the only shared artifact between `SettingsView` and the
  rest of the app — no settings "manager" or view model was introduced.
  `@AppStorage` (backed by the same key) is what keeps every observer in
  sync; there is exactly one copy of each preference's value, in
  `UserDefaults` itself.
- Launch at Login is architecturally separate from the other three
  preferences on purpose: its source of truth is `SMAppService`, not
  `UserDefaults`, and the two were never allowed to blend (e.g. Restore
  Defaults explicitly excludes it).

### Final behavior

A native Settings window (⌘, or the header gear icon) with a General page:
Launch at Login, Enable Quick Look, Restore Last Opened Folder, drag cleanup
delay (30/60/120s), a read-only shortcuts reference, Restore Defaults (with
confirmation), and a Check for Updates placeholder. Every preference has an
`info.circle` tooltip explaining what it does.

### Notes on native macOS behavior

- `Settings` scenes are native singleton windows; repeated `openSettings()`
  calls just refocus the existing window.
- `SMAppService.mainApp.status` reflects system-level state that can change
  outside the app's control (user removes it via System Settings), which is
  why it's read fresh every time the Settings window opens rather than
  cached.

---

## UI Polish

### Goal

Bring FolderDrop's visual feel in line with Finder/native macOS conventions,
iteratively, across rows, header, controls, empty states, and overall layout
density.

### Why it was implemented

Functionality was built first; once the interaction model stabilized, the
visual presentation was refined in several focused passes.

### Phases

**Row & List Polish (Phase A.1).** Row height, padding, icon-to-text spacing,
and corner radius were tuned iteratively — including one explicit
"overcorrection and revert" (padding went to 13pt, was judged too tall for a
menu-bar utility, and was brought back down to 7pt while keeping every other
Phase A.1 change). Hover color went through two iterations: first a light
system-accent-color tint, then — per explicit direction — the neutral,
semantic `NSColor.unemphasizedSelectedContentBackgroundColor` (the same gray
AppKit itself uses for a selected-but-not-key-window row), paired with
`NSColor.selectedContentBackgroundColor` for actual selection. Row separators
were hidden (`.listRowSeparator(.hidden)`) so whitespace became the primary
separator, matching a request to make the list "feel cleaner."

**Header & Navigation (Phase A.2).** Breadcrumb/subtitle typography shrunk
and switched to `NSColor.secondaryLabelColor`; the Back button gained a
`chevron.left` SF Symbol via `Label`, staying a normal (not icon-only
bordered) button at this stage.

**Window & Layout Polish (Phase A.3).** Outer padding, window `minWidth`, and
list row insets were each adjusted twice — once outward ("more breathing
room"), then explicitly walked back inward ("the layout has become a little
too spacious… make the UI feel denser again") — landing at `minWidth: 304`,
15pt horizontal content padding, and 6pt list row insets.

**Header & Toolbar / Controls Polish (Phase A.4–A.5).** A borderless
`gearshape` Settings button was added beside the title (later wired to the
real Settings window in Settings & Preferences). The Back and Add Folder
buttons were converted to `Label`-based, `.buttonStyle(.borderless)` +
`.controlSize(.small)` controls (`folder.badge.plus` for Add Folder) for a
lighter, more Finder-like weight.

**Empty States & Transitions (Phase A.6).** A reusable `EmptyStateView`
(icon + title + subtitle) replaced the bare "no folders" button-only screen
and was added for browsing into a genuinely empty folder (previously just a
blank list). Small `.animation(...)`/`.transition(.opacity)` fades were added
between navigation states, keyed on existing state (`currentFolder`,
`rootFolders.isEmpty`) rather than introducing new state for the purpose.

**Column-alignment investigation and fix.** After several rounds of
per-element padding tweaks (a `FolderHeaderView.contentColumnInset` constant
applied to some header text and to the Back button, while `FileRowView`'s own
internal row padding used an unrelated raw literal that happened to match),
the header title, subtitle, breadcrumb, Back button, and file rows stopped
sharing one visual left edge. A full trace (documented at the time,
requested explicitly rather than another one-off padding guess) found the
root cause: **three independent mechanisms were each reproducing the "same"
offset by convention, not by a shared reference** — external padding on the
Back button, internal padding inside `FolderHeaderView`, and an unrelated
literal inside `FileRowView` that also had to double as the hover/selection
pill's own internal inset. Rather than introduce a new shared layout
constant (considered and explicitly rejected as over-engineering for this
codebase), the fix was simplification: every explicit
`.padding(.leading, contentColumnInset)` added during the prior passes was
removed, leaving `ContentView`'s single outer `.padding(.horizontal, 15)` as
the only alignment source everything shares. `FileRowView`'s own internal row
padding — which also defines the hover/selection pill's inset — was left
untouched throughout, since it serves a different purpose (the pill's own
breathing room) than window-level alignment.

### Architectural decisions

- Visual/spacing changes were kept strictly separate from behavior changes
  throughout — no UI Polish phase touched `SelectionState`, drag-and-drop,
  Quick Look, or keyboard handling logic.
- When column alignment broke, the fix was to *remove* scattered
  compensating padding rather than add a new abstraction — consistent with
  this project's general preference for the smallest correct fix over a new
  layer of indirection.

### Final behavior

A denser, Finder-adjacent layout: hidden row separators, neutral-gray hover
distinct from accent-colored selection, borderless/light-weight Back and Add
Folder controls, populated empty states instead of blank space, subtle fade
transitions between navigation states, and every text element (app title,
folder count, folder title, breadcrumb, Back, file rows) sharing one left
edge derived from a single padding value.

### Notes on native macOS behavior

- `NSTrackingArea`-based hover (`.onHover`) dispatch is independent of
  standard click hit-testing order — multiple overlapping views can each
  receive enter/exit events regardless of which is topmost for clicks, which
  is why the multi-file-drag `NSView` overlay (Drag & Drop) was judged safe
  for hover without needing to manually re-implement hover forwarding.
- `List`/`NSTableView` may carry margins not fully exposed by
  `contentMargins`/`listRowInsets` — flagged as a residual, only-verifiable-
  at-runtime uncertainty during the alignment investigation, distinct from
  the actual (fully identified, in-code) root cause that was fixed.

---

## Current Feature Set (v1.0)

- Multiple, persistent root folders (security-scoped bookmarks, auto-refreshed
  when stale, dropped when no longer valid)
- Folder browsing with back navigation and breadcrumbs
- Root folder context menu (Open, Reveal in Finder, Remove)
- Single-file drag-and-drop to Finder, Mail, Chrome, Slack, VS Code, ChatGPT
- Multi-file drag-and-drop (native AppKit multi-item drag session, automatic
  stacked preview + count badge)
- Native Quick Look (single file or full multi-selection, native Left/Right
  cycling, Space to toggle)
- Full keyboard navigation (arrows, Shift-extend, Enter, Space, Escape, ⌘A,
  ⌘⇧A)
- Finder-style multi-selection (plain/⌘/⇧-click, ⇧-arrow, independent of
  drag/Quick Look/keyboard state)
- Hover and selection visuals using native semantic AppKit colors
- Populated empty states (no folders added yet; folder is empty) with subtle
  navigation-state fade transitions
- Native Settings window (⌘, or header gear icon):
  - Launch at Login (via `SMAppService`)
  - Enable Quick Look toggle
  - Restore Last Opened Folder toggle
  - Configurable drag-cleanup delay (30/60/120s)
  - Read-only keyboard shortcuts reference
  - Restore Defaults (with confirmation)
  - Check for Updates (placeholder)
  - Contextual `info.circle` tooltips on every setting

---

## Known Limitations

- No search or filtering within a folder's contents
- No Finder Sync extension (badges/context menu integration inside Finder
  itself)
- No real update mechanism — "Check for Updates" is a placeholder alert, not
  a Sparkle (or equivalent) integration
- Keyboard shortcuts are fixed — not user-remappable
- No drag-and-drop *into* FolderDrop (only outbound drag is implemented)
- No folder reordering or favorites/pinning
- Root folder removal has no undo beyond re-adding the folder manually
- No multi-window support — one menu bar panel, one Settings window
- Not App Store-packaged or notarized as a distributable build (development/
  local-run only, as far as this history covers)

---

## Future Roadmap

### Near-term
- Wire "Check for Updates" to a real updater (Sparkle or equivalent)
- Search/filter within the current folder's contents
- Continued UI polish passes (the project has iterated on this multiple
  times already and treats it as an ongoing, incremental effort rather than
  a one-time pass)

### Medium-term
- Finder Sync extension for deeper Finder integration
- Better/richer previews beyond what Quick Look provides by default
- Custom/remappable keyboard shortcuts (would need to extend the single
  centralized `NSEvent` monitor's key-mapping rather than replace it)
- Performance work if folder sizes/entry counts grow significantly (current
  `FolderContentsLoader` and `SelectionState` were not built or tested
  against very large directories)

### Long-term
- App Store release (would require revisiting the sandbox/entitlement setup
  and the security-scoped bookmark strategy for App Store compliance)
- Drag-and-drop *into* FolderDrop (currently entirely outbound)
- Folder favorites/pinning and reordering
