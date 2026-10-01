//
//  DiscoverView.swift
//  WalkAndTakeKit
//

import DesignSystem
import Domain
import Platform
import SwiftUI
import UIKit

public struct DiscoverView<Destination: View>: View {
    @Bindable var model: DiscoverModel
    @Bindable var navigation: CustomerNavigation
    let destination: (DiscoverRoute) -> Destination

    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        model: DiscoverModel,
        navigation: CustomerNavigation,
        @ViewBuilder destination: @escaping (DiscoverRoute) -> Destination
    ) {
        self.model = model
        self.navigation = navigation
        self.destination = destination
    }

    public var body: some View {
        NavigationStack(path: $navigation.discoverPath) {
            Group {
                switch model.mode {
                case .list: list
                case .map:
                    MapBrowseView(model: model.map) { navigation.discoverPath.append(.offer(id: $0)) }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if model.developer.usesDemoControls {
                    DemoMenuButton(title: "Demo · jump to", actions: demoActions).padding(Spacing.l)
                }
            }
            .navigationTitle(model.mode == .map ? "Map" : "Discover")
            .navigationBarTitleDisplayMode(model.mode == .map ? .inline : .automatic)
            .toolbar {
                if model.showsMapToggle {
                    Button {
                        withAnimation { model.mode = model.mode == .list ? .map : .list }
                    } label: {
                        model.mode == .list
                            ? Label("Map", systemImage: "map") : Label("List", systemImage: "list.bullet")
                    }
                }
            }
            .navigationDestination(for: DiscoverRoute.self, destination: destination)
        }
        .tint(.splashTeal)
        .task { await model.run() }
    }

    /// Developer mode: jump the clock to when bags open, or back to now.
    private var demoActions: [DemoAction] {
        var actions = model.demoTimeJumps.map { jump in
            DemoAction(jump.title, systemImage: "clock") { model.demoTravel(to: jump.date) }
        }
        if model.demoCanResetTime {
            actions.append(
                DemoAction("Back to live time", systemImage: "clock.arrow.circlepath") { model.demoResetTime() })
        }
        return actions
    }

    // MARK: - List

    @ViewBuilder
    private var list: some View {
        switch model.state {
        case .loading:
            LoadingView("Finding bags near you…")
        case .failed(let message):
            EmptyStateView(
                "Something went wrong", systemImage: "exclamationmark.triangle", message: message,
                actionTitle: "Try again"
            ) { Task { await model.retry() } }
        case .loaded, .empty:
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    DiscoverHeaderView(header: model.header)
                    if let reason = model.fallbackReason {
                        LocationBanner(reason: reason) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    }
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        CategoryChips(selection: $model.category)
                        sortPicker
                    }

                    if model.isListEmpty {
                        EmptyStateView(
                            "No bags right now", systemImage: "bag",
                            message: "Check back soon. Stores add bags throughout the morning."
                        )
                        .padding(.top, Spacing.xxl)
                    } else {
                        sections
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xxl)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    /// Segmented normally; a menu at accessibility text sizes, where four segments would truncate.
    @ViewBuilder
    private var sortPicker: some View {
        let picker = Picker("Sort", selection: $model.sort) {
            ForEach(model.availableSorts) { Text($0.rawValue).tag($0) }
        }
        if dynamicTypeSize.isAccessibilitySize {
            HStack {
                Text("Sort").foregroundStyle(.secondary)
                picker.pickerStyle(.menu)
            }
        } else {
            picker.pickerStyle(.segmented)
        }
    }

    private var sections: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(model.sections) { section in
                if let title = section.title {
                    DayLabel(title, day: section.kind == .tonight ? .tonight : .tomorrow)
                        .padding(.top, section.kind == .tonight ? 0 : Spacing.xs)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(section.items) { item in
                    NavigationLink(value: DiscoverRoute.offer(id: item.offerID)) {
                        BagCard(
                            item.card, isFavorite: item.isFavorite,
                            onToggleFavorite: model.showsFavoriteButtons
                                ? { Task { await model.toggleFavorite(restaurantID: item.restaurantID) } } : nil
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("discover.bagCard")
                }
            }
        }
    }
}

private struct DiscoverHeaderView: View {
    let header: DiscoverHeader

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let name = header.greetingName {
                Text("Good morning, \(name)")
                    .font(.title3.weight(.semibold))
            }
            Label("Near you · \(header.homeArea)", systemImage: "location.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.splashTeal)
            Text("\(header.availableCount) bags to rescue within \(header.maxDistanceText) mi")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if header.hiddenByPreferencesCount > 0 {
                Text("\(header.hiddenByPreferencesCount) more hidden by \(header.hiddenReasonText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
