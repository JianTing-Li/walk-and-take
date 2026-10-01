//
//  MilestoneProgressBar.swift
//  WalkAndTakeKit
//

import SwiftUI

/// A thick progress bar with tick marks. The fill slides to new values, and each tick lights up once the
/// fill passes it, so progress visibly "ticks" forward.
public struct MilestoneProgressBar: View {
    let value: Double
    let ticks: [Double]
    let fill: Color
    let track: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - value: 0...1 (clamped).
    ///   - ticks: Positions of the tick marks, 0...1. Ends are ignored.
    public init(value: Double, ticks: [Double] = [], fill: Color, track: Color) {
        self.value = min(1, max(0, value))
        self.ticks = ticks.filter { $0 > 0 && $0 < 1 }
        self.fill = fill
        self.track = track
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: value > 0 ? max(Self.height, width * value) : 0)
                ForEach(ticks, id: \.self) { tick in
                    Capsule()
                        .fill(tick <= value ? Color.white.opacity(0.9) : fill.opacity(0.35))
                        .frame(width: 2, height: Self.height - 4)
                        .offset(x: width * tick - 1)
                }
            }
        }
        .frame(height: Self.height)
        .animation(reduceMotion ? nil : .spring(duration: 0.6, bounce: 0.25), value: value)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((value * 100).rounded())) percent"))
    }

    static let height: CGFloat = 10

    /// Tick positions (0...1) every `step` between `start` and `end`, e.g. each whole mile between two
    /// milestones. At most `limit` ticks; the step doubles until they fit.
    public static func ticks(from start: Double, to end: Double, every step: Double, limit: Int = 20) -> [Double] {
        let span = end - start
        guard span > 0, step > 0 else { return [] }
        var step = step
        while span / step - 1 > Double(limit) { step *= 2 }
        let first = (start / step).rounded(.down) * step + step
        return stride(from: first, to: end - step * 1e-6, by: step).map { ($0 - start) / span }.filter { $0 > 1e-6 }
    }
}

#Preview("Light") {
    VStack(spacing: 20) {
        MilestoneProgressBar(
            value: 0.35, ticks: MilestoneProgressBar.ticks(from: 0, to: 0.7, every: 0.1), fill: .splashTeal,
            track: Color.splashTeal.opacity(0.15))
        MilestoneProgressBar(
            value: 0.4, ticks: MilestoneProgressBar.ticks(from: 5, to: 15, every: 1), fill: .yolk,
            track: .white.opacity(0.25)
        )
        .padding()
        .background(Color.splashTeal)
    }
    .padding()
}

#Preview("Dark") {
    MilestoneProgressBar(
        value: 0.6, ticks: MilestoneProgressBar.ticks(from: 0, to: 1, every: 0.1), fill: .splashTeal,
        track: Color.splashTeal.opacity(0.15)
    )
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("Large text") {
    MilestoneProgressBar(value: 0.6, fill: .splashTeal, track: Color.splashTeal.opacity(0.15))
        .padding()
        .dynamicTypeSize(.accessibility3)
}
