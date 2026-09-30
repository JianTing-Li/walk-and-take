//
//  RewardsListModelTests.swift
//  CustomerFeaturesTests
//

import Domain
import Foundation
import Platform
import Testing

@testable import CustomerFeatures

@MainActor
@Suite("Rewards list")
struct RewardsListModelTests {
    static let offer = Fixture.offer("breakfast", start: (7, 30), end: (10, 0), price: 599)

    func harness() -> Harness { Harness(now: Fixture.sep(24, 12), offers: [Self.offer]) }

    func model(_ harness: Harness) async -> RewardsListModel {
        let model = RewardsListModel(dependencies: harness.dependencies)
        await model.load()
        return model
    }

    static func reward(_ miles: Double, earned: Date) -> Reward { Reward(milestoneMiles: miles, earnedAt: earned) }

    /// A reservation that used `reward`, taking $2.99 off a $5.99 bag.
    @discardableResult
    func reserveUsing(_ reward: Reward, in harness: Harness, cancelled: Bool = false) async throws -> Reservation {
        let id = UUID()
        _ = try await harness.walkRewards.redeemReward(id: reward.id, reservationID: id, at: Fixture.sep(23, 9))
        let base = Fixture.reservation(for: Self.offer)
        let reservation = Reservation(
            id: id, confirmationCode: "QW3E", quantity: 1, snapshot: base.snapshot, reservedAt: Fixture.sep(23, 9),
            cancelledAt: cancelled ? Fixture.sep(23, 10) : nil, rewardID: reward.id, discount: Money(cents: 299))
        return harness.marketplace.add(reservation)
    }

    @Test func startsEmptyWithAHintAboutTheFirstReward() async {
        let harness = harness()
        let model = RewardsListModel(dependencies: harness.dependencies)
        #expect(model.state == .loading)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.isEmpty)
        #expect(model.emptyMessage == "Walk 1 mi in total to earn your first 50% off. Every pickup you walk counts.")
    }

    @Test func readyRewardsShowWhereTheyWereEarned() async {
        let harness = harness()
        harness.walkRewards.seed(rewards: [
            Self.reward(1, earned: Fixture.sep(22, 9)), Self.reward(5, earned: Fixture.sep(24, 9)),
        ])
        let model = await model(harness)
        #expect(model.ready.map(\.earnedText) == ["Earned at 1 mi · Tue Sep 22", "Earned at 5 mi · Thu Sep 24"])
        #expect(model.ready.allSatisfy { $0.title == "50% off one bag" && $0.isAvailable })
        #expect(model.used.isEmpty)
        #expect(model.summaryText == "2 ready to use · 0 used")
    }

    @Test func aUsedRewardSaysWhereWhenAndWhatItSaved() async throws {
        let harness = harness()
        let reward = Self.reward(1, earned: Fixture.sep(22, 9))
        harness.walkRewards.seed(rewards: [reward])
        try await reserveUsing(reward, in: harness)
        let model = await model(harness)
        #expect(model.ready.isEmpty)
        let row = try #require(model.used.first)
        #expect(row.usedText == "Used Wed Sep 23 at Near Café · saved $2.99")
        #expect(!row.isAvailable)
        #expect(model.summaryText == "0 ready to use · 1 used")
    }

    @Test func readyAndUsedAreListedSeparatelyWithTheLatestUsedFirst() async throws {
        let harness = harness()
        let first = Self.reward(1, earned: Fixture.sep(20, 9))
        let second = Self.reward(5, earned: Fixture.sep(21, 9))
        let third = Self.reward(15, earned: Fixture.sep(22, 9))
        harness.walkRewards.seed(rewards: [first, second, third])
        _ = try await harness.walkRewards.redeemReward(id: first.id, reservationID: UUID(), at: Fixture.sep(21, 10))
        _ = try await harness.walkRewards.redeemReward(id: second.id, reservationID: UUID(), at: Fixture.sep(23, 10))
        let model = await model(harness)
        #expect(model.ready.count == 1)
        #expect(model.used.map(\.earnedText) == ["Earned at 5 mi · Mon Sep 21", "Earned at 1 mi · Sun Sep 20"])
    }

    @Test func aUsedRewardWhoseOrderIsGoneStillShowsWhenItWasUsed() async throws {
        let harness = harness()
        let reward = Self.reward(1, earned: Fixture.sep(22, 9))
        harness.walkRewards.seed(rewards: [reward])
        _ = try await harness.walkRewards.redeemReward(id: reward.id, reservationID: UUID(), at: Fixture.sep(23, 9))
        #expect(try #require(await model(harness).used.first).usedText == "Used Wed Sep 23")
    }

    @Test func cancellingTheOrderMovesTheRewardBackToReady() async throws {
        let harness = harness()
        let reward = Self.reward(1, earned: Fixture.sep(22, 9))
        harness.walkRewards.seed(rewards: [reward])
        let reservation = try await reserveUsing(reward, in: harness)
        let model = await model(harness)
        #expect(model.used.count == 1)
        _ = try await harness.marketplace.cancel(reservationID: reservation.id, reason: nil, at: Fixture.sep(23, 10))
        try await harness.walkRewards.releaseReward(reservationID: reservation.id)
        await model.load()
        #expect(model.ready.count == 1)
        #expect(model.used.isEmpty)
    }

    @Test func theListUpdatesWhenARewardIsSpent() async throws {
        let harness = harness()
        let reward = Self.reward(1, earned: Fixture.sep(22, 9))
        harness.walkRewards.seed(rewards: [reward])
        let model = RewardsListModel(dependencies: harness.dependencies)
        let watching = Task { await model.run() }
        defer { watching.cancel() }
        #expect(await eventually { model.ready.count == 1 })
        _ = try await harness.walkRewards.redeemReward(id: reward.id, reservationID: UUID(), at: Fixture.sep(24, 9))
        #expect(await eventually { model.used.count == 1 })
        #expect(model.ready.isEmpty)
    }

    @Test func resettingEmptiesTheList() async throws {
        let harness = harness()
        harness.walkRewards.seed(rewards: [Self.reward(1, earned: Fixture.sep(22, 9))])
        let model = await model(harness)
        #expect(!model.isEmpty)
        harness.walkRewards.wipe()
        await model.load()
        #expect(model.isEmpty)
    }
}
