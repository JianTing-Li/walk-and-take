//
//  RewardAtomicityTests.swift
//  MockDataTests
//
//  A walking reward is spent in the same save as the reservation that uses it, and given back in the same
//  save as the cancellation. Either both happen or neither does.
//

import Domain
import Foundation
import Platform
import Testing

@testable import MockData

@Suite("Reward spent with the reservation")
struct RewardAtomicityTests {
    let earlyBird = TestEnv.offerID("tpl_early_bird_breakfast", day: 24)  // 4 bags
    let now = TestEnv.sep(24, 7)

    func stores() async throws -> TestEnv.Stores {
        try await TestEnv.makeStores(rolloverAt: now)
    }

    /// Earns the first reward (a credited 1.5 mi walk) and returns it.
    @discardableResult
    func earnReward(_ userData: UserDataStore, restaurant: String = "rst_test") async throws -> Reward {
        let id = UUID()
        _ = try await userData.startWalk(reservationID: id, restaurantID: restaurant, at: now)
        let done = try await userData.finishWalk(
            reservationID: id, verdict: .credited(miles: 1.5), at: now, calendar: NYCalendar.calendar)
        return try #require(done.newRewards.first)
    }

    func left(_ market: MarketplaceStore) async throws -> Int {
        try #require(try await market.offer(id: earlyBird)).quantityLeft
    }

    // MARK: Reserving

    @Test func reservingSpendsTheRewardInTheSameStep() async throws {
        let s = try await stores()
        let reward = try await earnReward(s.userData)
        _ = try await s.userData.rewards()  // the other store has already looked at it
        let reservationID = UUID()
        let r = try await s.marketplace.reserve(
            offerID: earlyBird, quantity: 2, reservationID: reservationID, rewardID: reward.id, at: now)
        #expect(r.rewardID == reward.id)
        #expect(r.discount == Money(cents: 299))

        // The other store sees it as used by this reservation.
        let seen = try #require(try await s.userData.rewards().first)
        #expect(!seen.isAvailable)
        #expect(seen.redeemedReservationID == reservationID)
        #expect(seen.redeemedAt == now)
    }

