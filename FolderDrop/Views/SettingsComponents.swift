//
//  SettingsComponents.swift
//  FolderDrop
//
//  Small views shared across the Settings pages (General, Hotkeys, About).
//

import SwiftUI

/// A setting's title with its explanation permanently visible underneath,
/// matching native macOS System Settings — reused by every configurable
/// control so every setting is self-explanatory without hovering.
struct SettingTitleDescription: View {
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
