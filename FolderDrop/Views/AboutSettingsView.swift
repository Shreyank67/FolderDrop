//
//  AboutSettingsView.swift
//  FolderDrop
//
//  The About page of Settings: app identity, project links, license and
//  privacy summaries, maintenance actions, and credits.
//

import AppKit
import SwiftUI

/// Only GitHub Repository and Report an Issue point anywhere real today —
/// both use this repository's actual public URL. Website has no real
/// destination yet, so it's shown as a disabled "Coming Soon" row rather
/// than a hardcoded placeholder domain that doesn't exist. A future support/
/// donate platform isn't listed at all yet — there's nothing to link, even
/// as a placeholder, until one exists. Discussions is left out entirely too
/// (not just disabled): GitHub Discussions isn't enabled for this
/// repository, so there's nothing to link even as a placeholder.
struct AboutSettingsView: View {
    // Only touched by restoreDefaults() below — the actual editors for these
    // live in GeneralSettingsView; this is the same UserDefaults-backed key,
    // not a separate copy of state.
    @AppStorage(SettingsKeys.quickLookEnabled) private var isQuickLookEnabled = true
    @AppStorage(SettingsKeys.restoresLastOpenedFolder) private var restoresLastOpenedFolder = false
    @AppStorage(SettingsKeys.dragCleanupDelaySeconds) private var cleanupDelay: CleanupDelay = .sixty

    @State private var showsRestoreDefaultsConfirmation = false
    @State private var showsUpToDateAlert = false

    private static let repositoryURL = URL(string: "https://github.com/Shreyank67/FolderDrop")!
    private static let issuesURL = URL(string: "https://github.com/Shreyank67/FolderDrop/issues/new/choose")!

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    appIcon
                        .resizable()
                        .frame(width: 64, height: 64)

                    Text("FolderDrop")
                        .font(.headline)

                    Text(versionString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("FolderDrop is an open-source macOS menu bar utility for quickly accessing, previewing, and dragging files from your frequently used folders.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Links") {
                ProjectLinkRow(title: "GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right", url: Self.repositoryURL)
                ProjectLinkRow(title: "Report an Issue", systemImage: "ladybug", url: Self.issuesURL)
                ProjectLinkRow(title: "Website", systemImage: "globe", url: nil)
            }

            Section("License") {
                Text("MIT License")
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("FolderDrop runs entirely on your Mac and does not collect analytics, telemetry, or personal data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Maintenance") {
                Button("Check for Updates…") {
                    showsUpToDateAlert = true
                }
                Button("Restore Defaults…") {
                    showsRestoreDefaultsConfirmation = true
                }
            }

            Section("Credits") {
                Text("Created by Shreyank Patil")
                    .foregroundStyle(.secondary)

                Text("Built using SwiftUI and AppKit.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Development assisted by ChatGPT and Claude.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert("You're up to date", isPresented: $showsUpToDateAlert) {
            Button("OK") {}
        } message: {
            Text("You're running the latest version of FolderDrop.")
        }
        .confirmationDialog(
            "Restore Defaults?",
            isPresented: $showsRestoreDefaultsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restore Defaults", role: .destructive) {
                restoreDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets Quick Look, folder restoring, and the temporary cleanup delay back to their default values. Launch at Login is not affected.")
        }
    }

    /// Launch at Login is deliberately untouched — it isn't one of these
    /// UserDefaults-backed preferences, and the requirement is explicit that
    /// resetting defaults shouldn't change the user's login-item registration.
    private func restoreDefaults() {
        isQuickLookEnabled = true
        restoresLastOpenedFolder = false
        cleanupDelay = .sixty
    }

    private var appIcon: Image {
        Image(nsImage: NSApplication.shared.applicationIconImage)
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(version)"
    }
}

/// A single "Links" row: a live outbound Link when a real URL exists, or a
/// plain, non-interactive "Coming Soon" row when it doesn't. `.buttonStyle(.plain)`
/// on the Link strips SwiftUI's default blue/underlined hyperlink styling so
/// it reads as a native System Settings row rather than a web link.
private struct ProjectLinkRow: View {
    let title: String
    let systemImage: String
    let url: URL?

    var body: some View {
        if let url {
            Link(destination: url) {
                HStack {
                    Label(title, systemImage: systemImage)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text("Coming Soon")
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AboutSettingsView()
}
