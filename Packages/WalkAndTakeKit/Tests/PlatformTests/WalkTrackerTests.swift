//
//  WalkTrackerTests.swift
//  PlatformTests
//

import Domain
import Foundation
import Synchronization
import Testing

@testable import Platform

/// Lets a test push events into the tracker's stream.
final class ScriptedWalkSource: WalkLocationSource {
    private let continuation = Mutex<AsyncStream<WalkLocationEvent>.Continuation?>(nil)
    let streamsOpened = Mutex(0)

    func events() -> AsyncStream<WalkLocationEvent> {
        streamsOpened.withLock { $0 += 1 }
        return AsyncStream { continuation in
            self.continuation.withLock { $0 = continuation }
        }
    }

    func send(_ event: WalkLocationEvent) { _ = continuation.withLock { $0?.yield(event) } }
}

@Suite("Walk tracker")
struct WalkTrackerTests {
    let id = UUID()
    let destination = Coordinate(latitude: 40.7455, longitude: -73.9490)

    func sample(_ n: Int) -> WalkSample {
        WalkSample(
            coordinate: Coordinate(latitude: 40.74 + Double(n) * 0.0001, longitude: -73.95),
            timestamp: Date(timeIntervalSince1970: Double(n) * 30))
    }

    /// Polls until the tracker has `count` samples (the source feeds it asynchronously).
    func waitForSamples(_ tracker: LiveWalkTracker, _ count: Int) async -> Bool {
        for _ in 0..<200 {
            if await tracker.samples(reservationID: id).count >= count { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test func idleUntilItBegins() async {
        let tracker = LiveWalkTracker(source: ScriptedWalkSource())
        #expect(await tracker.status(reservationID: id) == .idle)
        #expect(await tracker.samples(reservationID: id).isEmpty)
        #expect(await tracker.finish(reservationID: id).isEmpty)
    }

    @Test func recordsSamplesInOrderAndFinishReturnsThem() async {
        let source = ScriptedWalkSource()
        let tracker = LiveWalkTracker(source: source)
        await tracker.begin(reservationID: id, destination: destination)
        #expect(await tracker.status(reservationID: id) == .tracking)
        for n in 0..<3 { source.send(.sample(sample(n))) }
        #expect(await waitForSamples(tracker, 3))
        let recorded = await tracker.finish(reservationID: id)
        #expect(recorded == (0..<3).map(sample))
        #expect(await tracker.status(reservationID: id) == .idle)
    }

    @Test func beginningTwiceKeepsOneRecording() async {
        let source = ScriptedWalkSource()
        let tracker = LiveWalkTracker(source: source)
        await tracker.begin(reservationID: id, destination: destination)
        await tracker.begin(reservationID: id, destination: destination)
        #expect(source.streamsOpened.withLock { $0 } == 1)
    }

    @Test func deniedLocationMarksTheWalkAndAFixClearsIt() async {
        let source = ScriptedWalkSource()
        let tracker = LiveWalkTracker(source: source)
        await tracker.begin(reservationID: id, destination: destination)
        source.send(.denied)
        for _ in 0..<200 where await tracker.status(reservationID: id) != .locationOff {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(await tracker.status(reservationID: id) == .locationOff)
        source.send(.sample(sample(0)))
        #expect(await waitForSamples(tracker, 1))
        #expect(await tracker.status(reservationID: id) == .tracking)
    }

    @Test func sessionsAreIndependentPerReservation() async {
        let source = ScriptedWalkSource()
        let tracker = LiveWalkTracker(source: source)
        let other = UUID()
        await tracker.begin(reservationID: id, destination: destination)
        await tracker.begin(reservationID: other, destination: destination)
        _ = await tracker.finish(reservationID: id)
        #expect(await tracker.status(reservationID: id) == .idle)
        #expect(await tracker.status(reservationID: other) == .tracking)
    }
}
