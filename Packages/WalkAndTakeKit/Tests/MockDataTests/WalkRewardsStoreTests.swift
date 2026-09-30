//
//  WalkRewardsStoreTests.swift
//  MockDataTests
//

import Domain
import Foundation
import SwiftData
import Testing

@testable import MockData

@Suite("Walk rewards store")
struct WalkRewardsStoreTests {
    static let pacific: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()
    static let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    let now = TestEnv.sep(24, 8)

    /// Starts and finishes a walk for a fresh reservation.
    @discardableResult
    func walk(
        _ store: UserDataStore, restaurant: String = "rst_a", miles: Double, at finish: Date? = nil,
        calendar: Calendar = WalkRewardsStoreTests.newYork
    ) async throws -> WalkCompletion {
        let id = UUID()
        _ = try await store.startWalk(reservationID: id, restaurantID: restaurant, at: now)
        return try await store.finishWalk(
            reservationID: id, verdict: .credited(miles: miles), at: finish ?? now.addingTimeInterval(1800),
            calendar: calendar)
    }

    @Test func startingTwiceReturnsTheSameWalk() async throws {
        let store = try await TestEnv.makeStores().userData
        let id = UUID()
        let first = try await store.startWalk(reservationID: id, restaurantID: "rst_a", at: now)
        let second = try await store.startWalk(reservationID: id, restaurantID: "rst_a", at: now.addingTimeInterval(60))
        #expect(first == second)
        #expect(try await store.walks().count == 1)
    }

    @Test func finishingCreditsMilesAndBanksTheFirstReward() async throws {
        let store = try await TestEnv.makeStores().userData
        let done = try await walk(store, miles: 0.6)
        #expect(done.newRewards.isEmpty)
        #expect(done.totalMiles == 0.6)

        let second = try await walk(store, restaurant: "rst_b", miles: 0.6)
        #expect(second.newRewards.map(\.milestoneMiles) == [1])
        #expect(abs(second.totalMiles - 1.2) < 1e-9)
        #expect(try await store.rewards().count == 1)
        #expect(abs(try await store.totalMiles() - 1.2) < 1e-9)
    }

    @Test func oneWalkCanCrossSeveralMilestones() async throws {
        let store = try await TestEnv.makeStores().userData
        try await walk(store, restaurant: "a", miles: 2)
        try await walk(store, restaurant: "b", miles: 2)
        let third = try await walk(store, restaurant: "c", miles: 2)  // 6 mi: crosses 5
        #expect(third.newRewards.map(\.milestoneMiles) == [5])
        #expect(try await store.rewards().map(\.milestoneMiles) == [1, 5])
    }

    @Test func finishingTwiceChangesNothing() async throws {
        let store = try await TestEnv.makeStores().userData
        let id = UUID()
        _ = try await store.startWalk(reservationID: id, restaurantID: "rst_a", at: now)
        _ = try await store.finishWalk(
            reservationID: id, verdict: .credited(miles: 1.5), at: now, calendar: Self.newYork)
        let again = try await store.finishWalk(
            reservationID: id, verdict: .credited(miles: 1.5), at: now, calendar: Self.newYork)
        #expect(again.newRewards.isEmpty)
        #expect(abs(try await store.totalMiles() - 1.5) < 1e-9)
        #expect(try await store.rewards().count == 1)
    }

    @Test func rejectedWalksEarnNothingAndKeepTheReason() async throws {
        let store = try await TestEnv.makeStores().userData
        let id = UUID()
        _ = try await store.startWalk(reservationID: id, restaurantID: "rst_a", at: now)
        let done = try await store.finishWalk(
            reservationID: id, verdict: .rejected(.tooFast), at: now, calendar: Self.newYork)
        #expect(done.walk.creditedMiles == 0)
        #expect(done.walk.rejection == .tooFast)
        #expect(try await store.walk(reservationID: id)?.rejection == .tooFast)
        #expect(try await store.totalMiles() == 0)
    }

