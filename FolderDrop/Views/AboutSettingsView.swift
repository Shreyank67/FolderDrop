//
//  AboutSettingsView.swift
//  FolderDrop
//
//  The About page of Settings: app identity, project links (placeholders for
//  now), Check for Updates, and Restore Defaults — moved here from the old
//  single-page General settings, unchanged in behavior.
//

import AppKit
import SwiftUI

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
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Project") {
                Text("GitHub Repository")
                    .foregroundStyle(.secondary)
                Text("Website")
                    .foregroundStyle(.secondary)
                Text("Support Development")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Check for Updates…") {
                    showsUpToDateAlert = true
                }
                Button("Restore Defaults…") {
                    showsRestoreDefaultsConfirmation = true
                }
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

#Preview {
    AboutSettingsView()
}
