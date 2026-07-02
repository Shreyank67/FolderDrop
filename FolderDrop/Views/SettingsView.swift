//
//  SettingsView.swift
//  FolderDrop
//
//  Native Settings window content. Only a General page exists so far — later
//  phases wire these controls to real persistence; this phase only builds the UI.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 420, height: 460)
    }
}

/// How long a staged drag-and-drop temp file is kept before cleanup, in seconds.
/// FileRowView reads the same UserDefaults key (via its raw Int) independently,
/// since it only needs the number, not this enum.
private enum CleanupDelay: Int, CaseIterable, Identifiable {
    case thirty = 30
    case sixty = 60
    case oneTwenty = 120

    var id: Int { rawValue }

    var label: String {
        "\(rawValue) seconds"
    }
}

private struct GeneralSettingsView: View {
    // Backed directly by UserDefaults via the shared keys — this view doesn't
    // hold its own copy of the state, it's just an editor for the real thing.
    @AppStorage(SettingsKeys.quickLookEnabled) private var isQuickLookEnabled = true
    @AppStorage(SettingsKeys.restoresLastOpenedFolder) private var restoresLastOpenedFolder = false
    @AppStorage(SettingsKeys.dragCleanupDelaySeconds) private var cleanupDelay: CleanupDelay = .sixty

    // Not UserDefaults-backed: SMAppService.mainApp.status is itself the source
    // of truth, so this just mirrors it for the Toggle to render.
    @State private var isLaunchAtLoginEnabled = LaunchAtLoginService.isEnabled
    @State private var launchAtLoginError: String?

    @State private var showsRestoreDefaultsConfirmation = false
    @State private var showsUpToDateAlert = false

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

            Section("Keyboard Shortcuts") {
                VStack(alignment: .leading, spacing: 6) {
                    ShortcutRow(keys: "↑ ↓", description: "Navigate")
                    ShortcutRow(keys: "⇧ ↑↓", description: "Extend Selection")
                    ShortcutRow(keys: "⌘ Click", description: "Multi-select")
                    ShortcutRow(keys: "⌘A", description: "Select All")
                    ShortcutRow(keys: "Esc", description: "Back")
                    ShortcutRow(keys: "Space", description: "Quick Look")
                    ShortcutRow(keys: "Enter", description: "Open")
                }
                .padding(.vertical, 2)
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
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 2) {
                Text("FolderDrop")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(versionString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 12)
        }
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

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(version)"
    }
}

/// A setting's title with its explanation permanently visible underneath,
/// matching native macOS System Settings — reused by every configurable
/// control so every setting is self-explanatory without hovering.
private struct SettingTitleDescription: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 8)
    }
}

/// One read-only row in the shortcuts list: a key-cap-styled shortcut on the
/// left, its description on the right — matching System Settings' own layout.
private struct ShortcutRow: View {
    let keys: String
    let description: String

    var body: some View {
        HStack {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor))
                )
                .frame(minWidth: 72, alignment: .center)

            Text(description)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    SettingsView()
}
