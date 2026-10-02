//
//  DemoControls.swift
//  WalkAndTakeKit
//
//  Developer mode's floating "Demo" button. It's the only demo UI on a screen, so everything else
//  looks exactly as customers see it. It opens a compact menu above the button, which leaves the
//  screen visible while an action plays out (e.g. the walk bar moving).
//

import SwiftUI

/// One demo action.
public struct DemoAction: Identifiable {
    public var id: String { title }
    public let title: String
    public let systemImage: String
    public let action: () -> Void

    public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

/// The floating "Demo" button. Hidden when there's nothing to do.
public struct DemoMenuButton: View {
    let title: String
    let actions: [DemoAction]

    /// - Parameter title: Heads the menu, e.g. "Demo · this order".
    public init(title: String, actions: [DemoAction]) {
        self.title = title
        self.actions = actions
    }

    public var body: some View {
        if !actions.isEmpty {
            Menu {
                Section(title) {
                    ForEach(actions) { action in
                        Button(action: action.action) {
                            Label(action.title, systemImage: action.systemImage)
                        }
                        .accessibilityIdentifier("demo.\(action.title)")
                    }
                }
            } label: {
                Label("Demo", systemImage: "wand.and.stars")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.splashTeal, in: Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            .menuOrder(.fixed)
            .accessibilityLabel("Demo actions")
            .accessibilityIdentifier("demo.menu")
        }
    }
}

#Preview("Light") {
    DemoMenuButton(
        title: "Demo · this order",
        actions: [
            DemoAction("+0.1 mi", systemImage: "plus") {},
            DemoAction("Arrive now", systemImage: "flag.checkered") {},
        ]
    )
    .padding()
}

#Preview("Dark") {
    DemoMenuButton(title: "Demo", actions: [DemoAction("Arrive now", systemImage: "flag.checkered") {}])
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Large text") {
    DemoMenuButton(title: "Demo", actions: [DemoAction("Arrive now", systemImage: "flag.checkered") {}])
        .padding()
        .dynamicTypeSize(.accessibility3)
}
