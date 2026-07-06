# Changelog

All notable changes to FolderDrop are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project intends to adhere to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
once versioned releases begin shipping.

For the detailed story behind how each feature below was built — including
bugs found, approaches rejected, and native macOS behavior discovered along
the way — see [docs/implementation-history.md](docs/implementation-history.md).

## [Unreleased]

### Added

- Startup cleanup of orphaned drag-and-drop staging files left behind by a
  previous run that quit, crashed, or didn't survive long enough for its own
  delayed cleanup to run.
- A documented Known Limitations list ([docs/known-limitations.md](docs/known-limitations.md)),
  covering current bugs in shipped behavior (Quick Look focus loss in some
  fullscreen apps, DaVinci Resolve drag staging, no folder drag, alphabetical-
  only sorting, Settings window fullscreen-Space behavior, and a minor Back
  button hit-testing inconsistency).

### Changed

- Replaced the placeholder SF Symbol menu bar icon and default app icon with
  FolderDrop's own custom icon.
- Reorganized the About settings page into Links, License, Privacy, and
  Credits sections. GitHub Repository and Report an Issue now link to this
  project's real repository and issue tracker.
- Changed the app's bundle identifier to `com.folderdrop.app` ahead of the
  first public release.

### Fixed

- Root folders on external drives or network shares are no longer
  permanently forgotten when a temporary access failure — most commonly the
  volume not yet being mounted — is mistaken for the folder having been
  deleted.

See [docs/roadmap.md](docs/roadmap.md) for what's planned next.

## [1.0.0]

Initial feature set.

### Added

- Menu bar application — no Dock icon, no regular window; the entire UI is a
  `MenuBarExtra` panel anchored under the menu bar icon.
- Multiple, persistent root folders, added via a native folder picker, with
  a native context menu (Open, Reveal in Finder, Remove).
- Security-scoped bookmarks for root folder access, auto-refreshed when
  stale and dropped automatically when no longer valid, so folder access
  survives an app relaunch without re-prompting.
- Folder navigation with back navigation and breadcrumbs.
- Live folder refresh — the currently displayed folder (and every root
  folder, for deletion detection) is watched for filesystem changes and
  reloads automatically, with no polling.
- Automatic cleanup of root folders deleted outside FolderDrop, with a safe
  fallback to the root list if the folder being browsed disappears
  mid-session.
- Native Quick Look preview (Space to toggle), supporting both a single file
  and a full multi-selection with native Left/Right cycling.
- Native drag-and-drop, including genuine multi-file drag sessions, to
  Finder, Mail, Chrome, Slack, VS Code, and other apps that read the
  standard `public.file-url` pasteboard representation.
- Finder-style multi-selection: plain click, ⌘-click (toggle), and
  ⇧-click/⇧-arrow (range), fully interoperable with each other.
- Full keyboard navigation: arrow keys, Shift-extend, Enter, Space, Escape,
  ⌘A, ⌘⇧A.
- Native Settings window (⌘, or the header gear icon), split into three
  pages:
  - **General** — Launch at Login (via `SMAppService`), Enable Quick Look,
    Restore Last Opened Folder, configurable drag-cleanup delay
    (30/60/120s), and Restore Defaults (with confirmation).
  - **Hotkeys** — a read-only keyboard shortcuts reference.
  - **About** — app info, version, project links, and a Check for Updates
    placeholder.
- Populated empty states (no root folders yet; folder is empty) with subtle
  fade transitions between navigation states.
- Native file icons via `NSWorkspace`, matching what Finder shows for every
  registered macOS file type.

[Unreleased]: https://github.com/Shreyank67/FolderDrop/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Shreyank67/FolderDrop/releases/tag/v1.0.0
