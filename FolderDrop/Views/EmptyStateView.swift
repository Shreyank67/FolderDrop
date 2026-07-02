   //
//  EmptyStateView.swift
//   FolderDrop
//
//  A small, reusable placeholder for "nothing to show here" screens.
//  Pure display component — it receives data and does not own any @State.
//

import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 28))
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
