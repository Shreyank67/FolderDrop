//
//  GeneralSettingsView.swift
//  FolderDrop
//
//  The General page of Settings: Launch at Login, Quick Look, restoring the
//  last opened folder, and the drag-and-drop cleanup delay.
//

import SwiftUI

/// How long a staged drag-and-drop temp file is kept before cleanup, in seconds.
/// FileRowView reads the same UserDefaults key (via its raw Int) independently,
/// since it only needs the number, not this enum. Not private: AboutSettingsView's
/// Restore Defaults also needs to set it back to .sixty.
enum CleanupDelay: Int, CaseIterable, Identifiable {
    case thirty = 30
    case sixty = 60
    case oneTwenty = 120

    var id: Int { rawValue }

    var label: String {
        "\(rawValue) seconds"
    }
}

/// Every toggle/picker here edits real, already-effective app state directly —
/// there's no separate "Apply"/"Save" step, matching how every other macOS
/// preferences window behaves.
struct GeneralSettingsView: View {
    // Backed directly by UserDefaults via the shared keys — this view doesn't
    // hold its own copy of the state, it's just an editor for the real thing.
    @AppStorage(SettingsKeys.quickLookEnabled) private var isQuickLookEnabled = true
    @AppStorage(SettingsKeys.restoresLastOpenedFolder) private var restoresLastOpenedFolder = false
    @AppStorage(SettingsKeys.dragCleanupDelaySeconds) private var cleanupDelay: CleanupDelay = .sixty

    // Not UserDefaults-backed: SMAppService.mainApp.status is itself the source
    // of truth, so this just mirrors it for the Toggle to render.
    @State private var isLaunchAtLoginEnabled = LaunchAtLoginService.isEnabled
    @State private var launchAtLoginError: String?

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { isLaunchAtLoginEnabled },
            set: { newValue in
                do {
                    try LaunchAtLoginService.setEnabled(newValue)
                    isLaunchAtLoginEnabled = newValue
                } catch {
                    // isLaunchAtLoginEnabled is deliberately left unchanged, so the
                    // Toggle (which reads it via `get` above) snaps back on its own.
                    launchAtLoginError = error.localizedDescription
                }
            }
        )
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle(isOn: launchAtLoginBinding) {
                    SettingTitleDescription(
                        title: "Launch FolderDrop at Login",
                        description: "Automatically starts FolderDrop whenever you log into your Mac."
                    )
                }
            }

            Section("Behavior") {
                Toggle(isOn: $isQuickLookEnabled) {
                    SettingTitleDescription(
                        title: "Enable Quick Look",
                        description: "Preview the selected file with the Space key without opening it."
                    )
                }
                Toggle(isOn: $restoresLastOpenedFolder) {
                    SettingTitleDescription(
                        title: "Restore last opened folder",
                        description: "Reopen the folder you were browsing when FolderDrop was last closed."
                    )
                }
            }

            Section("Drag & Drop") {
                Picker(selection: $cleanupDelay) {
                    ForEach(CleanupDelay.allCases) { delay in
                        Text(delay.label).tag(delay)
                    }
                } label: {
                    SettingTitleDescription(
                        title: "Clean up temporary files after",
                        description: "Temporary files created during drag and drop are automatically removed after the selected delay."
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // SMAppService's status can change outside the app (e.g. the user
            // removed it in System Settings > General > Login Items), so refresh
            // from it every time the Settings window opens rather than trusting
            // whatever this view last rendered.
            isLaunchAtLoginEnabled = LaunchAtLoginService.isEnabled
        }
        .alert(
            "Couldn't Update Launch at Login",
            isPresented: Binding(
                get: { launchAtLoginError != nil },
                set: { isPresented in
                    if !isPresented { launchAtLoginError = nil }
                }
            ),
            presenting: launchAtLoginError
        ) { _ in
            Button("OK") { launchAtLoginError = nil }
        } message: { message in
            Text(message)
        }
    }
}

#Preview {
    GeneralSettingsView()
}
