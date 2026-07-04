//
//  EmptyStateView.swift
//   FolderDrop
//
//  A small, reusable placeholder for "nothing to show here" screens.
//  Pure display component — it receives data and does not own any @State.
//

import SwiftUI

/// Shared between "no root folders added yet" and "this folder is empty" — two
/// visually similar but semantically different states. `iconSize` defaults to
/// the smaller size used for the latter; only the top-level onboarding call
/// site opts into a larger icon, since that's the one screen where the icon
/// doubles as the primary visual anchor for a brand-new user.
struct EmptyStateView: View {
    let systemImage: String
    var iconSize: CGFloat = 28
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))

            Text(title)
                .font(.callout.weight(.medium))

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
