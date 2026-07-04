# Release Process

This document describes how a FolderDrop release is intended to be cut. Parts
of this process (signing, notarization, and the website update) are not yet
automated or exercised end-to-end — they're documented here as a placeholder
for when FolderDrop starts shipping signed builds, so the process is defined
before it's needed rather than improvised at the first release.

---

## 1. Version Bump

Update the app's version before building:

- Bump `CFBundleShortVersionString` (marketing version, e.g. `1.0.0`) and
  `CFBundleVersion` (build number) in the Xcode project's target settings.
- `AboutSettingsView` reads `CFBundleShortVersionString` directly, so this is
  the single place the visible version string comes from.

---

## 2. Building

Build a Release configuration archive, not a Debug build:

```bash
xcodebuild -project FolderDrop.xcodeproj -scheme FolderDrop -configuration Release archive \
  -archivePath build/FolderDrop.xcarchive
```

Debug builds retain `#if DEBUG`-gated code paths that should never ship; the
Release configuration excludes them at compile time.

---

## 3. Signing

> Not yet exercised — FolderDrop currently builds and runs locally with
> ad hoc / "Sign to Run Locally" signing only.

For a distributable build, this step will need:

- A valid **Developer ID Application** certificate
- Exporting the archive with that identity via `xcodebuild -exportArchive`
  and a distribution `exportOptionsPlist`
- Hardened Runtime enabled (required for notarization)

---

## 4. Notarization

> Placeholder — not yet performed.

Once signed with a Developer ID certificate, the build will need to be
submitted to Apple's notary service before distribution outside the App
Store:

```bash
xcrun notarytool submit FolderDrop.zip --keychain-profile "<profile>" --wait
xcrun stapler staple FolderDrop.app
```

Without this step, Gatekeeper will warn or block unidentified-developer
downloads on a fresh macOS installation.

---

## 5. GitHub Release

- Tag the release commit (`git tag vX.Y.Z && git push origin vX.Y.Z`)
- Create a GitHub Release from that tag, with release notes summarizing
  user-facing changes (cross-reference [roadmap.md](roadmap.md) for what
  shipped)
- Attach the notarized, zipped `.app` as a release asset

---

## 6. Website Update

> Placeholder — no public website exists yet.

Once one does, this step should update the download link and version number
shown there to match the newly published GitHub Release.

---

## 7. Homebrew (Future)

Once releases are versioned and notarized consistently, a Homebrew Cask
formula (`brew install --cask folderdrop`) is planned — see
[roadmap.md](roadmap.md). This isn't set up yet.
