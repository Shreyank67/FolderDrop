# FolderDrop

A native macOS menu bar app for browsing, previewing, and dragging files without opening Finder.

FolderDrop lives in your menu bar and gives you instant access to the folders you use most — browse into subfolders, preview files with Quick Look, drag files straight into other apps, and jump around entirely from the keyboard. It's built for anyone who reaches for a handful of the same folders dozens of times a day and doesn't want a full Finder window every time. FolderDrop is free and open source, built natively with SwiftUI and AppKit.

<!-- HERO GIF HERE -->

*Add a GIF showing:*
- *opening FolderDrop*
- *navigating folders*
- *Quick Look*
- *drag & drop*

---

## Features

- [x] Multiple root folders
- [x] Folder navigation with back/breadcrumb support
- [x] Native Quick Look preview (single file or multi-selection)
- [x] Native drag & drop (single and multi-file, to Finder, Mail, Chrome, Slack, VS Code, and more)
- [x] Finder-style multi-selection (click, ⌘-click, ⇧-click/⇧-arrow)
- [x] Full keyboard navigation
- [x] Live folder refresh (auto-updates when files change on disk)
- [x] Launch at Login
- [x] Native Settings window
- [x] Security-scoped bookmarks (persists folder access across launches)
- [x] Menu bar application (no Dock icon, no regular window)

---

## Screenshots

<!-- Screenshot: Empty State -->

*Description: The onboarding screen shown when no root folders have been added yet.*

<!-- Screenshot: Root Folders -->

*Description: The top-level list of root folders added to FolderDrop.*

<!-- Screenshot: Folder Contents -->

*Description: Browsing inside a folder, showing files and subfolders with native icons.*

<!-- Screenshot: Settings — General -->

*Description: The General settings page — Launch at Login, Quick Look, restore last folder, drag cleanup delay.*

<!-- Screenshot: Settings — Hotkeys -->

*Description: The Hotkeys settings page listing all keyboard shortcuts.*

<!-- Screenshot: Settings — About -->

*Description: The About settings page — app info, project links, and maintenance actions.*

<!-- Screenshot: Quick Look Preview -->

*Description: Quick Look previewing a selected file directly from FolderDrop.*

---

## Installation

### Download

> Prebuilt release binaries aren't published yet. Check the [Releases](../../releases) page once the first tagged release is out.

### Build from Source

See [Building](#building) below.

### Homebrew

> Not yet available. A `brew install --cask folderdrop` formula is planned once versioned releases exist — see [docs/roadmap.md](docs/roadmap.md).

---

## Building

FolderDrop is a standard Xcode project — no external dependencies or package managers are involved.

**Requirements:**
- macOS 26 or later
- Xcode 26 or later

**Steps:**

```bash
git clone https://github.com/Shreyank67/FolderDrop.git
cd FolderDrop
open FolderDrop.xcodeproj
```

Then build and run with `⌘R`. FolderDrop is sandboxed (`ENABLE_APP_SANDBOX = YES`); the first time you add a folder, macOS will prompt for access, and FolderDrop persists that access using a security-scoped bookmark (see [docs/architecture.md](docs/architecture.md)).

To build from the command line instead:

```bash
xcodebuild -project FolderDrop.xcodeproj -scheme FolderDrop -configuration Debug build
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `↑` `↓` | Navigate |
| `⇧` + `↑` `↓` | Extend selection |
| `⌘` + Click | Multi-select |
| `⌘A` | Select all |
| `⌘⇧A` | Deselect all |
| `Esc` | Back |
| `Space` | Quick Look |
| `Enter` | Open file / navigate into folder |

---

## Project Structure

```
FolderDrop/
├── FolderDropApp.swift      # App entry point (MenuBarExtra + Settings scene)
├── ContentView.swift        # Root view — owns navigation/selection state
├── Models/                  # Data shapes and pure navigation/selection logic
├── Services/                # macOS API bridges (filesystem, persistence, Quick Look, login items)
└── Views/                   # Stateless UI components
```

Models hold data and pure logic, Services wrap macOS/AppKit APIs behind small focused interfaces, and Views are stateless — they receive data and callbacks from `ContentView`, which is the single place app-wide state and behavior are coordinated.

For a deeper explanation of *why* the architecture looks like this — MenuBarExtra, FolderWatcher, selection, Quick Look, persistence, settings, and security-scoped bookmarks — see **[docs/architecture.md](docs/architecture.md)**.

---

## Roadmap

**Coming Soon**
- Wire "Check for Updates" to a real updater
- Search/filter within the current folder

**Future Ideas**
- Finder Sync extension for deeper Finder integration
- Custom/remappable keyboard shortcuts
- Folder favorites/pinning

Full details, including completed work, live in **[docs/roadmap.md](docs/roadmap.md)**.

---

## Contributing

Contributions are welcome. See **[CONTRIBUTING.md](CONTRIBUTING.md)** for how to get set up and what to expect from a pull request.

---

## Changelog

See **[CHANGELOG.md](CHANGELOG.md)** for a version-by-version summary of what's shipped, in [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

---

## License

FolderDrop is released under the **MIT License**. See [LICENSE](LICENSE) for the full text.
