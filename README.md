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

---

### ✅ Folder Navigation

- Navigate into subfolders
- Navigate back to parent folders
- Root folder remains unchanged
- Change Folder resets navigation

---

### ✅ Open Files

Clicking a file opens it using the default macOS application.

Examples:

- PDF → Preview
- PNG → Preview
- SVG → Affinity Designer (or system default)
- Text → TextEdit
- ZIP → Archive Utility

---

### ✅ Native macOS File Icons

Uses Finder's native file and folder icons through `NSWorkspace`.

The application automatically displays the correct icon for:

- Folders
- Documents
- Images
- Archives
- Applications
- Any registered macOS file type

---

### ✅ UI Improvements

Recent UI polish includes:

- Native folder icon in the header
- Compact Finder-style parent path
- Improved typography hierarchy
- Better row spacing
- Reduced list indentation
- Larger scrolling area
- Improved overall spacing and alignment

---
-------------------------------------   *   *   *   -------------------------------- 

## Roadmap

### ✅ Phase 1 — Foundation

- [x] Menu Bar Application
- [x] Folder Picker
- [x] Folder Browser
- [x] Folder Navigation
- [x] Open Files
- [x] Native File Icons
- [x] UI Polish

---

### 🚧 Phase 2 — Core Features

- [ ] Folder Persistence
- [ ] Drag & Drop Support
- [ ] Reveal File in Finder
- [ ] Context Menu

---

### 📅 Phase 3 — Productivity

- [ ] Search
- [ ] Favorites
- [ ] Recent Folders
- [ ] Keyboard Shortcuts
- [ ] Quick Look Preview

---

### ✨ Phase 4 — Polish

- [ ] Launch at Login
- [ ] Settings Window
- [ ] Multiple Folder Support
- [ ] Performance Improvements
- [ ] Accessibility Improvements

---

## Technologies

- Swift
- SwiftUI
- AppKit
- NSWorkspace
- NSOpenPanel
- FileManager
- Xcode
- Git
- GitHub


-------------------------------------   *   *   *   -------------------------------- 

## Project Structure

```
FolderDrop/
│
├── FolderDropApp.swift
├── ContentView.swift
│
├── Models/
│   ├── FolderEntry.swift
│   └── FolderNavigation.swift
│
├── Services/
│   ├── FolderContentsLoader.swift
│   └── FileIconProvider.swift
│
└── Views/
    ├── FolderHeaderView.swift
    ├── FileListView.swift
    └── FileRowView.swift
```
The project follows a simple separation of responsibilities.

- **Models** → Application data
- **Views** → UI components
- **Services** → macOS APIs and file system operations
- **ContentView** → Coordinates state and user interactions

---

-------------------------------------   *   *   *   -------------------------------- 

# Development Journal

### 2026-06-25

- Created SwiftUI macOS project
- Converted app into MenuBarExtra
- Learned Git + GitHub workflow
- Implemented folder picker
- Implemented folder browser


### 2026-07-01

- changed workflow (ChatGPT, Claude Code, VS Code)
- Added new features
- Made UI improvements