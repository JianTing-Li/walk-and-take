//
//  ProfileModel.swift
//  WalkAndTakeKit
//
//  User Journey 4: a customer sets their preferences (and, behind a flag,
//  their commute) so Discover shows bags that fit.
//

import DesignSystem
import Domain
import Foundation
import Observation
import Platform

@Observable
@MainActor
public final class ProfileModel {
    public enum State: Equatable {
        case loading, loaded
        case failed(String)
    }

    public private(set) var state: State = .loading
    public private(set) var impact = Impact()
    /// Lifetime miles walked to pickups, and the rewards banked so far.
    public private(set) var walkMiles = 0.0
    public private(set) var rewards: [Reward] = []

    /// Edits save as they happen.
    public var preferences = UserPreferences() {
        didSet {
            if isLoaded, preferences != oldValue {
                save { [preferences] in try await $0.updatePreferences(preferences) }
            }
        }
    }
    public var commute = CommuteProfile() {
        didSet { if isLoaded, commute != oldValue { save { [commute] in try await $0.updateCommuteProfile(commute) } } }
    }

    public var confirmingReset = false
    public private(set) var isResetting = false
    public var resetFailed = false

    /// The latest save, so tests can await it.
    @ObservationIgnored private(set) var pendingSave: Task<Void, Never>?
    @ObservationIgnored private var isLoaded = false
    private let dependencies: CustomerDependencies
    private let navigation: CustomerNavigation

    public init(dependencies: CustomerDependencies, navigation: CustomerNavigation) {
        self.dependencies = dependencies
        self.navigation = navigation
    }

    public var flags: FeatureFlags { dependencies.flags }
    public var showsImpact: Bool { flags.impact }
    public var showsDietary: Bool { flags.dietaryFilters }
    public var showsWalkProgress: Bool { flags.walkRewards }
    /// "Morning commute" section (commute flag, off by default).
    public var showsCommute: Bool { flags.commute }

    // MARK: - Lifecycle

    public func run() async {
        await load()
        let reservations = dependencies.reservations.changes()
        let userData = dependencies.preferences.changes()
        let walkChanges = dependencies.walkRewards.changes()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in reservations { await self.loadImpact() } }
            group.addTask { for await _ in walkChanges { await self.loadWalkRewards() } }
            // Only a reset replaces what's on screen; the customer's own edits aren't reloaded mid-typing.
            group.addTask { for await change in userData where change == .reset { await self.load() } }
        }
    }

    public func load() async {
        do {
            isLoaded = false
            preferences = try await dependencies.preferences.preferences()
            commute = try await dependencies.preferences.commuteProfile()
            isLoaded = true
            await loadImpact()
            await loadWalkRewards()
            state = .loaded
        } catch {
            state = .failed("Couldn't load your profile. Please try again.")
        }
    }

    private func loadImpact() async {
        if let reservations = try? await dependencies.reservations.reservations() {
            impact = ImpactCalculator.impact(of: reservations)
        }
    }

    private func loadWalkRewards() async {
        guard flags.walkRewards else { return }
        walkMiles = (try? await dependencies.walkRewards.totalMiles()) ?? walkMiles
        rewards = (try? await dependencies.walkRewards.rewards()) ?? rewards
    }

    private func save(_ write: @escaping @Sendable (any PreferencesRepository) async throws -> Void) {
        let repository = dependencies.preferences
        let previous = pendingSave
        pendingSave = Task {
            await previous?.value  // keep writes in order
            try? await write(repository)
        }
    }

    // MARK: - Actions

    public func setDietary(_ tag: DietaryTag, _ on: Bool) {
        if on { preferences.dietary.insert(tag) } else { preferences.dietary.remove(tag) }
    }

    /// Wipes everything back to fresh seed data and pops every tab to its root.
    public func resetDemoData() async {
        isResetting = true
        defer { isResetting = false }
        await pendingSave?.value
        do {
            try await dependencies.resetter.resetAll()
            navigation.popAllToRoot()
            await load()
        } catch {
            resetFailed = true
        }
    }

    // MARK: - Output

    /// Rewards banked and not yet used.
    public var availableRewards: Int { rewards.filter(\.isAvailable).count }

    /// Miles walked, how far to the next reward, and what's ready to use. Nil when the flag is off.
    public var walkProgress: WalkProgressCard.Content? {
        guard flags.walkRewards else { return nil }
        let next = WalkRewardLadder.nextMilestone(after: walkMiles)
        let discount = "\(WalkRewardLadder.discountPercent)% off one bag"
        let ready = availableRewards
        return WalkProgressCard.Content(
            milesText: "\(WalkCopy.miles(walkMiles)) mi",
            milesCaption: "walked to pickups",
            progress: WalkRewardLadder.progressFraction(totalMiles: walkMiles),
            targetTitle: WalkRewardLadder.milestonesReached(totalMiles: walkMiles) == 0
                ? "First reward: \(discount) at \(WalkCopy.milestone(next)) mi"
                : "Next: \(discount) at \(WalkCopy.milestone(next)) mi",
            targetDetail: "\(WalkCopy.miles(WalkRewardLadder.milesToNext(totalMiles: walkMiles))) mi to go",
            readyText: ready == 0
                ? nil : ready == 1 ? "1 reward ready to use" : "\(ready) rewards ready to use")
    }

    public var distanceOptions: [Double] { UserPreferences.distanceOptions }

    public func distanceLabel(_ miles: Double) -> String {
        "\(miles.formatted(.number.precision(.fractionLength(0...2)))) mi"
    }

    /// The commute time pickers work in New York wall-clock time on today's date.
    public func time(forMinutes minutes: Int) -> Date {
        let today = NYCalendar.dayKey(for: dependencies.clock.now)
        return NYCalendar.date(on: today, hour: minutes / 60, minute: minutes % 60) ?? dependencies.clock.now
    }

    public func minutes(from date: Date) -> Int {
        let parts = NYCalendar.calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
