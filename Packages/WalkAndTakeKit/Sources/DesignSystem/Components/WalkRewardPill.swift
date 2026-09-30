//
//  WalkRewardPill.swift
//  WalkAndTakeKit
//

import SwiftUI

/// Small capsule on a bag: how many walking miles the pickup would add, e.g. "+0.7 mi toward a reward".
public struct WalkRewardPill: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Label(text, systemImage: "figure.walk")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.splashTeal)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.yolk.opacity(0.35), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Light") {
    WalkRewardPill("+0.7 mi toward a reward").padding()
}

#Preview("Dark") {
    WalkRewardPill("+0.7 mi toward a reward").padding().preferredColorScheme(.dark)
}

#Preview("Large text") {
    WalkRewardPill("+0.7 mi toward a reward").padding().dynamicTypeSize(.accessibility3)
}
