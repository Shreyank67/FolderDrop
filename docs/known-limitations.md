# Known Limitations

This document tracks known bugs in FolderDrop's existing behavior ahead of
v1.0, with more detail than the README's
[Known Limitations](../README.md#known-limitations) summary. It exists so
contributors and users can see current behavior, expected behavior, and
status without digging through issues or source.

For features that haven't been built yet (search, folder favorites, a real
updater, etc.), see [docs/roadmap.md](roadmap.md#known-limitations) instead —
this document is only about things that are implemented but don't behave
correctly.

---

## Quick Look

**Description:** In some fullscreen applications (for example, Figma), Quick
Look may occasionally lose keyboard focus when closing with the Space key.

**Current behavior:** Closing the Quick Look panel with Space can leave
keyboard focus in a state where the previously fullscreen app doesn't
immediately reclaim it, in certain fullscreen-Space configurations.

**Expected behavior:** Closing Quick Look should always return keyboard focus
to whatever had it before Quick Look opened, regardless of whether that app is
in a fullscreen Space.

**Workaround:** Click into the target app's window if focus doesn't return on
its own. This does not affect normal (non-fullscreen) desktop usage.

**Status:** Deferred (post v1.0)

**Notes:** Specific to fullscreen-Space interaction between `QLPreviewPanel`
and third-party apps; not observed in normal windowed usage.

---

## Drag & Drop (DaVinci Resolve)

**Description:** Some applications import the temporary staged file path
FolderDrop creates for a drag, instead of the original file's location.

**Current behavior:** FolderDrop stages a temporary copy of a dragged file
outside its sandbox container so destination apps can read it during a drag
(see [docs/architecture.md](architecture.md#drag--drop)). DaVinci Resolve
imports this staged path rather than the original file's path. Once
FolderDrop cleans up the staged copy (a configurable delay after the drag,
30/60/120s), Resolve is left referencing a file that no longer exists.

**Expected behavior:** The destination application should reference the
original file's location, matching how dragging the same file from Finder
behaves.

**Workaround:** None currently. Increasing the drag cleanup delay in
Settings > General does not fix the underlying reference, it only postpones
when it breaks.

**Status:** Under Investigation

**Notes:** Root-cause investigation is ongoing. Confirmed so far: FolderDrop's
`NSItemProvider` registrations (`registerObject`, `registerFileRepresentation`)
both currently point at the staged copy rather than the original file.
Chrome's (and, by extension, other Chromium/Electron apps') drag-receiving
code has been confirmed, by reading its current source, to read the
`public.file-url` pasteboard type directly rather than negotiating a file
promise. DaVinci Resolve is closed-source, so its exact drag-reading
mechanism cannot be confirmed. An experiment that pointed the shared
`registerObject` representation at the original file fixed Resolve but broke
Finder, Chrome, Figma, and multi-file drag — indicating the fix isn't as
simple as swapping which URL is advertised. No fix is scheduled until this is
better understood.

---

## Folder Drag & Drop

**Description:** Dragging folders out of FolderDrop is not currently
supported.

**Current behavior:** Only file rows support drag-and-drop. Folder rows have
no drag source attached.

**Expected behavior:** Dragging a folder should behave like dragging a file —
handing the destination app the folder (or a staged copy of it, consistent
with however file dragging is ultimately resolved).

**Workaround:** None. Navigate into the folder and drag its contents
individually, or use Finder for folder-level drags.

**Status:** Planned

**Notes:** No implementation work has started.

---

## Sorting

**Description:** Folder contents are only ever displayed alphabetically.

**Current behavior:** No sort order other than alphabetical (by name) is
available.

**Expected behavior:** Additional sort options — date modified, size, kind,
etc. — with a way to switch between them.

**Workaround:** None.

**Status:** Planned

**Notes:** No implementation work has started.

---

## Settings Window / Fullscreen Spaces

**Description:** The Settings window opens in its own desktop/Space rather
than the Space containing the active fullscreen app.

**Current behavior:** Opening Settings while another app is fullscreen
switches to a separate Space for the Settings window instead of appearing
alongside the fullscreen app.

**Expected behavior:** Settings should open in the currently active Space,
consistent with how many native macOS panels behave.

**Workaround:** Exit fullscreen before opening Settings, or manually switch
back to the Space containing the fullscreen app afterward.

**Status:** Deferred (SwiftUI/AppKit limitation)

**Notes:** This stems from how SwiftUI's `Settings` scene and AppKit's
fullscreen Space management interact; not something FolderDrop's own code
directly controls.

---

## Back Button Hit-Testing

**Description:** Minor inconsistency in the Back button's hit-testing near
the top edge of its clickable area.

**Current behavior:** A click very close to the top edge of the Back
button's hit area can occasionally fail to register.

**Expected behavior:** The entire visible/hover-highlighted area of the Back
button should register a click consistently, with no edge inconsistency.

**Workaround:** Click closer to the center of the button.

**Status:** Planned

**Notes:** A related hover/click hit-testing mismatch for this same button
was previously fixed (see
[implementation-history.md](implementation-history.md#root-folder-lifecycle--rc1-stability))
by aligning `contentShape` and `.onHover` on the same view node. This is a
narrower, residual edge case in the same area, not a regression of that fix.
