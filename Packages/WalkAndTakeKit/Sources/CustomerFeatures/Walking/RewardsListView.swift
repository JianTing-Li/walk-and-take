//
//  RewardsListView.swift
//  WalkAndTakeKit
//

import DesignSystem
import SwiftUI

struct RewardsListView: View {
    @State private var model: RewardsListModel

    init(model: RewardsListModel) {
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
                    EmptyStateView("No rewards yet", systemImage: "gift", message: model.emptyMessage)
                } else {
                    list
                }
            }
        }
        .navigationTitle("Rewards")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.run() }
    }

    private var list: some View {
        List {
            if !model.ready.isEmpty {
                Section {
                    ForEach(model.ready) { row in
                        rewardRow(row, symbol: "gift.fill", tint: .yolk)
                    }
                } header: {
                    Text("Ready to use")
                } footer: {
                    Text("Turn one on when you reserve. Each reservation can use one.")
                }
            }
            if !model.used.isEmpty {
                Section("Used") {
                    ForEach(model.used) { row in
                        rewardRow(row, symbol: "checkmark.circle.fill", tint: .secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("rewards.list")
    }

    private func rewardRow(_ row: RewardsListModel.Row, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline)
                Text(row.earnedText).font(.subheadline).foregroundStyle(.secondary)
                if let usedText = row.usedText {
                    Text(usedText).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
