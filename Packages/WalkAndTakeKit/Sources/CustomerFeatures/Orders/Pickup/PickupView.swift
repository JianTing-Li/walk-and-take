//
//  PickupView.swift
//  WalkAndTakeKit
//

import DesignSystem
import Domain
import Platform
import SwiftUI

struct PickupView<RateSheet: View>: View {
    @State private var model: PickupModel
    let rateSheet: (RateRequest) -> RateSheet

    init(model: PickupModel, @ViewBuilder rateSheet: @escaping (RateRequest) -> RateSheet) {
        _model = State(initialValue: model)
        self.rateSheet = rateSheet
    }

    var body: some View {
        Group {
            switch model.state {
            case .loading: LoadingView()
            case .notFound: EmptyStateView("Order not found", systemImage: "bag", message: "It may have been removed.")
            case .failed(let message):
                EmptyStateView(
                    "Something went wrong", systemImage: "exclamationmark.triangle", message: message,
                    actionTitle: "Try again"
                ) { Task { await model.load() } }
            case .loaded: content
            }
        }
        .navigationTitle(model.restaurantName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $model.rateRequest, content: rateSheet)
        .alert("Couldn't start your walk", isPresented: $model.walkFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
        .alert("Pickup couldn't be confirmed", isPresented: $model.collectFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can confirm pickup only while the pickup window is open.")
        }
        .task { await model.run() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                if let header = model.header { StatusHeader(header: header) }

                // Ready for pickup: the code goes first, right above the swipe.
                if model.status == .readyNow { PickupCodeCard(code: model.code) }

                if let section = model.walkSection { walkSection(section) }

                if model.isActive {
                    if model.status != .readyNow { PickupCodeCard(code: model.code) }
                    PickupSteps(
                        restaurantName: model.restaurantName, addressLine: model.addressLine,
                        instructions: model.pickupInstructions, directionsURL: model.directionsURL)
                    if model.canManage, let id = model.reservation?.id {
                        NavigationLink(value: OrdersRoute.manageOrder(reservationID: id)) {
                            Label("Change or cancel order", systemImage: "slider.horizontal.3")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.m)
                                .background(
                                    Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: Radius.panel))
                        }
                    } else if let text = model.changesClosedText {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                if model.status == .collected {
                    if let earned = model.walkEarned {
                        WalkEarnedCard(earned).accessibilityIdentifier("pickup.walkEarned")
                    }
                    RatingCard(
                        restaurantName: model.restaurantName, review: model.review, canReview: model.canReview
                    ) { model.rate(stars: $0) }
                    if let impact = model.impactText {
                        VStack(spacing: 6) {
                            Text("This order's impact").font(.headline)
                            Text(impact).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.l)
                        .background(
                            Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.card))
                    }
                }

                summary
            }
            .padding(Spacing.l)
        }
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .bottomTrailing) {
            if model.developer.usesDemoControls, model.isActive {
                DemoMenuButton(title: "Demo · this order", actions: demoActions)
                    .padding(Spacing.l)
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sensoryFeedback(.success, trigger: model.status == .collected)
    }

    @ViewBuilder
    private func walkSection(_ section: PickupModel.WalkSection) -> some View {
        switch section {
        case .opensLater(let text):
            Label(text, systemImage: "figure.walk")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(Spacing.m)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.panel))
        case .ready(let content):
            VStack(spacing: Spacing.m) {
                WalkRewardCard(content)
                Button {
                    Task { await model.startWalk() }
                } label: {
                    Label("Start walk", systemImage: "figure.walk")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.splashTeal)
                .disabled(model.isStartingWalk)
                .accessibilityIdentifier("pickup.startWalk")
            }
        case .walking(let walking):
            WalkingCard(walking: walking)
        }
    }

    // MARK: Developer mode

    private var startNowAction: DemoAction {
        DemoAction("Start walk now", systemImage: "figure.walk") { Task { await model.startWalkNow() } }
    }

    private func walkActions(_ isAutoWalking: Bool) -> [DemoAction] {
        [
            DemoAction("+0.1 mi", systemImage: "plus") { Task { await model.demoStep() } },
            isAutoWalking
                ? DemoAction("Pause", systemImage: "pause.fill") { Task { await model.demoToggleAutoWalk() } }
                : DemoAction("Auto-walk", systemImage: "play.fill") { Task { await model.demoToggleAutoWalk() } },
            DemoAction("Arrive now", systemImage: "flag.checkered") { Task { await model.demoArrive() } },
        ]
    }

    /// What the Demo button can do on this order right now: the walk first, then the clock.
    private var demoActions: [DemoAction] {
        var actions: [DemoAction] = []
        switch model.demoWalkControls {
        case .startNow: actions.append(startNowAction)
        case .simulated(let isAutoWalking, false): actions += walkActions(isAutoWalking)
        default: break
        }
        if model.isActive {
            actions.append(
                DemoAction("Send pickup reminder", systemImage: "bell.badge") {
                    Task { await model.demoSendReminder() }
                })
            actions.append(
                DemoAction("Confirm pickup now", systemImage: "checkmark.seal") {
                    Task { await model.demoConfirmPickup() }
                })
        }
        if model.canOpenPickupNow {
            actions.append(
                DemoAction("Open pickup now", systemImage: "clock.badge.checkmark") { model.openPickupNow() })
        }
        if model.canJumpToClosing {
            actions.append(
                DemoAction("Jump to 5 min before pickup ends", systemImage: "hourglass.bottomhalf.filled") {
                    model.jumpToClosing()
                })
        }
        return actions
    }

    @ViewBuilder
    private var bottomBar: some View {
        if model.status == .readyNow {
            SwipeToConfirm(title: "Swipe to confirm pickup") { Task { await model.collect() } }
                .id(model.collectFailed)  // a failed confirm resets the knob so you can try again
                .padding(Spacing.l)
                .background(.bar)
        }
    }

    private var summary: some View {
        VStack(spacing: Spacing.s) {
            ForEach(model.summary, id: \.label) { row in
                SummaryRow(row.label, row.value)
            }
        }
        .padding(Spacing.l)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Radius.card))
    }
}

