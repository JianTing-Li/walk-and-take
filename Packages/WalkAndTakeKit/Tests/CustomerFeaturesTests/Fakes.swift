//
//  Fakes.swift
//  CustomerFeaturesTests
//
//  In-memory repositories, a scripted location, and fixture data for view-model tests.
//

import Domain
import Foundation
import Platform
import Synchronization

@testable import CustomerFeatures

nonisolated struct TestError: Error {}

/// Favorites + preferences fake.
nonisolated final class FakeUserData: FavoritesRepository, PreferencesRepository, Sendable {
    private struct State {
        var favorites: [FavoriteRestaurant] = []
        var preferences = UserPreferences()
        var commute = CommuteProfile()
    }

    private let state: Mutex<State>
    private let broadcaster = Broadcaster<UserDataChange>()

    init(preferences: UserPreferences = UserPreferences(), favorites: [FavoriteRestaurant] = []) {
        state = Mutex(State(favorites: favorites, preferences: preferences))
    }

    var favoriteIDs: [String] { state.withLock { $0.favorites.map(\.restaurantID) } }

    func favorites() async throws -> [FavoriteRestaurant] { state.withLock { $0.favorites } }
    func setFavorite(_ isFavorite: Bool, restaurantID: String) async throws {
        state.withLock { s in
            s.favorites.removeAll { $0.restaurantID == restaurantID }
            if isFavorite { s.favorites.append(FavoriteRestaurant(restaurantID: restaurantID, alertsEnabled: false)) }
        }
        broadcaster.send(.favoritesChanged)
    }
    func setAlerts(_ enabled: Bool, restaurantID: String) async throws {
        state.withLock { s in
            s.favorites.removeAll { $0.restaurantID == restaurantID }
            s.favorites.append(FavoriteRestaurant(restaurantID: restaurantID, alertsEnabled: enabled))
        }
        broadcaster.send(.favoritesChanged)
    }
    func preferences() async throws -> UserPreferences { state.withLock { $0.preferences } }
    func updatePreferences(_ preferences: UserPreferences) async throws {
        state.withLock { $0.preferences = preferences }
        broadcaster.send(.preferencesChanged)
    }
    func commuteProfile() async throws -> CommuteProfile { state.withLock { $0.commute } }
    func updateCommuteProfile(_ profile: CommuteProfile) async throws {
        state.withLock { $0.commute = profile }
        broadcaster.send(.commuteChanged)
    }
    func changes() -> AsyncStream<UserDataChange> { broadcaster.stream() }

    func wipe() {
        state.withLock { $0 = State() }
        broadcaster.send(.reset)
    }
}

/// Records walks without GPS; `finish` returns whatever a test scripted.
nonisolated final class FakeWalkTracker: WalkTracking, Sendable {
    private struct State {
        var active: Set<UUID> = []
        var locationOff = false
        var script: [WalkSample] = []
        var destinations: [UUID: Coordinate] = [:]
    }

    private let state = Mutex(State())

    /// The fixes every walk will have recorded.
    func script(_ samples: [WalkSample]) { state.withLock { $0.script = samples } }
    func setLocationOff(_ off: Bool) { state.withLock { $0.locationOff = off } }
    func isTracking(_ id: UUID) -> Bool { state.withLock { $0.active.contains(id) } }
    func destination(of id: UUID) -> Coordinate? { state.withLock { $0.destinations[id] } }

    func begin(reservationID: UUID, destination: Coordinate) async {
        state.withLock {
            $0.active.insert(reservationID)
            $0.destinations[reservationID] = destination
        }
    }
    func status(reservationID: UUID) async -> WalkTrackingStatus {
        state.withLock { s in s.active.contains(reservationID) ? (s.locationOff ? .locationOff : .tracking) : .idle }
    }
    func samples(reservationID: UUID) async -> [WalkSample] {
        state.withLock { $0.active.contains(reservationID) ? $0.script : [] }
    }
    func finish(reservationID: UUID) async -> [WalkSample] {
        state.withLock { s in
            guard s.active.remove(reservationID) != nil else { return [] }
            return s.script
        }
    }
}

