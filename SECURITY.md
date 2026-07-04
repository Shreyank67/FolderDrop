# Security Policy

FolderDrop is a sandboxed macOS app with no network access, no analytics,
and no third-party dependencies — see [README.md § Privacy](README.md#privacy)
and [docs/architecture.md](docs/architecture.md) for how folder access is
scoped. That said, if you find a real security or privacy issue, please
report it responsibly rather than opening a public issue.

## Supported Versions

FolderDrop hasn't cut a tagged release yet — see
[docs/roadmap.md](docs/roadmap.md) for release status. Once versioned
releases begin, only the latest released version will receive security
fixes.

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for a security or privacy
concern — that gives anyone browsing the repository a working description
of the problem before a fix exists.

Instead, use GitHub's private vulnerability reporting for this repository:

1. Go to the repository's **Security** tab.
2. Select **Report a vulnerability**.
3. Describe the issue, including steps to reproduce and what you'd expect
   to happen instead.

If that option isn't available to you, open a regular issue asking to be
pointed to an alternate contact — without describing the vulnerability
itself — and it will be followed up on privately.

## What to Expect

This is a small, actively maintained open-source project without a formal
disclosure SLA. You should expect an acknowledgment and an honest read on
severity and timeline once a report comes in, not a guaranteed response
window.

## Scope

In scope: FolderDrop's own code (this repository) and its use of macOS
sandbox/security-scoped bookmark APIs. Out of scope: vulnerabilities in
macOS itself, Quick Look (`quicklookd`), or any third-party app FolderDrop
hands files to via drag-and-drop — please report those to Apple or the
relevant vendor instead.
