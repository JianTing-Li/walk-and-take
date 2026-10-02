//
//  WalkTrackerPersistenceTests.swift
//  PlatformTests
//
//  A tracker with a store saves fixes in small batches and picks them up again after the app is killed.
//

import Domain
import Foundation
import Testing

@testable import Platform

struct StoreFailure: Error {}

/// Keeps "saved" fixes in memory, and can be told to fail.
actor FakeSampleStore: WalkSampleStoring {
    private var rows: [UUID: [WalkSample]] = [:]
    private var failuresLeft = 0
    private(set) var appendCalls = 0

    func failNext(_ count: Int) { failuresLeft = count }
    func preload(_ samples: [WalkSample], for id: UUID) { rows[id] = samples }
    func count(for id: UUID) -> Int { rows[id]?.count ?? 0 }
    func all(for id: UUID) -> [WalkSample] { rows[id] ?? [] }

    func appendSamples(_ samples: [WalkSample], reservationID: UUID) throws {
        appendCalls += 1
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw StoreFailure()
        }
        rows[reservationID, default: []] += samples
    }

    func savedSamples(reservationID: UUID) throws -> [WalkSample] { rows[reservationID] ?? [] }
    func discardSamples(reservationID: UUID) throws { rows[reservationID] = nil }
}

@Suite("Walk tracker persistence")
struct WalkTrackerPersistenceTests {
    let id = UUID()
    let destination = Coordinate(latitude: 40.7455, longitude: -73.9490)

    /// A fix taken `seconds` after the walk began, drifting north.
    func fix(_ seconds: Double) -> WalkSample {
        WalkSample(
            coordinate: Coordinate(latitude: 40.74 + seconds * 0.00001, longitude: -73.95),
            timestamp: Date(timeIntervalSince1970: 1_000_000 + seconds))
    }

    func waitFor(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<300 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }

    func makeTracker(_ store: FakeSampleStore, _ source: ScriptedWalkSource) -> LiveWalkTracker {
        LiveWalkTracker(source: source, store: store)
    }

    @Test func fixesAreSavedInBatchesAsTheyArrive() async throws {
        let store = FakeSampleStore()
        let source = ScriptedWalkSource()
        let tracker = makeTracker(store, source)
        await tracker.begin(reservationID: id, destination: destination)
        for second in 0..<7 { source.send(.sample(fix(Double(second)))) }  // 1 s apart
        // The first fix is saved at once; then a batch of five goes when it is full.
        #expect(await waitFor { await store.count(for: id) == 6 })
        #expect(await tracker.samples(reservationID: id).count == 7)
        #expect(await store.count(for: id) == 6)  // the 7th is still waiting for its batch
    }

    @Test func aLongGapSavesTheWaitingFixAtOnce() async throws {
        let store = FakeSampleStore()
        let source = ScriptedWalkSource()
        let tracker = makeTracker(store, source)
        await tracker.begin(reservationID: id, destination: destination)
        source.send(.sample(fix(0)))
        #expect(await waitFor { await store.count(for: id) == 1 })
        source.send(.sample(fix(30)))  // 30 s later: past the 5 s limit
        #expect(await waitFor { await store.count(for: id) == 2 })
    }

    @Test func finishingSavesWhateverIsWaiting() async throws {
        let store = FakeSampleStore()
        let source = ScriptedWalkSource()
        let tracker = makeTracker(store, source)
        await tracker.begin(reservationID: id, destination: destination)
        for second in 0..<4 { source.send(.sample(fix(Double(second)))) }
        #expect(await waitFor { await tracker.samples(reservationID: id).count == 4 })
        let recorded = await tracker.finish(reservationID: id)
        #expect(recorded.count == 4)
        #expect(await store.all(for: id) == recorded)
        #expect(await tracker.status(reservationID: id) == .idle)
    }

    @Test func aKilledWalkResumesWithTheFixesAlreadySaved() async throws {
        let store = FakeSampleStore()
        let earlier = (0..<4).map { fix(Double($0) * 10) }
        await store.preload(earlier, for: id)
        let source = ScriptedWalkSource()
        let tracker = makeTracker(store, source)  // a new tracker: the app was relaunched
        await tracker.begin(reservationID: id, destination: destination)
        #expect(await tracker.samples(reservationID: id) == earlier)

        source.send(.sample(fix(300)))
        #expect(await waitFor { await tracker.samples(reservationID: id).count == 5 })
        #expect(await waitFor { await store.count(for: id) == 5 })  // the new fix is saved after the old ones
        #expect(await store.all(for: id).prefix(4).elementsEqual(earlier))
    }

    @Test func saveKeepsFixesUntilTheyAreDiscarded() async throws {
        let store = FakeSampleStore()
        let source = ScriptedWalkSource()
        let tracker = makeTracker(store, source)
        await tracker.begin(reservationID: id, destination: destination)
        source.send(.sample(fix(0)))
        source.send(.sample(fix(1)))
        #expect(await waitFor { await tracker.samples(reservationID: id).count == 2 })
        let recorded = await tracker.finish(reservationID: id)
        // Finished, but not credited yet: the fixes stay so a kill right now can still be recovered.
        #expect(await store.count(for: id) == 2)
        #expect(await tracker.recover(reservationID: id) == recorded)
        await tracker.discard(reservationID: id)
        #expect(await store.count(for: id) == 0)
        #expect(await tracker.recover(reservationID: id).isEmpty)
    }

    @Test func recoverReadsSavedFixesWithoutStartingToRecord() async throws {
        let store = FakeSampleStore()
        let saved = (0..<3).map { fix(Double($0)) }
        await store.preload(saved, for: id)
        let tracker = makeTracker(store, ScriptedWalkSource())
        #expect(await tracker.recover(reservationID: id) == saved)
        #expect(await tracker.status(reservationID: id) == .idle)
    }

    @Test func aFailedSaveIsRetriedWithTheNextBatchWithoutLosingOrRepeatingFixes() async throws {
        let store = FakeSampleStore()
        await store.failNext(1)
        let source = ScriptedWalkSource()
        let tracker = makeTracker(store, source)
        await tracker.begin(reservationID: id, destination: destination)
        source.send(.sample(fix(0)))  // its save fails
        #expect(await waitFor { await store.appendCalls == 1 })
        #expect(await store.count(for: id) == 0)
        source.send(.sample(fix(30)))  // the retry carries both
        #expect(await waitFor { await store.count(for: id) == 2 })
        #expect(await store.all(for: id) == [fix(0), fix(30)])
    }

    @Test func aTrackerWithoutAStoreStillWorks() async throws {
        let source = ScriptedWalkSource()
        let tracker = LiveWalkTracker(source: source)
        await tracker.begin(reservationID: id, destination: destination)
        source.send(.sample(fix(0)))
        #expect(await waitFor { await tracker.samples(reservationID: id).count == 1 })
        #expect(await tracker.recover(reservationID: id).count == 1)  // still recording: what is in memory
        #expect(await tracker.finish(reservationID: id).count == 1)
        #expect(await tracker.recover(reservationID: id).isEmpty)  // nothing was ever saved
        await tracker.discard(reservationID: id)  // nothing to forget, and no crash
    }
}
