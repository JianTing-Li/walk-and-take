//
//  WalkRewardCard.swift
//  WalkAndTakeKit
//

import SwiftUI

/// Offer Detail panel: the walk to this restaurant and the reward progress it would earn.
public struct WalkRewardCard: View {
    public struct Content: Hashable, Sendable {
        /// e.g. "0.7 mi walk".
        public var title: String
        /// e.g. "Earns +0.7 mi toward your next reward".
        public var detail: String
        /// Optional extra line, e.g. the per-pickup cap.
        public var footnote: String?
        /// Progress after this pickup, e.g. "After this pickup: 1.7 of 5 mi · 3.3 mi to go".
        public var outcome: String?
        /// Shown when the pickup reaches a milestone, e.g. "Unlocks a reward: 50% off one bag".
        public var unlock: String?

        public init(
            title: String, detail: String, footnote: String? = nil, outcome: String? = nil, unlock: String? = nil
        ) {
            self.title = title
            self.detail = detail
            self.footnote = footnote
            self.outcome = outcome
            self.unlock = unlock
        }
    }

    let content: Content

    public init(_ content: Content) {
        self.content = content
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "figure.walk")
                .font(.title3)
                .foregroundStyle(Color.splashTeal)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.title).font(.subheadline.weight(.semibold))
                Text(content.detail).font(.footnote).foregroundStyle(.secondary)
                if let outcome = content.outcome {
                    Text(outcome).font(.footnote.weight(.semibold)).foregroundStyle(Color.splashTeal).padding(.top, 2)
                }
                if let unlock = content.unlock {
                    Label(unlock, systemImage: "gift.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.splashTeal)
                }
                if let footnote = content.footnote {
                    Text(footnote).font(.caption).foregroundStyle(.secondary).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.yolk.opacity(0.2), in: RoundedRectangle(cornerRadius: Radius.panel))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") {
    WalkRewardCard(PreviewSamples.walkCard).padding()
}

#Preview("Dark") {
    WalkRewardCard(PreviewSamples.walkCard).padding().preferredColorScheme(.dark)
}

#Preview("Large text") {
    WalkRewardCard(PreviewSamples.walkCard).padding().dynamicTypeSize(.accessibility3)
}
