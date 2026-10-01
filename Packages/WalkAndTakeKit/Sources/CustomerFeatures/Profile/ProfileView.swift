//
//  ProfileView.swift
//  WalkAndTakeKit
//

import DesignSystem
import Domain
import Platform
import SwiftUI

public struct ProfileView: View {
    @Bindable var model: ProfileModel
    @Bindable var navigation: CustomerNavigation

    public init(model: ProfileModel, navigation: CustomerNavigation) {
        self.model = model
        self.navigation = navigation
    }

    public var body: some View {
        NavigationStack(path: $navigation.profilePath) {
            Group {
                switch model.state {
                // The form shows at once; values fill in a moment later, so there's no spinner flash.
                case .loading: form
                case .failed(let message):
                    EmptyStateView(
                        "Something went wrong", systemImage: "exclamationmark.triangle", message: message,
                        actionTitle: "Try again"
                    ) { Task { await model.load() } }
                case .loaded: form
                }
            }
            .navigationTitle("Profile")
            .navigationDestination(for: ProfileRoute.self) { route in
                switch route {
                case .walkHistory: WalkHistoryView(model: model.makeWalkHistory())
                case .rewards: RewardsListView(model: model.makeRewardsList())
                case .timeTravel: TimeTravelView(demo: model.demo)
                case .seedMap: SeedMapView(offers: model.offers)
                }
            }
        }
        .tint(.splashTeal)
        .task { await model.run() }
    }

