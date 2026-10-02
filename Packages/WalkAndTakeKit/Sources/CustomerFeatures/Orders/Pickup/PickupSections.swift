//
//  PickupSections.swift
//  WalkAndTakeKit
//
//  The pickup screen's cards: code + QR, steps, and rating.
//

import DesignSystem
import Domain
import SwiftUI

/// The pickup code and its QR, on the order screen and (smaller) on the confirmation sheet.
struct PickupCodeCard: View {
    let code: String
    /// The confirmation sheet's smaller version, so the pickup details fit above it.
    var compact = false
    var identifier = "pickup.code"

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text("Pickup code").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(code)
                .font(.pickupCode(size: compact ? 36 : 48))
                .tracking(compact ? 8 : 10)
                .accessibilityLabel("Pickup code \(code.map(String.init).joined(separator: " "))")
                .accessibilityIdentifier(identifier)
            QRCodeView(text: code, size: compact ? 110 : 150)
            Text("Show this to staff at the counter")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.l)
        .background(Color.yolk.opacity(0.25), in: RoundedRectangle(cornerRadius: Radius.card))
    }
}

/// A label and value. Long values (like "Pick up today, Thu Oct 1, 12:00–2:00 PM") move under the label
/// instead of wrapping mid-range.
struct SummaryRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value).fontWeight(.semibold).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).foregroundStyle(.secondary)
                Text(value).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

struct PickupSteps: View {
    let restaurantName: String
    let addressLine: String
    let instructions: String
    let directionsURL: URL?

    @ScaledMetric(relativeTo: .subheadline) private var badge: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            step(1, "Head to \(restaurantName)", detail: addressLine) {
                if let directionsURL {
                    Link(destination: directionsURL) {
                        Label("Get directions", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            step(2, "Show your pickup code", detail: instructions)
            step(3, "Confirm pickup together", detail: "Swipe below while you're at the counter.")
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.card))
    }

    private func step(
        _ n: Int, _ title: String, detail: String, @ViewBuilder extra: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Text("\(n)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: badge, height: badge)
                .background(Color.splashTeal, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
                extra()
            }
        }
    }
}

struct RatingCard: View {
    let restaurantName: String
    let review: Review?
    let canReview: Bool
    let onRate: @MainActor @Sendable (Int) -> Void

    var body: some View {
        if let review {
            VStack(spacing: 8) {
                Text("You rated this bag").font(.headline)
                StarsDisplay(rating: review.overall, size: 22)
                if !review.tags.isEmpty {
                    Text(ReviewTag.allCases.filter(review.tags.contains).map(\.label).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.l)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.card))
        } else if canReview {
            VStack(spacing: Spacing.s) {
                Text("How was your bag?").font(.headline)
                StarRating(rating: Binding(get: { 0 }, set: onRate), size: 34, label: "Rate your bag")
                Text("Tap a star to rate \(restaurantName)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.l)
            .background(Color.yolk.opacity(0.2), in: RoundedRectangle(cornerRadius: Radius.card))
        }
    }
}
