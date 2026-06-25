## FolderDrop

A lightweight native macOS menu bar application that lets you browse and access files without opening Finder.

Built as a learning project in SwiftUI while recreating and extending the idea behind FolderPeek.
P.S. Honestly I didnt want to pay for FolderPeek and thaught it'll be fun to build my own!

---

## MVP Features

- [X] Menu bar icon
- [X] Folder picker
- [X] File browser
- [ ] Folder tree
- [ ] Drag & Drop
- [ ] Search
- [ ] Open in Finder
- [ ] Remember selected folders




# Vision

FolderDrop should make frequently accessed files instantly available from the macOS menu bar.

Long-term goals include:

- Browse folders
- Drag files into any application
- Search files
- Quick previews
- Multiple folders
- Favorites
- Recently opened files
- Startup at login

---

# Current Progress

## ✅ Phase 1 — Foundation

- [x] Native SwiftUI Menu Bar application
- [x] GitHub repository
- [x] Project architecture
- [x] README roadmap

---

## ✅ Feature 1 — Menu Bar App

### Goal

Convert a standard macOS window application into a native MenuBarExtra utility.

### Concepts Learned

- SwiftUI App lifecycle
- MenuBarExtra
- Scenes
- LSUIElement
- Info.plist
- SwiftUI App structure

### Result

- Folder icon appears in menu bar
- No Dock icon
- Window replaced with floating panel

---

## ✅ Feature 2 — Folder Picker

### Goal

Allow the user to choose a folder using the native macOS picker.

### Concepts Learned

- @State
- URL
- NSOpenPanel
- Optional Binding
- AppKit + SwiftUI

### Result

- Select Folder button
- Native folder picker
- Folder name displayed
- Folder path displayed

---

## ✅ Feature 3 — Folder Browser

### Goal

Display the contents of the selected folder.

### Concepts Learned

- FileManager
- Directory enumeration
- List
- ForEach
- Identifiable
- Security Scoped Resources
- File sorting

### Result

- Folder contents displayed
- Folders first
- Files second
- Alphabetical sorting
- Scrollable list

-------------------------------------   *   *   *   -------------------------------- 

# Upcoming Features

## Phase 2 — File Actions

- [ ] Open files
- [ ] Reveal in Finder
- [ ] Display file icons

---

## Phase 3 — Drag & Drop

- [ ] Drag files into any application
- [ ] Drag folders
- [ ] Multi-file drag

---

## Phase 4 — Persistence

- [ ] Remember selected folders
- [ ] Security scoped bookmarks

---

## Phase 5 — Productivity

- [ ] Search
- [ ] Favorites
- [ ] Recent files
- [ ] Multiple folders

---

## Phase 6 — Polish

- [ ] Startup at login
- [ ] Settings
- [ ] Keyboard shortcuts
- [ ] Quick Look preview
- [ ] Context menu

-------------------------------------   *   *   *   -------------------------------- 

# Planned Architecture

```
FolderDrop

├── App
│   └── MenuBarExtra

├── Views
│   ├── ContentView
│   ├── FolderListView
│   ├── FileRowView
│   └── SettingsView

├── Models
│   ├── FolderEntry
│   └── FolderModel

├── Services
│   ├── FolderPicker
│   ├── FileManager
│   ├── BookmarkManager
│   └── DragManager
```

-------------------------------------   *   *   *   -------------------------------- 

# Development Journal

### 2026-06-25

- Created SwiftUI macOS project
- Converted app into MenuBarExtra
- Learned Git + GitHub workflow
- Implemented folder picker
- Implemented folder browser