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

        public init(title: String, detail: String, footnote: String? = nil) {
            self.title = title
            self.detail = detail
            self.footnote = footnote
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
