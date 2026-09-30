//
//  RewardBanner.swift
//  WalkAndTakeKit
//

import SwiftUI

/// The "Reward redeemed" announcement. It pops in with a spring, the gift bounces with a small burst of
/// confetti, and a success haptic plays. With Reduce Motion on it simply appears.
public struct RewardBanner: View {
    let title: String
    let detail: String
    let footer: String
    /// False shows the finished banner at once (previews, snapshots).
    let animated: Bool

    @State private var shown: Bool
    @State private var confettiLaunched = false
    @State private var confettiSpread = false
    @State private var glowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(title: String, detail: String, footer: String, animated: Bool = true) {
        self.title = title
        self.detail = detail
        self.footer = footer
        self.animated = animated
        _shown = State(initialValue: !animated)
    }

    private var playsMotion: Bool { animated && !reduceMotion }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: Spacing.s) {
                gift
                Text(title).font(.headline).foregroundStyle(.black)
            }
            Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(.black)
            Text(footer).font(.footnote).foregroundStyle(.black.opacity(0.75))
        }
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yolk, in: RoundedRectangle(cornerRadius: Radius.panel))
        .scaleEffect(shown ? 1 : 0.82, anchor: .leading)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 18)
        .animation(playsMotion ? .spring(response: 0.5, dampingFraction: 0.5) : nil, value: shown)
        // A glow that flares as the banner lands and fades.
        .shadow(color: Color.yolk.opacity(glowing ? 0 : 0.9), radius: glowing ? 34 : 4)
        .animation(playsMotion ? .easeOut(duration: 0.9) : nil, value: glowing)
        .sensoryFeedback(.success, trigger: shown) { _, now in now && playsMotion }
        .task { await reveal() }
    }

    private var gift: some View {
        Image(systemName: "gift.fill")
            .font(.title3)
            .foregroundStyle(.black)
            .symbolEffect(.bounce, options: .repeat(2), value: playsMotion ? shown : false)
            .background { confetti }
            .accessibilityHidden(true)
    }

    /// Fourteen dots fly out from the gift and fade.
    private static let confettiColors: [Color] = [.splashTeal, .orange, .black, .red]
    private static let confettiCount = 14
    /// Side of each confetti square, in points.
    private static let confettiSize: CGFloat = 10.8

    private var confetti: some View {
        ZStack {
            ForEach(0..<Self.confettiCount, id: \.self) { index in
                let angle = Double(index) / Double(Self.confettiCount) * 2 * .pi
                let reach: Double = index.isMultiple(of: 2) ? 74 : 52
                RoundedRectangle(cornerRadius: 2)
                    .fill(Self.confettiColors[index % Self.confettiColors.count])
                    .frame(width: Self.confettiSize, height: Self.confettiSize)
                    .rotationEffect(.degrees(confettiSpread ? Double(index) * 70 : 0))
                    .offset(
                        x: confettiSpread ? cos(angle) * reach : 0,
                        y: confettiSpread ? sin(angle) * reach : 0
                    )
                    .scaleEffect(confettiSpread ? 0.4 : 1)
                    .opacity(confettiLaunched ? (confettiSpread ? 0 : 1) : 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Waits for the sheet to finish sliding up so the pop is seen, then plays.
    private func reveal() async {
        guard animated, !shown else { return }
        guard playsMotion else {
            shown = true
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        shown = true
        try? await Task.sleep(for: .milliseconds(120))
        confettiLaunched = true
        glowing = true
        withAnimation(.easeOut(duration: 0.9)) { confettiSpread = true }
    }
}

#Preview("Animated") {
    RewardBanner(
        title: "Reward redeemed", detail: "50% off one bag saved you $2.74.",
        footer: "That was your last reward. Keep walking to earn the next one."
    )
    .padding()
}

#Preview("Finished, dark") {
    RewardBanner(
        title: "Reward redeemed", detail: "50% off one bag saved you $2.74.",
        footer: "1 more reward is ready to use.", animated: false
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Large text") {
    RewardBanner(
        title: "Reward redeemed", detail: "50% off one bag saved you $2.74.",
        footer: "That was your last reward. Keep walking to earn the next one.", animated: false
    )
    .padding()
    .dynamicTypeSize(.accessibility2)
}
