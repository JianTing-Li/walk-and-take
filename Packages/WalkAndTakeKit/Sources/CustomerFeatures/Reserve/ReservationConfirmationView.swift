//
//  ReservationConfirmationView.swift
//  WalkAndTakeKit
//

import DesignSystem
import SwiftUI

struct ReservationConfirmationView: View {
    let confirmation: ReservationConfirmation
    let onViewOrder: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.splashTeal)
                    .padding(.top, 32)
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text("You're all set!").font(.title.weight(.bold))
                    Text("Your bag at \(confirmation.restaurantName) is reserved.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // When and where first: that's what to plan around.
                VStack(spacing: Spacing.m) {
                    SummaryRow("When", confirmation.pickupText)
                    SummaryRow("Where", confirmation.address)
                    SummaryRow("How", confirmation.pickupInstructions)
                    SummaryRow("Bags", confirmation.bagsText)
                    // The reward banner below already says what the reward saved.
                    if confirmation.rewardRedeemed == nil, let rewardText = confirmation.rewardText {
                        SummaryRow("Reward", rewardText)
                    }
                    SummaryRow("Total", confirmation.totalText)
                }
                .padding(Spacing.l)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.panel))

                if let reminder = confirmation.walkReminderText {
                    Label(reminder, systemImage: "figure.walk")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.splashTeal)
                        .padding(Spacing.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.yolk.opacity(0.25), in: RoundedRectangle(cornerRadius: Radius.panel))
                        .accessibilityIdentifier("confirmation.walkReminder")
                }

                PickupCodeCard(code: confirmation.code, compact: true, identifier: "confirmation.code")

                if let redeemed = confirmation.rewardRedeemed {
                    RewardBanner(title: redeemed.title, detail: redeemed.detail, footer: redeemed.footer)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("confirmation.rewardRedeemed")
                }

                Text(confirmation.policyText)
                    .multilineTextAlignment(.center)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(Spacing.xl)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.s) {
                Button(action: onViewOrder) {
                    Text("View order").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("confirmation.viewOrder")
                Button {
                    dismiss()
                } label: {
                    Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .tint(.splashTeal)
            .padding(Spacing.l)
            .background(.bar)
        }
        .presentationDetents([.large])
    }

}
