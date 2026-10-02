//
//  WalkProgressCard.swift
//  WalkAndTakeKit
//

import SwiftUI

/// Profile panel: total walked miles, progress to the next reward, and rewards ready to use.
public struct WalkProgressCard: View {
    public struct Content: Hashable, Sendable {
        /// e.g. "1.2 mi".
        public var milesText: String
        /// e.g. "walked to pickups".
        public var milesCaption: String
        /// From the last milestone to the next, 0...1.
        public var progress: Double
        /// Tick marks on the bar, 0...1 (e.g. each whole mile between the milestones).
        public var ticks: [Double]
        /// e.g. "Next: 50% off one bag at 5 mi".
        public var targetTitle: String
        /// e.g. "3.8 mi to go".
        public var targetDetail: String
        /// e.g. "1 reward ready to use". Nil when none are banked.
        public var readyText: String?

        public init(
            milesText: String, milesCaption: String, progress: Double, ticks: [Double] = [], targetTitle: String,
            targetDetail: String, readyText: String? = nil
        ) {
            self.milesText = milesText
            self.milesCaption = milesCaption
            self.progress = progress
            self.ticks = ticks
            self.targetTitle = targetTitle
            self.targetDetail = targetDetail
            self.readyText = readyText
        }
    }

    let content: Content
    /// Opens the rewards list from the "ready to use" button. Nil shows it as a plain label.
    let onReadyTap: (() -> Void)?

    public init(_ content: Content, onReadyTap: (() -> Void)? = nil) {
        self.content = content
        self.onReadyTap = onReadyTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Image(systemName: "figure.walk").foregroundStyle(Color.yolk)
                Text(content.milesText)
                    .font(.title.weight(.bold))
                    .contentTransition(.numericText())
                    .animation(.default, value: content.milesText)
                Text(content.milesCaption).font(.subheadline).opacity(0.85)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                MilestoneProgressBar(
                    value: content.progress, ticks: content.ticks, fill: .yolk, track: .white.opacity(0.25)
                )
                .accessibilityHidden(true)
                .padding(.vertical, 2)
                Text(content.targetTitle).font(.subheadline.weight(.semibold))
                Text(content.targetDetail).font(.footnote).opacity(0.85)
            }

            if let readyText = content.readyText {
                if let onReadyTap {
                    Button(action: onReadyTap) { readyLabel(readyText, chevron: true) }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens your rewards")
                } else {
                    readyLabel(readyText, chevron: false)
                }
            }
        }
        .padding(Spacing.l)
        .foregroundStyle(.white)
        .background(Color.splashTeal, in: RoundedRectangle(cornerRadius: Radius.card))
        .accessibilityElement(children: .contain)
    }

    private func readyLabel(_ text: String, chevron: Bool) -> some View {
        HStack {
            Label(text, systemImage: "gift.fill")
            Spacer(minLength: 0)
            if chevron { Image(systemName: "chevron.right").font(.footnote.weight(.bold)) }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.black)
        .padding(.horizontal, Spacing.m).padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yolk, in: RoundedRectangle(cornerRadius: Radius.tile))
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile))
    }
}

#Preview("Light") {
    VStack(spacing: 14) {
        WalkProgressCard(PreviewSamples.walkProgress) {}
        WalkProgressCard(PreviewSamples.walkProgressNew)
    }
    .padding()
}

#Preview("Dark") {
    WalkProgressCard(PreviewSamples.walkProgress).padding().preferredColorScheme(.dark)
}

#Preview("Large text") {
    WalkProgressCard(PreviewSamples.walkProgress).padding().dynamicTypeSize(.accessibility2)
}
