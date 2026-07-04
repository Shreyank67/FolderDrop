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

## Getting Set Up

FolderDrop has no external dependencies or package managers — see
[README.md § Building](README.md#building) for the full setup.

```bash
git clone https://github.com/<your-org>/FolderDrop.git
cd FolderDrop
open FolderDrop.xcodeproj
```

## Making Changes

- Keep pull requests focused — one feature or fix per PR is easier to review
  than several bundled together.
- Match the existing code style: SwiftUI views stay stateless where possible,
  with `ContentView` coordinating app-wide state; AppKit is used directly
  only where SwiftUI has no equivalent.
- If you're fixing a bug or changing behavior, a short comment explaining
  *why* (not just what) is appreciated, in keeping with the rest of the
  codebase's commenting style.
- Test on-device: sandboxed filesystem behavior (security-scoped bookmarks,
  Quick Look, drag-and-drop) is hard to fully verify without running the
  actual app.

## Submitting a Pull Request

1. Fork the repository and create a branch from `main`.
2. Make your changes, and confirm the project still builds:
   ```bash
   xcodebuild -project FolderDrop.xcodeproj -scheme FolderDrop -configuration Debug build
   ```
3. Open a pull request describing what changed and why. Screenshots or a
   short screen recording are appreciated for any UI change.

## Reporting Issues

Open a GitHub issue with:

- What you expected to happen
- What actually happened
- macOS version and FolderDrop version (see Settings → About)
- Steps to reproduce, if applicable

## License

By contributing, you agree that your contributions will be licensed under the
project's [MIT License](LICENSE).
