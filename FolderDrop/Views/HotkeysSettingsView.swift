//
//  HotkeysSettingsView.swift
//  FolderDrop
//
//  The Hotkeys page of Settings: the existing keyboard shortcuts reference,
//  plus a placeholder for future global shortcut customization. No shortcut
//  recording or registration exists yet — this page only prepares the
//  architecture for it.
//

import SwiftUI

struct HotkeysSettingsView: View {
    var body: some View {
        Form {
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

            Section("Global Shortcut") {
                SettingTitleDescription(
                    title: "Open FolderDrop",
                    description: "Global shortcut customization will be available in a future update."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
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
    HotkeysSettingsView()
}
