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
                case .loading: LoadingView()
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
                Section {
                    WalkProgressCard(walkProgress) { navigation.profilePath.append(.rewards) }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("profile.walkProgress")
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
                } header: {
                    Text("Walking rewards")
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
                resetButton
            }
        } header: {
            Text("Developer")
        } footer: {
            Text(
                model.developer.isOn
                    ? "Fixed location puts you at the center of Long Island City. Simulated walks follow a "
                        + "straight route to the store that you can step, pause or finish from the order screen. "
                        + "Reset demo data starts over "
                        + "with fresh bags from every store. Turning Developer mode off puts every setting here "
                        + "back to normal."
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
