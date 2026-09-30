//
//  WalkEarnedCard.swift
//  WalkAndTakeKit
//

import SwiftUI

/// After a walked pickup: the miles earned, a catchphrase, the running total, and any reward unlocked.
public struct WalkEarnedCard: View {
    public struct Content: Hashable, Sendable {
        /// e.g. "+0.50 mi earned".
        public var headline: String
        /// One of the rotating lines, e.g. "Walk it. Earn it.".
        public var catchphrase: String
        /// e.g. "Walked pickup #3 · added 0.50 mi".
        public var contribution: String
        /// e.g. "1.70 mi walked in total · 3.30 mi to your next reward".
        public var progress: String
        /// e.g. "Reward unlocked: 50% off one bag". Nil when no milestone was reached.
        public var unlock: String?

        public init(
            headline: String, catchphrase: String, contribution: String, progress: String, unlock: String? = nil
        ) {
            self.headline = headline
            self.catchphrase = catchphrase
            self.contribution = contribution
            self.progress = progress
            self.unlock = unlock
        }
    }

    let content: Content

    public init(_ content: Content) {
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "figure.walk.circle.fill").font(.title2).foregroundStyle(Color.yolk)
                Text(content.headline).font(.title2.weight(.bold))
            }
            Text(content.catchphrase).font(.headline).foregroundStyle(Color.yolk)
            Text(content.contribution).font(.subheadline).opacity(0.9)
            Text(content.progress).font(.footnote).opacity(0.85)
            if let unlock = content.unlock {
                Label(unlock, systemImage: "gift.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yolk, in: RoundedRectangle(cornerRadius: Radius.tile))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .foregroundStyle(.white)
        .background(Color.splashTeal, in: RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Light") {
    VStack(spacing: 14) {
        WalkEarnedCard(PreviewSamples.walkEarned)
        WalkEarnedCard(PreviewSamples.walkEarnedUnlock)
    }
    .padding()
}

#Preview("Dark") {
    WalkEarnedCard(PreviewSamples.walkEarnedUnlock).padding().preferredColorScheme(.dark)
}

#Preview("Large text") {
    WalkEarnedCard(PreviewSamples.walkEarnedUnlock).padding().dynamicTypeSize(.accessibility2)
}
