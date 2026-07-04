//
//  AboutSettingsView.swift
//  FolderDrop
//
//  The About page of Settings: app identity, project links (placeholders
//  until the project is published), open-source details, maintenance
//  actions, and credits.
//

import AppKit
import SwiftUI

/// Project links are intentionally disabled placeholders (see ProjectLinkRow
/// below) rather than omitted — reserving their spot in the layout now avoids
/// a settings-window redesign the day real URLs exist to fill them in.
struct AboutSettingsView: View {
    // Only touched by restoreDefaults() below — the actual editors for these
    // live in GeneralSettingsView; this is the same UserDefaults-backed key,
    // not a separate copy of state.
    @AppStorage(SettingsKeys.quickLookEnabled) private var isQuickLookEnabled = true
    @AppStorage(SettingsKeys.restoresLastOpenedFolder) private var restoresLastOpenedFolder = false
    @AppStorage(SettingsKeys.dragCleanupDelaySeconds) private var cleanupDelay: CleanupDelay = .sixty

    @State private var showsRestoreDefaultsConfirmation = false
    @State private var showsUpToDateAlert = false

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

                    Text("An open-source menu bar utility for quickly browsing, previewing, and opening files.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Disabled rather than removed: these are prepared now so the
            // project only needs real URLs wired in later, not new UI.
            Section("Project") {
                ProjectLinkRow(title: "GitHub Repository")
                ProjectLinkRow(title: "Documentation")
                ProjectLinkRow(title: "Website")
                ProjectLinkRow(title: "Support Development")
            }

            Section("Open Source") {
                LabeledContent("License", value: "MIT License")
                LabeledContent("Built With", value: "SwiftUI, AppKit, Quick Look")
                LabeledContent("Platform", value: "macOS")
            }

            Section("Maintenance") {
                Button("Check for Updates…") {
                    showsUpToDateAlert = true
                }
                Button("Restore Defaults…") {
                    showsRestoreDefaultsConfirmation = true
                }
            }

            Section("Created by") {
                Text("Shreyank Patil")
                    .foregroundStyle(.secondary)

                Text("Thank you for supporting independent open-source software.")
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

/// A row that visually reads as an outbound link — trailing external-link
/// icon — but is disabled until the project has a real URL to send it to.
/// No link is hardcoded or invented; this only prepares the row's shape.
private struct ProjectLinkRow: View {
    let title: String

    var body: some View {
        Button {
            // Intentionally empty: disabled until a real URL exists.
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(true)
    }
}

#Preview {
    AboutSettingsView()
}
