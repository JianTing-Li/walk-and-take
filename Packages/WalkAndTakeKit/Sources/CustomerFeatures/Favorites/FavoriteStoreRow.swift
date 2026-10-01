//
//  FavoriteStoreRow.swift
//  WalkAndTakeKit
//

import DesignSystem
import Domain
import SwiftUI

struct FavoriteStoreRow: View {
    let row: FavoritesModel.Row
    let showsBell: Bool
    let onToggleAlerts: () -> Void

    var body: some View {
        HStack(spacing: Spacing.m) {
            CategoryTile(category: row.category)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(row.name).font(.headline)
                statusText
            }

            Spacer(minLength: Spacing.xs)

            if showsBell {
                Button(action: onToggleAlerts) {
                    Image(systemName: row.alertsOn ? "bell.fill" : "bell.slash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(row.alertsOn ? Color.splashTeal : .secondary)
                        .frame(width: 44, height: 44)
                        .background(
                            row.alertsOn ? Color.splashTeal.opacity(0.15) : Color(.tertiarySystemFill), in: Circle()
                        )
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .sensoryFeedback(.selection, trigger: row.alertsOn)
                .accessibilityLabel(row.alertsOn ? "Turn off alerts for \(row.name)" : "Turn on alerts for \(row.name)")
            }
        }
        .padding(.vertical, 4)
    }

    /// Icon and text sit tight together, in a fixed-width icon column so every row's text lines up.
    private var statusText: some View {
        let (symbol, text, color): (String, String, Color) =
            switch row.status {
            case .availableNow(let text): ("bag.fill", text, .splashTeal)
            case .upcoming(let text): ("clock", text, .orange)
            case .none: ("bag", "No bags left today", .secondary)
            }
        return HStack(spacing: Spacing.xxs) {
            Image(systemName: symbol)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
    }

    @ScaledMetric(relativeTo: .caption) private var iconWidth: CGFloat = 16
}