/// In-memory walks and rewards that follow the same rules as the real store.
nonisolated final class FakeWalkRewards: WalkRewardsRepository, Sendable {
    private struct State {
        var walks: [Walk] = []
        var rewards: [Reward] = []
    }

    private let state = Mutex(State())
    private let broadcaster = Broadcaster<UserDataChange>()

    /// Seeds lifetime miles and banked rewards for a test.
    func seed(miles: Double = 0, rewards: [Reward] = []) {
        state.withLock { s in
            if miles > 0 {
                s.walks.append(
                    Walk(
                        reservationID: UUID(), restaurantID: "seed", startedAt: .distantPast, finishedAt: .distantPast,
                        creditedMiles: miles))
            }
            s.rewards = rewards
        }
    }

    func walks() async throws -> [Walk] { state.withLock { $0.walks } }
    func rewards() async throws -> [Reward] { state.withLock { $0.rewards } }
    func totalMiles() async throws -> Double { state.withLock { $0.walks.reduce(0) { $0 + $1.creditedMiles } } }
    func walk(reservationID: UUID) async throws -> Walk? {
        state.withLock { $0.walks.first { $0.reservationID == reservationID } }
    }

    func startWalk(reservationID: UUID, restaurantID: String, at now: Date) async throws -> Walk {
        let walk = state.withLock { s -> Walk in
            if let existing = s.walks.first(where: { $0.reservationID == reservationID }) { return existing }
            let walk = Walk(reservationID: reservationID, restaurantID: restaurantID, startedAt: now)
            s.walks.append(walk)
            return walk
        }
        broadcaster.send(.walkRewardsChanged)
        return walk
    }

    func finishWalk(
        reservationID: UUID, verdict: WalkVerdict, at now: Date, calendar: Calendar
    ) async throws -> WalkCompletion {
        let completion = try state.withLock { s -> WalkCompletion in
            guard let index = s.walks.firstIndex(where: { $0.reservationID == reservationID }) else {
                throw WalkRewardsError.walkNotFound
            }
            let before = s.walks.reduce(0) { $0 + $1.creditedMiles }
            if s.walks[index].finishedAt != nil {
                return WalkCompletion(walk: s.walks[index], newRewards: [], totalMiles: before)
            }
            var verdict = verdict
            let restaurantID = s.walks[index].restaurantID
            if case .credited = verdict,
                s.walks.contains(where: {
                    $0.restaurantID == restaurantID && $0.creditedMiles > 0
                        && ($0.finishedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
                })
            {
                verdict = .rejected(.repeatPickupToday)
            }
            s.walks[index].finishedAt = now
            s.walks[index].creditedMiles = verdict.creditedMiles
            if case .rejected(let reason) = verdict { s.walks[index].rejection = reason }
            let after = before + verdict.creditedMiles
            let rewards = WalkRewardLadder.milestonesCrossed(from: before, to: after)
                .map { Reward(milestoneMiles: $0, earnedAt: now) }
            s.rewards.append(contentsOf: rewards)
            return WalkCompletion(walk: s.walks[index], newRewards: rewards, totalMiles: after)
        }
        broadcaster.send(.walkRewardsChanged)
        return completion
    }

    func redeemReward(id: UUID, reservationID: UUID, at now: Date) async throws -> Reward {
        let reward = try state.withLock { s -> Reward in
            guard let index = s.rewards.firstIndex(where: { $0.id == id }) else {
                throw WalkRewardsError.rewardNotFound
            }
            guard s.rewards[index].redeemedAt == nil else { throw WalkRewardsError.rewardAlreadyRedeemed }
            s.rewards[index].redeemedAt = now
            s.rewards[index].redeemedReservationID = reservationID
            return s.rewards[index]
        }
        broadcaster.send(.walkRewardsChanged)
        return reward
    }

    /// Developer mode: a reward without miles.
    func bank(milestoneMiles: Double, at now: Date) -> Reward {
        let reward = Reward(milestoneMiles: milestoneMiles, earnedAt: now)
        state.withLock { $0.rewards.append(reward) }
        broadcaster.send(.walkRewardsChanged)
        return reward
    }

    /// Developer mode: finished walks and every reward gone.
    func clear() {
        state.withLock { s in
            s.walks.removeAll { $0.finishedAt != nil }
            s.rewards.removeAll()
        }
        broadcaster.send(.walkRewardsChanged)
    }

    func releaseReward(reservationID: UUID) async throws {
        state.withLock { s in
            for i in s.rewards.indices where s.rewards[i].redeemedReservationID == reservationID {
                s.rewards[i].redeemedAt = nil
                s.rewards[i].redeemedReservationID = nil
            }
        }
        broadcaster.send(.walkRewardsChanged)
    }

    func changes() -> AsyncStream<UserDataChange> { broadcaster.stream() }

    func wipe() {
        state.withLock { $0 = State() }
        broadcaster.send(.reset)
    }
}

/// Scripted permission answer; records previews.
nonisolated final class FakeNotifications: NotificationScheduler, Sendable {
    private let granted = Mutex(true)
    private let previews = Mutex<[String]>([])

    func setPermission(_ allowed: Bool) { granted.withLock { $0 = allowed } }
    var previewOfferIDs: [String] { previews.withLock { $0 } }

    func requestPermission() async -> Bool { granted.withLock { $0 } }
    func schedule(_ alerts: [OfferAlert], now: Date) async {}
    func replaceAll(with alerts: [OfferAlert], now: Date) async {}
    func cancel(offerIDs: [String]) async {}
    func cancelAll() async {}
    func sendPreview(_ alert: OfferAlert, after delay: TimeInterval) async {
        previews.withLock { $0.append(alert.offerID) }
        delays.withLock { $0.append(delay) }
    }
    private let delays = Mutex<[TimeInterval]>([])
    private let reminders = Mutex<[PickupReminder]>([])
    var sentReminders: [PickupReminder] { reminders.withLock { $0 } }
    func sendReminder(_ reminder: PickupReminder, after delay: TimeInterval) async {
        reminders.withLock { $0.append(reminder) }
    }
    /// Seconds before each preview fires, in order.
    var previewDelays: [TimeInterval] { delays.withLock { $0 } }
}

/// Wipes the fakes the way DemoDataResetter wipes the stores.
nonisolated final class FakeResetter: DemoDataResetting, Sendable {
    private let calls = Mutex(0)
    private let fail = Mutex(false)
    let marketplace: FakeMarketplace
    let userData: FakeUserData
    let walkRewards: FakeWalkRewards?

    init(marketplace: FakeMarketplace, userData: FakeUserData, walkRewards: FakeWalkRewards? = nil) {
        self.marketplace = marketplace
        self.userData = userData
        self.walkRewards = walkRewards
    }

    var resetCount: Int { calls.withLock { $0 } }
    func failNext() { fail.withLock { $0 = true } }

    func resetAll() async throws {
        if fail.withLock({ f in
            defer { f = false }
            return f
        }) {
            throw TestError()
        }
        calls.withLock { $0 += 1 }
        marketplace.clearReservations()
        userData.wipe()
        walkRewards?.wipe()
    }
}

nonisolated struct FakeLocation: LocationProvider {
    var result: ResolvedLocation
    func resolve() async -> ResolvedLocation { result }
}

nonisolated enum Fixture {
    static let licCenter = ServiceArea.longIslandCity.center

    /// A New York time in September 2026 (Thu the 24th is "today").
    static func sep(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        NYCalendar.date(on: DayKey(rawValue: String(format: "2026-09-%02d", day)), hour: hour, minute: minute)!
    }

    static func flags(
        mapBrowse: Bool = true, favorites: Bool = true, notifications: Bool = true, dietaryFilters: Bool = true,
        manageOrder: Bool = true, reviews: Bool = true, impact: Bool = true, commute: Bool = false,
        walkRewards: Bool = true
    ) -> FeatureFlags {
        FeatureFlags(
            mapBrowse: mapBrowse, favorites: favorites, notifications: notifications, dietaryFilters: dietaryFilters,
            manageOrder: manageOrder, reviews: reviews, impact: impact, commute: commute,
            walkRewards: walkRewards)
    }

    static func restaurant(_ id: String, name: String, lat: Double, lng: Double) -> Restaurant {
        Restaurant(
            id: id, name: name, kind: .cafe,
            address: .init(
                street: "Vernon Blvd", crossStreet: "48th Ave", neighborhood: "Long Island City",
                borough: "Queens", zip: "11101"),
            coordinate: Coordinate(latitude: lat, longitude: lng), pickupInstructions: "Ask at the counter.",
            rating: 4.5, reviewCount: 100)
    }

    /// ~0.23 mi, ~0.60 mi, and ~2.10 mi (Midtown) from the LIC center.
    static let restaurants = [
        restaurant("near", name: "Near Café", lat: 40.7443, lng: -73.9532),
        restaurant("mid", name: "Mid Deli", lat: 40.7497, lng: -73.9390),
        restaurant("far", name: "Far Bistro", lat: 40.7580, lng: -73.9855),
    ]

    /// A reservation for `offer` as it looked when reserved.
    static func reservation(
        for offer: Offer, quantity: Int = 1, reservedAt: Date = sep(24, 6), collectedAt: Date? = nil,
        cancelledAt: Date? = nil, review: Review? = nil
    ) -> Reservation {
        Reservation(
            id: UUID(), confirmationCode: "QW3E", quantity: quantity,
            snapshot: OfferSnapshot(offer: offer, restaurant: restaurants.first { $0.id == offer.restaurantID }!),
            reservedAt: reservedAt, collectedAt: collectedAt, cancelledAt: cancelledAt, review: review)
    }

    static func offer(
        _ template: String, restaurant: String = "near", day: Int = 24, start: (Int, Int), end: (Int, Int),
        category: FoodCategory = .breakfast, price: Int = 500, total: Int = 5, reserved: Int = 0,
        dietary: Set<DietaryTag> = []
    ) -> Offer {
        let key = DayKey(rawValue: String(format: "2026-09-%02d", day))
        return Offer(
            id: Offer.makeID(templateID: template, day: key), templateID: template, restaurantID: restaurant,
            name: "\(template) bag", category: category, summary: "Might include things.", dietary: dietary,
            price: Money(cents: price), estimatedValue: Money(cents: price * 3), quantityTotal: total,
            quantityReserved: reserved,
            pickupWindow: PickupWindow(
                start: NYCalendar.date(on: key, hour: start.0, minute: start.1)!,
                end: NYCalendar.date(on: key, hour: end.0, minute: end.1)!))
    }
}

@MainActor
struct Harness {
    let marketplace: FakeMarketplace
    let userData: FakeUserData
    let walkRewards = FakeWalkRewards()
    let walkTracker = FakeWalkTracker()
    let clock: AdjustableClock
    let notifications = FakeNotifications()
    let resetter: FakeResetter
    let developer: DeveloperSettings
    let demo: FakeDemoController
    let dependencies: CustomerDependencies

    init(
        now: Date,
        offers: [Offer],
        preferences: UserPreferences = UserPreferences(),
        favorites: [FavoriteRestaurant] = [],
        location: ResolvedLocation = ResolvedLocation(coordinate: Fixture.licCenter, source: .device),
        flags: FeatureFlags = Fixture.flags()
    ) {
        marketplace = FakeMarketplace(offers: offers)
        userData = FakeUserData(preferences: preferences, favorites: favorites)
        clock = AdjustableClock(fixedAt: now)
        resetter = FakeResetter(marketplace: marketplace, userData: userData, walkRewards: walkRewards)
        developer = DeveloperSettings(defaults: freshDefaults())
        demo = FakeDemoController(clock: clock)
        demo.walkRewards = walkRewards
        dependencies = CustomerDependencies(
            offers: marketplace, reservations: marketplace, reviews: marketplace, favorites: userData,
            preferences: userData, walkRewards: walkRewards, walkTracker: walkTracker,
            location: FakeLocation(result: location),
            notifications: notifications,
            resetter: resetter, clock: clock, flags: flags, developer: developer, demo: demo)
    }
}

/// A UserDefaults suite of its own, so tests never share Developer mode switches.
func freshDefaults() -> UserDefaults {
    let name = "WalkAndTakeTests.\(UUID().uuidString)"
    return UserDefaults(suiteName: name)!
}

/// Demo actions on the test clock.
@MainActor
final class FakeDemoController: DemoControlling {
    let clock: AdjustableClock

    init(clock: AdjustableClock) {
        self.clock = clock
    }

    var now: Date { clock.now }
    var isTimeLive: Bool { clock.isLive }
    func travel(to date: Date) { clock.travel(to: date) }
    func advanceTime(by interval: TimeInterval) { clock.advance(by: interval) }
    func resetTimeToLive() { clock.resetToLive() }

    /// Walks the test marks as simulated, and the demo calls made on them.
    var simulatedWalks: Set<UUID> = []
    var autoWalking: Set<UUID> = []
    private(set) var walkCalls: [String] = []

    func isSimulatedWalk(_ id: UUID) async -> Bool { simulatedWalks.contains(id) }
    func isAutoWalking(_ id: UUID) async -> Bool { autoWalking.contains(id) }
    func advanceWalk(_ id: UUID, miles: Double) async {
        walkCalls.append("advance \(miles)")
        autoWalking.remove(id)
    }
    func arriveWalk(_ id: UUID) async { walkCalls.append("arrive") }
    func autoWalk(_ id: UUID) async {
        walkCalls.append("auto")
        autoWalking.insert(id)
    }
    func pauseWalk(_ id: UUID) async {
        walkCalls.append("pause")
        autoWalking.remove(id)
    }

    /// Rewards actions go to the fake walk rewards, through the same rules as the real store.
    var walkRewards: FakeWalkRewards?

    func addMiles(_ miles: Double) async -> [Reward] {
        guard let walkRewards else { return [] }
        let id = UUID()
        _ = try? await walkRewards.startWalk(reservationID: id, restaurantID: "demo-\(id)", at: clock.now)
        return
            (try? await walkRewards.finishWalk(
                reservationID: id, verdict: .credited(miles: miles), at: clock.now, calendar: .current))?.newRewards
            ?? []
    }

    func completeNextMilestone() async -> [Reward] {
        let total = (try? await walkRewards?.totalMiles()) ?? 0
        return await addMiles(WalkRewardLadder.milesToNext(totalMiles: total) + 1e-6)
    }

    func grantReward() async -> Reward? {
        let total = (try? await walkRewards?.totalMiles()) ?? 0
        return walkRewards?.bank(milestoneMiles: WalkRewardLadder.nextMilestone(after: total), at: clock.now)
    }

    func clearWalksAndRewards() async { walkRewards?.clear() }
}

/// Polls until `condition` holds (for stream-driven updates), up to ~2 s.
@MainActor
func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