    @Test func tooManyBagsIsRefusedAndTheRewardStaysUnspent() async throws {
        let s = try await stores()
        let reward = try await earnReward(s.userData)
        let before = try await left(s.marketplace)
        await #expect(throws: ReservationError.invalidQuantity) {
            try await s.marketplace.reserve(
                offerID: earlyBird, quantity: 9, reservationID: UUID(), rewardID: reward.id, at: now)
        }
        #expect(try await left(s.marketplace) == before)
        #expect(try await s.marketplace.reservations().isEmpty)
        #expect(try #require(try await s.userData.rewards().first).isAvailable)
    }

    @Test func aClosedWindowIsRefusedAndTheRewardStaysUnspent() async throws {
        let s = try await stores()
        let reward = try await earnReward(s.userData)
        let tooLate = TestEnv.sep(24, 23, 30)
        await #expect(throws: ReservationError.windowClosed) {
            try await s.marketplace.reserve(
                offerID: earlyBird, quantity: 1, reservationID: UUID(), rewardID: reward.id, at: tooLate)
        }
        #expect(try await s.marketplace.reservations().isEmpty)
        #expect(try #require(try await s.userData.rewards().first).isAvailable)
    }

    @Test func anUnknownRewardRefusesTheReservationAndChangesNothing() async throws {
        let s = try await stores()
        let before = try await left(s.marketplace)
        await #expect(throws: ReservationError.rewardUnavailable) {
            try await s.marketplace.reserve(
                offerID: earlyBird, quantity: 1, reservationID: UUID(), rewardID: UUID(), at: now)
        }
        #expect(try await left(s.marketplace) == before)
        #expect(try await s.marketplace.reservations().isEmpty)
    }

    @Test func aRewardAlreadyUsedCannotBackASecondReservation() async throws {
        let s = try await stores()
        let reward = try await earnReward(s.userData)
        _ = try await s.marketplace.reserve(
            offerID: earlyBird, quantity: 1, reservationID: UUID(), rewardID: reward.id, at: now)
        let before = try await left(s.marketplace)
        await #expect(throws: ReservationError.rewardUnavailable) {
            try await s.marketplace.reserve(
                offerID: earlyBird, quantity: 1, reservationID: UUID(), rewardID: reward.id, at: now)
        }
        #expect(try await left(s.marketplace) == before)
        #expect(try await s.marketplace.reservations().count == 1)
    }

    @Test func aPlainReservationNeverTouchesRewards() async throws {
        let s = try await stores()
        let reward = try await earnReward(s.userData)
        _ = try await s.marketplace.reserve(offerID: earlyBird, quantity: 1, at: now)
        #expect(try #require(try await s.userData.rewards().first).isAvailable)
        #expect(try await s.userData.rewards().first?.id == reward.id)
    }

    @Test func simultaneousReservationsWithOneRewardSucceedExactlyOnce() async throws {
        let s = try await stores()
        let reward = try await earnReward(s.userData)
        let before = try await left(s.marketplace)
        let market = s.marketplace
        let now = now
        let earlyBird = earlyBird
        let outcomes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    (try? await market.reserve(
                        offerID: earlyBird, quantity: 1, reservationID: UUID(), rewardID: reward.id, at: now)) != nil
                }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        #expect(outcomes == 1)
        #expect(try await left(s.marketplace) == before - 1)
        #expect(try await s.marketplace.reservations().count == 1)
    }

    // MARK: Cancelling

    @Test func cancellingGivesTheRewardBackInTheSameStep() async throws {
        let s = try await stores()
        let reward = try await earnReward(s.userData)
        let reservationID = UUID()
        let r = try await s.marketplace.reserve(
            offerID: earlyBird, quantity: 1, reservationID: reservationID, rewardID: reward.id, at: now)
        #expect(!(try #require(try await s.userData.rewards().first)).isAvailable)

        _ = try await s.marketplace.cancel(reservationID: r.id, reason: nil, at: now)
        let seen = try #require(try await s.userData.rewards().first)
        #expect(seen.isAvailable)
        #expect(seen.redeemedReservationID == nil)
        #expect(try await left(s.marketplace) == 4)
    }

    @Test func cancellingAnOrderWithoutARewardLeavesOtherRewardsSpent() async throws {
        let s = try await stores()
        let reward = try await earnReward(s.userData)
        _ = try await s.marketplace.reserve(
            offerID: earlyBird, quantity: 1, reservationID: UUID(), rewardID: reward.id, at: now)
        let plain = try await s.marketplace.reserve(offerID: earlyBird, quantity: 1, at: now)
        _ = try await s.marketplace.cancel(reservationID: plain.id, reason: nil, at: now)
        #expect(!(try #require(try await s.userData.rewards().first)).isAvailable)
    }

    @Test func aRefusedCancelLeavesTheRewardSpent() async throws {
        let s = try await stores()
        let reward = try await earnReward(s.userData)
        let r = try await s.marketplace.reserve(
            offerID: earlyBird, quantity: 1, reservationID: UUID(), rewardID: reward.id, at: now)
        let afterDeadline = TestEnv.sep(24, 9, 55)  // changes close 10 min before pickup ends
        await #expect(throws: ReservationError.changeClosed) {
            try await s.marketplace.cancel(reservationID: r.id, reason: nil, at: afterDeadline)
        }
        #expect(!(try #require(try await s.userData.rewards().first)).isAvailable)
    }

    // MARK: Listeners

    @Test func rewardChangesReachTheUserDataFeed() async throws {
        let s = try await stores()
        let reward = try await earnReward(s.userData)
        var feed = s.userData.changes().makeAsyncIterator()
        let r = try await s.marketplace.reserve(
            offerID: earlyBird, quantity: 1, reservationID: UUID(), rewardID: reward.id, at: now)
        #expect(await feed.next() == .walkRewardsChanged)
        _ = try await s.marketplace.cancel(reservationID: r.id, reason: nil, at: now)
        #expect(await feed.next() == .walkRewardsChanged)
    }
}
