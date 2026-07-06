# Roadmap

This document tracks what's done, what's actively planned, and longer-range
ideas that haven't been scheduled. For how each completed feature was
actually built, see [implementation-history.md](implementation-history.md).
For why the architecture looks the way it does, see
[architecture.md](architecture.md).

---

## Version 1.0

### Completed

Everything below is implemented and shipping today. See
[implementation-history.md](implementation-history.md) for how each one was
built.

- Multiple, persistent root folders (security-scoped bookmarks,
  auto-refreshed when stale, dropped automatically when no longer valid)
- Folder browsing with back navigation and breadcrumbs
- Root folder context menu (Open, Reveal in Finder, Remove)
- Live folder refresh — automatic reload on filesystem changes, no polling
- Automatic cleanup of root folders deleted outside FolderDrop, with safe
  fallback to the root list if the active root disappears mid-session
- Robust root-folder bookmark validation — a temporary access failure (an
  external drive or network share not yet mounted, or a transient sandbox
  hiccup) is no longer mistaken for the folder having been deleted
- Automatic cleanup of orphaned drag-and-drop staging files left behind by a
  previous run that quit, crashed, or didn't survive long enough for its own
  delayed cleanup to run
- Single-file drag-and-drop to Finder, Mail, Chrome, Slack, VS Code, ChatGPT
- Multi-file drag-and-drop (native AppKit multi-item drag session, automatic
  stacked preview and count badge)
- Native Quick Look (single file or full multi-selection, native Left/Right
  cycling, Space to toggle)
- Full keyboard navigation (arrows, Shift-extend, Enter, Space, Escape, ⌘A,
  ⌘⇧A)
- Finder-style multi-selection (plain/⌘/⇧-click, ⇧-arrow, independent of
  drag/Quick Look/keyboard state)
- Native file icons via `NSWorkspace`, matching what Finder shows for every
  registered macOS file type
- Custom app and menu bar icon (replacing the placeholder SF Symbol used
  during early development)
- Hover and selection visuals using native semantic AppKit colors
- Populated empty states with subtle navigation-state fade transitions
- Duplicate-folder feedback (an audible beep when re-adding an existing root
  folder, instead of doing nothing silently)
- Native Settings window (⌘, or the header gear icon), split into General,
  Hotkeys, and About pages:
  - Launch at Login (via `SMAppService`)
  - Enable Quick Look toggle
  - Restore Last Opened Folder toggle
  - Configurable drag-cleanup delay (30/60/120s)
  - Read-only keyboard shortcuts reference
  - Restore Defaults (with confirmation)
  - View Latest Release (opens the GitHub releases page; no automatic
    version checking yet)
  - Quit FolderDrop (immediate, no confirmation)
  - About page with working GitHub Repository and Report an Issue links,
    plus License, Privacy, and Credits sections
- Pre-release security & privacy audit, including a full git-history review
  for secrets and personal information
- Project-owned bundle identifier (`com.folderdrop.app`)
- `CONTRIBUTING.md`, `CHANGELOG.md`, issue/PR templates, and a documented
  Known Limitations list (see [known-limitations.md](known-limitations.md))

### Remaining Before Release

- [ ] Real screenshots and a hero GIF for the README
- [ ] Signed, notarized release build — currently undecided; see
      [release-process.md](release-process.md) and the sandbox item under
      Version 1.1 below
- [ ] Continued UI polish passes, as needed (treated as an ongoing,
      incremental effort rather than a one-time pass)

---

## Version 1.0.1

Reserved for critical bug fixes only, if any are found after v1.0 ships. No
release-blocking issues are currently known — see
[known-limitations.md](known-limitations.md) for existing, non-blocking bugs
already being tracked for a later version.

---

## Version 1.1

Planned improvements, not yet started unless noted otherwise:

- [ ] Investigate a non-sandbox architecture for direct/GitHub distribution
      to simplify drag & drop and file access. **Under investigation —
      not a decision to remove App Sandbox**; see
      [known-limitations.md](known-limitations.md#drag--drop-davinci-resolve)
      for the drag-and-drop issue driving this investigation.
- [ ] Rework drag & drop architecture to better match Finder's file-reference
      behavior
- [ ] Folder drag & drop support (currently files only)
- [ ] Sorting options (date modified, size, kind, etc. — currently
      alphabetical only)
- [ ] Improved Quick Look behavior (fullscreen focus-restoration edge case)
- [ ] Automatic update checking (Sparkle or equivalent) — "View Latest
      Release" currently only opens the GitHub releases page manually, with
      no in-app version comparison or notification
- [ ] Search/filter within the current folder's contents
- [ ] Homebrew Cask formula
- [ ] Additional quality-of-life improvements, as they come up

---

## Version 1.2

- [ ] Finder Sync extension for deeper Finder integration
- [ ] Custom/remappable keyboard shortcuts (would extend the single
      centralized `NSEvent` monitor's key-mapping rather than replace it)
- [ ] Richer previews beyond what Quick Look provides by default
- [ ] Performance work if folder sizes/entry counts grow significantly
      (`FolderContentsLoader` and `SelectionState` have not been built or
      tested against very large directories)

---

## Long-Term Ideas

Not scheduled — directional ideas only:

- App Store release (would require revisiting the sandbox/entitlement setup
  and the security-scoped bookmark strategy for App Store compliance)
- Drag-and-drop *into* FolderDrop (currently entirely outbound)
- Folder favorites/pinning and reordering
- Multi-window support (currently one menu bar panel, one Settings window)

---

## Known Limitations

Features that don't exist yet. For bugs in behavior that *is* implemented, see
[docs/known-limitations.md](known-limitations.md).

- No search or filtering within a folder's contents
- No Finder Sync extension (badges/context menu integration inside Finder
  itself)
- No automatic update mechanism — "View Latest Release" opens the GitHub
  releases page manually; there's no in-app version check, notification, or
  Sparkle (or equivalent) integration yet
- Keyboard shortcuts are fixed — not user-remappable
- No drag-and-drop *into* FolderDrop (only outbound drag is implemented)
- No folder reordering or favorites/pinning
- Root folder removal has no undo beyond re-adding the folder manually
- No multi-window support — one menu bar panel, one Settings window
- Not yet notarized or distributed outside building from source
