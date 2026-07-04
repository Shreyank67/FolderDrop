# Roadmap

This document tracks what's done, what's actively planned, and longer-range
ideas that haven't been scheduled. For how each completed feature was
actually built, see [implementation-history.md](implementation-history.md).
For why the architecture looks the way it does, see
[architecture.md](architecture.md).

---

## RC1 Polish

Work remaining before the first public release candidate:

- [ ] Prebuilt, signed, notarized release build (see
      [release-process.md](release-process.md))
- [ ] Real screenshots and a hero GIF for the README
- [x] `CONTRIBUTING.md`, `CHANGELOG.md`, and issue/PR templates finalized
- [x] Pre-release security & privacy audit, including a full git-history
      review for secrets and personal information
- [x] Adopt a project-owned bundle identifier (`com.folderdrop.app`) ahead
      of release
- [ ] Continued UI polish passes, as needed (treated as an ongoing,
      incremental effort rather than a one-time pass)

---

## Version 1.1

- [ ] Wire "Check for Updates" to a real updater (Sparkle or equivalent)
- [ ] Search/filter within the current folder's contents
- [ ] Homebrew Cask formula

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

## Completed Features

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
- Hover and selection visuals using native semantic AppKit colors
- Populated empty states with subtle navigation-state fade transitions
- Native Settings window (⌘, or the header gear icon), split into General,
  Hotkeys, and About pages:
  - Launch at Login (via `SMAppService`)
  - Enable Quick Look toggle
  - Restore Last Opened Folder toggle
  - Configurable drag-cleanup delay (30/60/120s)
  - Read-only keyboard shortcuts reference
  - Restore Defaults (with confirmation)
  - Check for Updates (placeholder)
  - About page with working GitHub Repository and Report an Issue links,
    plus License, Privacy, and Credits sections

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
- Not yet notarized or distributed outside building from source
