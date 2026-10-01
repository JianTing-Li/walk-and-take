//
//  DemoControls.swift
//  WalkAndTakeKit
//
//  Developer mode's demo controls: a dashed "DEMO" panel next to the feature it drives, and a
//  floating "Demo" button with every action for the screen. Screens show them only while
//  Developer mode is on, and the dashed look keeps them clearly apart from the real UI.
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

/// A dashed panel of demo buttons, placed under the feature it drives.
public struct DemoPanel: View {
    let note: String?
    let actions: [DemoAction]

    public init(note: String? = nil, actions: [DemoAction]) {
        self.note = note
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.xs) {
                DemoTag()
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !actions.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.xs) { buttons }
                    VStack(alignment: .leading, spacing: Spacing.xs) { buttons }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.m)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.panel)
                .strokeBorder(Color.splashTeal.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Demo controls")
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(actions) { action in
            Button(action: action.action) {
                Label(action.title, systemImage: action.systemImage)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.splashTeal)
            .accessibilityIdentifier("demo.\(action.title)")
        }
    }
}

/// The floating "Demo" button. Opens a sheet with every demo action for the screen.
public struct DemoSheetButton: View {
    let title: String
    let actions: [DemoAction]
    @State private var isPresented = false

    public init(title: String, actions: [DemoAction]) {
        self.title = title
        self.actions = actions
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Label("Demo", systemImage: "wand.and.stars")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.m)
                .padding(.vertical, Spacing.xs)
                .background(Color.splashTeal, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("demo.sheetButton")
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                List {
                    Section {
                        ForEach(actions) { action in
                            Button {
                                isPresented = false
                                action.action()
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                            }
                            .accessibilityIdentifier("demoSheet.\(action.title)")
                        }
                    } footer: {
                        Text("Developer mode only. Turn it off at the bottom of Profile.")
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isPresented = false }
                    }
                }
            }
            .tint(.splashTeal)
            .presentationDetents([.medium, .large])
        }
    }
}

/// The small "DEMO" tag that marks demo-only UI.
struct DemoTag: View {
    var body: some View {
        Text("DEMO")
            .font(.caption2.weight(.heavy))
            .tracking(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.splashTeal, in: Capsule())
            .accessibilityHidden(true)
    }
}

#Preview("Light") {
    VStack(spacing: 20) {
        DemoPanel(
            note: "Simulated walk",
            actions: [
                DemoAction("+0.1 mi", systemImage: "figure.walk") {},
                DemoAction("Pause", systemImage: "pause.fill") {},
                DemoAction("Arrive now", systemImage: "flag.checkered") {},
            ])
        DemoSheetButton(title: "Demo · this order", actions: [DemoAction("Open pickup now", systemImage: "clock") {}])
    }
    .padding()
}

#Preview("Dark") {
    DemoPanel(note: "Simulated walk", actions: [DemoAction("Arrive now", systemImage: "flag.checkered") {}])
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Large text") {
    DemoPanel(
        note: "Simulated walk",
        actions: [
            DemoAction("+0.1 mi", systemImage: "figure.walk") {},
            DemoAction("Arrive now", systemImage: "flag.checkered") {},
        ]
    )
    .padding()
    .dynamicTypeSize(.accessibility3)
}