    @Test func finishingAnUnknownWalkThrows() async throws {
        let store = try await TestEnv.makeStores().userData
        await #expect(throws: WalkRewardsError.walkNotFound) {
            try await store.finishWalk(
                reservationID: UUID(), verdict: .credited(miles: 1), at: now, calendar: Self.newYork)
        }
    }

    // MARK: Once per restaurant per day

    @Test func aSecondPickupFromTheSameRestaurantTheSameDayEarnsNothing() async throws {
        let store = try await TestEnv.makeStores().userData
        try await walk(store, miles: 0.5)
        let repeatWalk = try await walk(store, miles: 0.5)
        #expect(repeatWalk.walk.creditedMiles == 0)
        #expect(repeatWalk.walk.rejection == .repeatPickupToday)
        #expect(abs(try await store.totalMiles() - 0.5) < 1e-9)
    }

    @Test func aDifferentRestaurantOrANextDayStillEarns() async throws {
        let store = try await TestEnv.makeStores().userData
        try await walk(store, restaurant: "rst_a", miles: 0.5)
        let other = try await walk(store, restaurant: "rst_b", miles: 0.5)
        let nextDay = try await walk(store, restaurant: "rst_a", miles: 0.5, at: TestEnv.sep(25, 12))
        #expect(other.walk.creditedMiles == 0.5)
        #expect(nextDay.walk.creditedMiles == 0.5)
    }

    @Test func theDayFollowsTheUsersTimeZone() async throws {
        // 9 PM and 1 AM New York time: two calendar days in New York, one evening in Los Angeles.
        let late = TestEnv.sep(24, 21)
        let after = TestEnv.sep(25, 1)

        let inNewYork = try await TestEnv.makeStores().userData
        try await walk(inNewYork, miles: 0.5, at: late, calendar: Self.newYork)
        let ny = try await walk(inNewYork, miles: 0.5, at: after, calendar: Self.newYork)
        #expect(ny.walk.creditedMiles == 0.5)

        let inLosAngeles = try await TestEnv.makeStores().userData
        try await walk(inLosAngeles, miles: 0.5, at: late, calendar: Self.pacific)
        let la = try await walk(inLosAngeles, miles: 0.5, at: after, calendar: Self.pacific)
        #expect(la.walk.rejection == .repeatPickupToday)
    }

    // MARK: Redeeming

    @Test func aRewardCanBeRedeemedOnce() async throws {
        let store = try await TestEnv.makeStores().userData
        let done = try await walk(store, miles: 1.2)
        let reward = try #require(done.newRewards.first)
        let reservationID = UUID()
        let used = try await store.redeemReward(id: reward.id, reservationID: reservationID, at: now)
        #expect(!used.isAvailable)
        #expect(used.redeemedReservationID == reservationID)
        await #expect(throws: WalkRewardsError.rewardAlreadyRedeemed) {
            try await store.redeemReward(id: reward.id, reservationID: UUID(), at: now)
        }
        await #expect(throws: WalkRewardsError.rewardNotFound) {
            try await store.redeemReward(id: UUID(), reservationID: UUID(), at: now)
        }
    }

    @Test func releasingMakesTheRewardAvailableAgain() async throws {
        let store = try await TestEnv.makeStores().userData
        let reward = try #require(try await walk(store, miles: 1.2).newRewards.first)
        let reservationID = UUID()
        _ = try await store.redeemReward(id: reward.id, reservationID: reservationID, at: now)
        try await store.releaseReward(reservationID: reservationID)
        #expect(try await store.rewards().first?.isAvailable == true)
        _ = try await store.redeemReward(id: reward.id, reservationID: UUID(), at: now)
    }

    @Test func simultaneousRedemptionsSucceedExactlyOnce() async throws {
        let store = try await TestEnv.makeStores().userData
        let reward = try #require(try await walk(store, miles: 1.2).newRewards.first)
        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask { (try? await store.redeemReward(id: reward.id, reservationID: UUID(), at: now)) != nil }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        #expect(successes == 1)
    }

    // MARK: Changes and reset

    @Test func changesAreBroadcast() async throws {
        let store = try await TestEnv.makeStores().userData
        var iterator = store.changes().makeAsyncIterator()
        _ = try await store.startWalk(reservationID: UUID(), restaurantID: "rst_a", at: now)
        #expect(await iterator.next() == .walkRewardsChanged)
    }

    @Test func resetWipesWalksAndRewards() async throws {
        let store = try await TestEnv.makeStores().userData
        try await walk(store, miles: 1.5)
        try await store.deleteAll()
        #expect(try await store.walks().isEmpty)
        #expect(try await store.rewards().isEmpty)
        #expect(try await store.totalMiles() == 0)
    }

    // MARK: Reservation discount columns

    @Test func aReservationKeepsItsRewardAndDiscount() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = ModelContext(container)
        let rewardID = UUID()
        let reservation = Reservation(
            id: UUID(), confirmationCode: "AB23", quantity: 2,
            snapshot: OfferSnapshot(
                offerID: "o", restaurantID: "r", restaurantName: "R",
                address: .init(street: "s", crossStreet: "c", neighborhood: "n", borough: "b", zip: "z"),
                coordinate: Coordinate(latitude: 40.7, longitude: -73.9), pickupInstructions: "",
                bagName: "Bag", category: .meal, summary: "", unitPrice: Money(cents: 600),
                estimatedValue: Money(cents: 1800),
                pickupWindow: PickupWindow(start: now, end: now.addingTimeInterval(3600))),
            reservedAt: now, rewardID: rewardID, discount: Money(cents: 300))
        context.insert(ReservationEntity(reservation))
        try context.save()

        let loaded = try #require(try context.fetch(FetchDescriptor<ReservationEntity>()).first).domain
        #expect(loaded.rewardID == rewardID)
        #expect(loaded.discount == Money(cents: 300))
        #expect(loaded.total == Money(cents: 900))  // 2 x $6.00 - $3.00
        #expect(loaded.savings == Money(cents: 2700))  // 2 x $12.00 + $3.00
    }
}
