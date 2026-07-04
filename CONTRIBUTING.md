# Contributing to FolderDrop

Thanks for your interest in contributing. FolderDrop is a small, native macOS
project — the goal of this guide is to get you productive quickly without a
lot of process overhead.

## Before You Start

- Read [docs/architecture.md](docs/architecture.md) to understand why the
  major pieces (MenuBarExtra, FolderWatcher, selection, Quick Look,
  persistence, settings) are shaped the way they are.
- Read [docs/implementation-history.md](docs/implementation-history.md) if
  you're touching an area that's already been iterated on — several
  approaches have already been tried and rejected for specific, documented
  reasons, and it's worth knowing why before re-proposing one of them.
- Check [docs/roadmap.md](docs/roadmap.md) to see what's already planned, so
  proposed features don't overlap with in-progress work.
- If you're preparing a tagged release rather than a code contribution, see
  [docs/release-process.md](docs/release-process.md) instead of this guide.

---

## Build Instructions

FolderDrop has no external dependencies or package managers — it's a plain
Xcode project.

**Requirements:**
- macOS 26 or later
- Xcode 26 or later

**Setup:**

```bash
git clone https://github.com/Shreyank67/FolderDrop.git
cd FolderDrop
open FolderDrop.xcodeproj
```

Build and run with `⌘R`. FolderDrop is sandboxed
(`ENABLE_APP_SANDBOX = YES`); the first time you add a folder, macOS will
prompt for access, and FolderDrop persists that access using a
security-scoped bookmark (see [docs/architecture.md](docs/architecture.md)).

To build from the command line instead of Xcode:

```bash
xcodebuild -project FolderDrop.xcodeproj -scheme FolderDrop -configuration Debug build
```

See [README.md § Building](README.md#building) for the same instructions in
context.

---

## Coding Style

- **SwiftUI views stay stateless where possible.** `ContentView` is the one
  place app-wide state (navigation, selection, watchers) is coordinated;
  child views (`FileListView`, `FileRowView`, `FolderHeaderView`, etc.)
  receive data and callbacks rather than owning state of their own. New
  views should follow the same pattern unless there's a specific reason not
  to.
- **AppKit is used directly only where SwiftUI has no equivalent** (Quick
  Look, security-scoped bookmarks, native multi-item drag sessions, the
  keyboard event monitor). Don't reach for AppKit bridging as a default —
  check whether a pure SwiftUI approach already covers the need first.
- **Comment the *why*, not the *what*.** The existing codebase favors
  comments that explain a non-obvious constraint, a rejected alternative, or
  a platform quirk — not comments that restate what the next line of code
  does. If you're fixing a bug or working around unexpected framework
  behavior, a short comment explaining why is expected, in keeping with the
  rest of the codebase.
- **Match existing naming and file organization.** `Models/` holds data
  shapes and pure logic, `Services/` wraps macOS/AppKit APIs behind small
  focused interfaces, `Views/` holds UI components — see
  [README.md § Project Structure](README.md#project-structure).
- **No new third-party dependencies** without discussing it in an issue
  first — part of what keeps this project simple to build is having none.

---

## Commit Message Guidelines

- Use the imperative mood for the subject line (e.g. "Add live folder
  watching", not "Added" or "Adds").
- Optionally prefix with a [Conventional Commits](https://www.conventionalcommits.org/)-style
  type when it clarifies intent — `feat:`, `fix:`, `docs:`, `refactor:`,
  `chore:` — with an optional scope, e.g. `fix(settings): ...`. Not every
  commit in this project's history uses a prefix, and that's fine; use one
  when it adds clarity, skip it when the subject line is already clear on
  its own.
- Keep the subject line short (under ~70 characters) and put detail in the
  body as a bullet list of what changed.
- Explain **why**, not just what, for anything non-obvious — a one-line
  summary sentence at the end of the body describing the overall intent of
  the change is common in this project's history and is encouraged.
- Keep commits focused. A documentation-only change shouldn't also touch
  Swift code, and a behavior change shouldn't be bundled with unrelated
  refactoring.

---

## Making Changes

- Keep pull requests focused — one feature or fix per PR is easier to review
  than several bundled together.
- Test on-device: sandboxed filesystem behavior (security-scoped bookmarks,
  Quick Look, drag-and-drop) is hard to fully verify without running the
  actual app.

---

## Pull Request Checklist

Before opening a pull request, confirm:

- [ ] The project builds with no errors or new warnings:
      `xcodebuild -project FolderDrop.xcodeproj -scheme FolderDrop -configuration Debug build`
- [ ] The change is focused — unrelated refactoring or formatting changes
      are left out
- [ ] New or changed behavior has been tested on-device, not just assumed to
      work from reading the code
- [ ] Comments explain *why*, not *what*, consistent with the existing style
- [ ] The PR description explains what changed and why
- [ ] Screenshots or a short screen recording are included for any UI change
- [ ] `docs/roadmap.md` and/or `docs/implementation-history.md` are updated
      if the change adds a feature, closes a known limitation, or is
      significant enough to be worth a future contributor knowing the story
      behind it
- [ ] `CHANGELOG.md` has an entry under an `[Unreleased]` section if the
      change is user-facing

The repository's [pull request template](.github/PULL_REQUEST_TEMPLATE.md)
mirrors this checklist and will be pre-filled when you open a PR.

---

## Reporting Issues

Please use the repository's issue templates rather than a blank issue:

- **[Bug report](../../issues/new?template=bug_report.md)** — for something
  that doesn't work as expected. Include what you expected to happen, what
  actually happened, your macOS version, FolderDrop's version (Settings →
  About), and steps to reproduce.
- **[Feature request](../../issues/new?template=feature_request.md)** — for
  a new capability or behavior change. Check
  [docs/roadmap.md](docs/roadmap.md) first to see if it's already planned.

---

## License

By contributing, you agree that your contributions will be licensed under the
project's [MIT License](LICENSE).
