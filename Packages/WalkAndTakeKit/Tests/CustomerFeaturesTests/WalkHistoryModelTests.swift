//
//  WalkHistoryModelTests.swift
//  CustomerFeaturesTests
//

import Domain
import Foundation
import Platform
import Testing

@testable import CustomerFeatures

@MainActor
@Suite("Walk history")
struct WalkHistoryModelTests {
    static let offer = Fixture.offer("breakfast", start: (7, 30), end: (10, 0))

    /// Records one finished walk. `restaurant` must be one of the fixture restaurants ("near", "mid", "far").
    @discardableResult
    func walk(
        _ harness: Harness, restaurant: String, miles: Double, finished: Date, rejected: WalkRejection? = nil
    ) async throws -> Walk {
        let id = UUID()
        _ = try await harness.walkRewards.startWalk(
            reservationID: id, restaurantID: restaurant, at: finished.addingTimeInterval(-900))
        let verdict: WalkVerdict = rejected.map { .rejected($0) } ?? .credited(miles: miles)
        return try await harness.walkRewards.finishWalk(
            reservationID: id, verdict: verdict, at: finished, calendar: NYCalendar.calendar
        ).walk
    }

    func model(_ harness: Harness) async -> WalkHistoryModel {
        let model = WalkHistoryModel(dependencies: harness.dependencies)
        await model.load()
        return model
    }

    @Test func startsEmpty() async {
        let harness = Harness(now: Fixture.sep(24, 9), offers: [Self.offer])
        let model = WalkHistoryModel(dependencies: harness.dependencies)
        #expect(model.state == .loading)
        await model.load()
        #expect(model.state == .loaded)
        #expect(model.isEmpty)
        #expect(model.summaryText == "0 walked pickups · 0.0 mi counted")
    }

    @Test func listsWalksNewestFirstWithRestaurantDateAndMiles() async throws {
        let harness = Harness(now: Fixture.sep(24, 12), offers: [Self.offer])
        try await walk(harness, restaurant: "near", miles: 0.23, finished: Fixture.sep(22, 8))
        try await walk(harness, restaurant: "mid", miles: 0.6, finished: Fixture.sep(24, 9))
        let model = await model(harness)

        #expect(model.rows.map(\.title) == ["Mid Deli", "Near Café"])
        #expect(model.rows[0].dateText == "Thu Sep 24 · 9:00 AM")
        #expect(model.rows[0].milesText == "+0.6 mi")
        #expect(model.rows[1].milesText == "+0.2 mi")
        #expect(model.summaryText == "2 walked pickups · 0.8 mi counted")
    }

    @Test func eachRowShowsTheRunningTotalAfterThatWalk() async throws {
        let harness = Harness(now: Fixture.sep(24, 12), offers: [Self.offer])
        try await walk(harness, restaurant: "near", miles: 0.4, finished: Fixture.sep(22, 8))
        try await walk(harness, restaurant: "mid", miles: 0.6, finished: Fixture.sep(24, 9))
        let model = await model(harness)
        #expect(model.rows[0].detail == "1.0 mi walked in total")  // newest
        #expect(model.rows[1].detail == "0.4 mi walked in total")  // oldest
    }

    @Test func aWalkThatEarnedNothingSaysWhy() async throws {
        let harness = Harness(now: Fixture.sep(24, 12), offers: [Self.offer])
        try await walk(harness, restaurant: "near", miles: 0, finished: Fixture.sep(24, 9), rejected: .tooFast)
        let model = await model(harness)
        let row = try #require(model.rows.first)
        #expect(row.milesText == "0 mi")
        #expect(!row.earnedMiles)
        #expect(row.detail == WalkRejection.tooFast.message)
        #expect(model.summaryText == "1 walked pickup · 0.0 mi counted")
    }

    @Test func aWalkNotYetFinishedIsLeftOut() async throws {
        let harness = Harness(now: Fixture.sep(24, 12), offers: [Self.offer])
        _ = try await harness.walkRewards.startWalk(reservationID: UUID(), restaurantID: "near", at: Fixture.sep(24, 8))
        #expect(await model(harness).isEmpty)
    }

    @Test func anUnknownRestaurantGetsAGenericName() async throws {
        let harness = Harness(now: Fixture.sep(24, 12), offers: [Self.offer])
        try await walk(harness, restaurant: "gone", miles: 0.5, finished: Fixture.sep(24, 9))
        #expect(try #require(await model(harness).rows.first).title == "Walk & Take pickup")
    }

    @Test func theListUpdatesWhenAWalkFinishes() async throws {
        let harness = Harness(now: Fixture.sep(24, 12), offers: [Self.offer])
        let model = WalkHistoryModel(dependencies: harness.dependencies)
        let watching = Task { await model.run() }
        defer { watching.cancel() }
        #expect(await eventually { model.state == .loaded })
        try await walk(harness, restaurant: "near", miles: 0.5, finished: Fixture.sep(24, 9))
        #expect(await eventually { model.rows.count == 1 })
    }

    @Test func resettingEmptiesTheHistory() async throws {
        let harness = Harness(now: Fixture.sep(24, 12), offers: [Self.offer])
        try await walk(harness, restaurant: "near", miles: 0.5, finished: Fixture.sep(24, 9))
        let model = await model(harness)
        #expect(model.rows.count == 1)
        harness.walkRewards.wipe()
        await model.load()
        #expect(model.isEmpty)
    }
}
