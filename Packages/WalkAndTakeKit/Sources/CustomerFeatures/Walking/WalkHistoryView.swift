//
//  WalkHistoryView.swift
//  WalkAndTakeKit
//

import DesignSystem
import SwiftUI

struct WalkHistoryView: View {
    @State private var model: WalkHistoryModel

    init(model: WalkHistoryModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading: LoadingView()
            case .failed(let message):
                EmptyStateView(
                    "Something went wrong", systemImage: "exclamationmark.triangle", message: message,
                    actionTitle: "Try again"
                ) { Task { await model.load() } }
            case .loaded:
                if model.isEmpty {
                    EmptyStateView(
                        "No walks yet", systemImage: "figure.walk",
                        message: "Reserve a bag, tap Start walk on your order, and walk to pickup. It shows up here.")
                } else {
                    list
                }
            }
        }
        .navigationTitle("Walk history")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.run() }
    }

    private var list: some View {
        List {
            Section {
                ForEach(model.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.m) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.headline)
                            Text(row.dateText).font(.subheadline).foregroundStyle(.secondary)
                            Text(row.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: Spacing.s)
                        Text(row.milesText)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(row.earnedMiles ? Color.splashTeal : .secondary)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(model.summaryText)
            }
        }
        .accessibilityIdentifier("walkHistory.list")
    }
}