private struct StatusHeader: View {
    let header: PickupModel.Header

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: header.symbol)
                .font(.system(size: 52))
                .foregroundStyle(header.tone.headerColor)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Text(header.title).font(.title2.weight(.bold)).multilineTextAlignment(.center)
            Text(header.subtitle).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
}

extension PickupStatusPill.Tone {
    fileprivate var headerColor: Color {
        switch self {
        case .readyNow: .splashTeal
        case .upcoming: .orange
        case .collected: .splashTeal
        case .inactive: .secondary
        }
    }
}

/// The walk card while recording. Shrinks to one line once you're at the door and can confirm.
private struct WalkingCard: View {
    let walking: PickupModel.WalkSection.Walking

    var body: some View {
        Group {
            if walking.phase == .arrived {
                Label(walking.title, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.splashTeal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Spacing.m)
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label(
                        walking.title,
                        systemImage: walking.phase == .arrivedEarly ? "checkmark.circle.fill" : "figure.walk.motion"
                    )
                    .font(.headline)
                    .foregroundStyle(Color.splashTeal)
                    MilestoneProgressBar(
                        value: walking.fraction, ticks: walking.ticks, fill: .splashTeal,
                        track: Color.splashTeal.opacity(0.15)
                    )
                    .padding(.vertical, Spacing.xxs)
                    Text(walking.progressText)
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())
                        .accessibilityIdentifier("pickup.walkProgress")
                    if let detail = walking.detail {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let warning = walking.warning {
                        Label(warning, systemImage: "location.slash.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.l)
            }
        }
        .background(Color.yolk.opacity(0.25), in: RoundedRectangle(cornerRadius: Radius.panel))
        .animation(.default, value: walking)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pickup.walkInProgress")
    }
}