    private var form: some View {
        Form {
            if let walkProgress = model.walkProgress {
                if let unlock = model.rewardUnlock {
                    Section {
                        RewardBanner(title: unlock.title, detail: unlock.detail, footer: unlock.footer)
                            .id(unlock.id)  // a new unlock plays the animation again
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .accessibilityIdentifier("profile.rewardUnlocked")
                    }
                }
                Section {
                    WalkProgressCard(walkProgress) { navigation.profilePath.append(.rewards) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("profile.walkProgress")
                } header: {
                    Text("Walking rewards")
                }
                // Its own section, so the links get rounded corners and a gap under the card.
                Section {
                    // With rewards ready, the card's button opens the list; otherwise this row does.
                    if walkProgress.readyText == nil {
                        NavigationLink(value: ProfileRoute.rewards) {
                            Label("Rewards", systemImage: "gift")
                        }
                        .accessibilityIdentifier("profile.rewards")
                    }
                    NavigationLink(value: ProfileRoute.walkHistory) {
                        Label("Walk history", systemImage: "list.bullet.rectangle")
                    }
                    .accessibilityIdentifier("profile.walkHistory")
                } footer: {
                    Text(
                        "Miles count from pickups you walk to. One pickup adds up to "
                            + "\(WalkCopy.milestone(WalkRewardLadder.maxMilesPerPickup)) mi. Use a reward when you reserve."
                    )
                }
            }

            if model.showsImpact {
                Section {
                    ImpactCard(impact: model.impact)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Your impact")
                }
            }

            Section("About you") {
                TextField("Your name", text: $model.preferences.name)
                    .textContentType(.givenName)
                LabeledContent("Home area") {
                    TextField("Neighborhood", text: $model.preferences.homeArea)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Picker("Max distance", selection: $model.preferences.maxDistanceMiles) {
                    ForEach(model.distanceOptions, id: \.self) { Text(model.distanceLabel($0)).tag($0) }
                }
            } header: {
                Text("Distance")
            } footer: {
                Text("Discover hides bags farther than this from you.")
            }

            if model.showsDietary { dietarySection }
            if model.showsCommute { CommuteSection(model: model) }
            developerSection
        }
        .animation(.spring(duration: 0.4), value: model.rewardUnlock)
        .overlay(alignment: .bottomTrailing) {
            if model.developer.usesDemoControls, model.showsWalkProgress {
                DemoMenuButton(title: "Demo · walking rewards", actions: rewardActions)
                    .padding(Spacing.l)
            }
        }
        .confirmationDialog(
            "Clear all walks and rewards?", isPresented: $model.confirmingClearRewards, titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) { Task { await model.demoClearWalksAndRewards() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Miles go back to zero and every reward is removed. Orders and bags stay.")
        }
    }

    // MARK: Developer mode: rewards

    private var rewardActions: [DemoAction] {
        [
            DemoAction("+0.5 mi", systemImage: "plus") { Task { await model.demoAddMiles(0.5) } },
            DemoAction("+1 mi", systemImage: "plus") { Task { await model.demoAddMiles(1) } },
            DemoAction("Complete milestone", systemImage: "flag.checkered") {
                Task { await model.demoCompleteMilestone() }
            },
            DemoAction("Grant a reward", systemImage: "gift") { Task { await model.demoGrantReward() } },
        ]
    }

    private var dietarySection: some View {
        Section {
            ForEach(DietaryTag.allCases) { tag in
                Toggle(
                    isOn: Binding(
                        get: { model.preferences.dietary.contains(tag) },
                        set: { model.setDietary(tag, $0) })
                ) {
                    Label(tag.label, systemImage: tag.symbol)
                }
            }
        } header: {
            Text("Dietary preferences")
        } footer: {
            Text(
                "Discover only shows bags that fit every preference you turn on. "
                    + "Surprise bags vary, so check with the store if you have an allergy.")
        }
    }

    /// Developer mode, last on the screen in every build. Its tools expand under the switch while it's on.
    private var developerSection: some View {
        Section {
            Toggle(
                isOn: Binding(get: { model.developer.isOn }, set: { model.setDeveloperMode($0) }).animation()
            ) {
                Label("Developer mode", systemImage: "hammer")
            }
            .accessibilityIdentifier("profile.developerMode")
            if model.developer.isOn {
                Toggle(isOn: Bindable(model.developer).showsDemoControls) {
                    Label("Show demo controls", systemImage: "wand.and.stars")
                }
                .accessibilityIdentifier("developer.showsDemoControls")
                Toggle(isOn: Bindable(model.developer).fixedLocation) {
                    Label("Fixed location", systemImage: "location.fill")
                }
                .accessibilityIdentifier("developer.fixedLocation")
                Toggle(isOn: Bindable(model.developer).simulatedWalks) {
                    Label("Simulated walks", systemImage: "figure.walk.motion")
                }
                .accessibilityIdentifier("developer.simulatedWalks")
                if model.developer.simulatedWalks {
                    Picker(selection: Bindable(model.developer).autoWalkSeconds) {
                        ForEach(DeveloperSettings.autoWalkOptions, id: \.self) { Text("\($0) s").tag($0) }
                    } label: {
                        Label("Auto-walk takes", systemImage: "timer")
                    }
                }
                NavigationLink(value: ProfileRoute.timeTravel) {
                    Label("Time travel", systemImage: "clock.arrow.2.circlepath")
                }
                NavigationLink(value: ProfileRoute.seedMap) {
                    Label("Seed map", systemImage: "map")
                }
                Button(role: .destructive) {
                    model.confirmingClearRewards = true
                } label: {
                    Label("Clear walks & rewards", systemImage: "figure.walk.departure")
                }
                .accessibilityIdentifier("developer.clearWalksAndRewards")
                resetButton
            }
        } header: {
            Text("Developer")
        } footer: {
            Text(
                model.developer.isOn
                    ? "The Demo button on Profile and on orders steps walks, adds miles and unlocks rewards. "
                        + "Fixed location puts you at the center of Long Island City. Simulated walks follow a "
                        + "straight route to the store. Clear walks & rewards zeroes your miles and rewards; "
                        + "Reset demo data starts the whole app over. Turning Developer mode off puts every "
                        + "setting here back to normal."
                    : "Shows demo tools for walking through the app: time travel, a fixed location and demo data.")
        }
    }

    private var resetButton: some View {
        Button(role: .destructive) {
            model.confirmingReset = true
        } label: {
            HStack {
                Label("Reset demo data", systemImage: "arrow.counterclockwise")
                if model.isResetting {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(model.isResetting)
        .confirmationDialog(
            "Reset all demo data?", isPresented: $model.confirmingReset, titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) { Task { await model.resetDemoData() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Orders, ratings, favorites and preferences will be erased and today's bags restocked.")
        }
        .alert("Reset didn't finish", isPresented: $model.resetFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please try again.")
        }
    }
}

/// "Morning commute" (behind the commute flag).
private struct CommuteSection: View {
    @Bindable var model: ProfileModel

    var body: some View {
        Section {
            DatePicker("Leave home", selection: time(\.leaveMinutes), displayedComponents: .hourAndMinute)
            DatePicker("Arrive at work", selection: time(\.arriveMinutes), displayedComponents: .hourAndMinute)

            VStack(alignment: .leading, spacing: Spacing.s) {
                Text("Commute days")
                WeekdayPicker(selection: $model.commute.commuteDays, calendar: NYCalendar.calendar)
            }
            .padding(.vertical, 4)

            Picker("Getting there", selection: $model.commute.travelMode) {
                ForEach(TravelMode.allCases) { mode in
                    Label(mode.label, systemImage: mode.symbol).tag(mode)
                }
            }
        } header: {
            Text("Morning commute")
        } footer: {
            if model.commute.isValid {
                Text("Bags you can pick up during your commute get a “Fits your commute” tag in Discover.")
            } else {
                Label(
                    "Your arrival time needs to be after you leave home.", systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.red)
            }
        }
        .environment(\.timeZone, NYCalendar.timeZone)
    }

    /// Bridges minutes-after-midnight (New York) to a Date for the time pickers.
    private func time(_ keyPath: WritableKeyPath<CommuteProfile, Int>) -> Binding<Date> {
        Binding {
            model.time(forMinutes: model.commute[keyPath: keyPath])
        } set: { date in
            model.commute[keyPath: keyPath] = model.minutes(from: date)
        }
    }
}
