//
//  WalkSampleStoreTests.swift
//  MockDataTests
//

import Domain
import Foundation
import Testing

@testable import MockData

@Suite("Saved walk fixes")
struct WalkSampleStoreTests {
    let id = UUID()

    func fix(_ n: Int, accuracy: Double = 5, simulated: Bool = false) -> WalkSample {
        WalkSample(
            coordinate: Coordinate(latitude: 40.74 + Double(n) * 0.001, longitude: -73.95),
            timestamp: Date(timeIntervalSince1970: 1_000_000 + Double(n) * 10),
            horizontalAccuracyMeters: accuracy, isSimulated: simulated)
    }

    @Test func fixesComeBackOldestFirstWithEverythingIntact() async throws {
        let store = try await TestEnv.makeStores().userData
        // Saved out of order and across batches.
        try await store.appendSamples([fix(2), fix(3, accuracy: 12.5, simulated: true)], reservationID: id)
        try await store.appendSamples([fix(0), fix(1)], reservationID: id)
        let back = try await store.savedSamples(reservationID: id)
        #expect(back == [fix(0), fix(1), fix(2), fix(3, accuracy: 12.5, simulated: true)])
    }

    @Test func eachWalksFixesStayApart() async throws {
        let store = try await TestEnv.makeStores().userData
        let other = UUID()
        try await store.appendSamples([fix(0), fix(1)], reservationID: id)
        try await store.appendSamples([fix(5)], reservationID: other)
        #expect(try await store.savedSamples(reservationID: id).count == 2)
        #expect(try await store.savedSamples(reservationID: other) == [fix(5)])
        #expect(try await store.savedSamples(reservationID: UUID()).isEmpty)
    }

    @Test func discardingForgetsOnlyThatWalk() async throws {
        let store = try await TestEnv.makeStores().userData
        let other = UUID()
        try await store.appendSamples([fix(0)], reservationID: id)
        try await store.appendSamples([fix(1)], reservationID: other)
        try await store.discardSamples(reservationID: id)
        #expect(try await store.savedSamples(reservationID: id).isEmpty)
        #expect(try await store.savedSamples(reservationID: other).count == 1)
        try await store.discardSamples(reservationID: id)  // nothing left: fine
    }

    @Test func savingNothingDoesNothing() async throws {
        let store = try await TestEnv.makeStores().userData
        try await store.appendSamples([], reservationID: id)
        #expect(try await store.savedSamples(reservationID: id).isEmpty)
    }

    @Test func aRelaunchedStoreOnTheSameDataStillHasThem() async throws {
        let stores = try await TestEnv.makeStores()
        try await stores.userData.appendSamples([fix(0), fix(1)], reservationID: id)
        let relaunched = UserDataStore(modelContainer: stores.container)  // a new process, same file
        #expect(try await relaunched.savedSamples(reservationID: id) == [fix(0), fix(1)])
    }

    @Test func resettingDemoDataWipesThem() async throws {
        let store = try await TestEnv.makeStores().userData
        try await store.appendSamples([fix(0)], reservationID: id)
        try await store.deleteAll()
        #expect(try await store.savedSamples(reservationID: id).isEmpty)
    }
}
