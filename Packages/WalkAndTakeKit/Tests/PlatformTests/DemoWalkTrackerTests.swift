//
//  DemoWalkTrackerTests.swift
//  PlatformTests
//

import Domain
import Foundation
import Synchronization
import Testing

@testable import Platform

/// A wall clock the test moves by hand.
final class TestWallClock: Sendable {
    private let date = Mutex(Date(timeIntervalSince1970: 1_000_000))
    var now: Date { date.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { date.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

private struct At: LocationProvider {
    let coordinate: Coordinate
    func resolve() async -> ResolvedLocation { ResolvedLocation(coordinate: coordinate, source: .device) }
}

@Suite("Demo walk tracker")
struct DemoWalkTrackerTests {
    let id = UUID()
    let home = ServiceArea.longIslandCity.center
    /// About 0.7 mi north-east of the center.
    let door = Coordinate(latitude: 40.7525, longitude: -73.9380)
    let clock = TestWallClock()

    func tracker(from start: Coordinate? = nil, autoWalk seconds: Int = 20) -> DemoWalkTracker {
        let clock = clock
        return DemoWalkTracker(location: At(coordinate: start ?? home), autoWalkSeconds: { seconds }) { clock.now }
    }

    func progress(_ tracker: DemoWalkTracker) async -> WalkProgress? {
        WalkVerifier.progress(samples: await tracker.samples(reservationID: id), destination: door)
    }

    @Test func theRouteRunsFromWhereYouAreToTheDoor() async throws {
        let tracker = tracker()
        await tracker.begin(reservationID: id, destination: door)
        #expect(await tracker.status(reservationID: id) == .tracking)
        let start = try #require(await progress(tracker))
        #expect(start.creditedMiles == 0)
        #expect(abs(start.milesToGo - home.distanceMiles(to: door)) < 0.01)
    }

    @Test func autoWalkReachesTheDoorInTheSetTime() async throws {
        let tracker = tracker(autoWalk: 20)
        await tracker.begin(reservationID: id, destination: door)
        clock.advance(10)
        let halfway = try #require(await progress(tracker))
        #expect(abs(halfway.fraction - 0.5) < 0.05)
        #expect(await tracker.isAutoWalking(id))
        clock.advance(15)
        let done = try #require(await progress(tracker))
        #expect(done.fraction > 0.99)
        #expect(!(await tracker.isAutoWalking(id)))
    }

    @Test func aFinishedRouteIsCreditedForItsFullDistance() async {
        let tracker = tracker()
        await tracker.begin(reservationID: id, destination: door)
        await tracker.arrive(id)  // seconds after starting
        let verdict = WalkVerifier.verify(samples: await tracker.finish(reservationID: id), destination: door)
        guard case .credited(let miles) = verdict else {
            Issue.record("expected a credited walk, got \(verdict)")
            return
        }
        #expect(abs(miles - home.distanceMiles(to: door)) < 0.02)
        #expect(await tracker.status(reservationID: id) == .idle)
    }

    @Test func stepsPauseAutoWalkAndStopAtTheDoor() async throws {
        let tracker = tracker()
        await tracker.begin(reservationID: id, destination: door)
        await tracker.advance(id, miles: 0.1)
        #expect(!(await tracker.isAutoWalking(id)))
        clock.advance(30)  // paused: no further progress
        #expect(abs(try #require(await progress(tracker)).creditedMiles - 0.1) < 0.011)
        await tracker.advance(id, miles: 5)
        #expect(try #require(await progress(tracker)).fraction > 0.99)
    }

    @Test func autoWalkResumesFromWhereItPaused() async throws {
        let tracker = tracker(autoWalk: 20)
        await tracker.begin(reservationID: id, destination: door)
        await tracker.pause(id)
        await tracker.autoWalk(id)
        clock.advance(20)
        #expect(try #require(await progress(tracker)).fraction > 0.99)
    }

    @Test func confirmingBeforeArrivingEndsFarFromTheDoor() async {
        let tracker = tracker()
        await tracker.begin(reservationID: id, destination: door)
        await tracker.advance(id, miles: 0.2)
        let verdict = WalkVerifier.verify(samples: await tracker.finish(reservationID: id), destination: door)
        #expect(verdict == .rejected(.endedFarFromRestaurant))
    }

    @Test func startingAtTheDoorWalksFromHalfAMileAway() async throws {
        let tracker = tracker(from: door)
        await tracker.begin(reservationID: id, destination: door)
        #expect(abs(try #require(await progress(tracker)).milesToGo - DemoWalkTracker.fallbackMiles) < 0.01)
    }
}

@Suite("Switching walk tracker")
struct SwitchingWalkTrackerTests {
    let id = UUID()
    let door = Coordinate(latitude: 40.7525, longitude: -73.9380)

    func demo() -> DemoWalkTracker {
        DemoWalkTracker(location: At(coordinate: ServiceArea.longIslandCity.center), autoWalkSeconds: { 20 })
    }

    @Test func simulatedWalksGoToTheDemoTracker() async {
        let demo = demo()
        let tracker = SwitchingWalkTracker(live: LiveWalkTracker(source: ScriptedWalkSource()), demo: demo) { true }
        await tracker.begin(reservationID: id, destination: door)
        #expect(await demo.isTracking(id))
        #expect(await tracker.samples(reservationID: id).count >= 2)
        _ = await tracker.finish(reservationID: id)
        #expect(!(await demo.isTracking(id)))
    }

    @Test func otherWalksUseGPS() async {
        let demo = demo()
        let live = LiveWalkTracker(source: ScriptedWalkSource())
        let tracker = SwitchingWalkTracker(live: live, demo: demo) { false }
        await tracker.begin(reservationID: id, destination: door)
        #expect(!(await demo.isTracking(id)))
        #expect(await live.status(reservationID: id) != .idle)
    }

    @Test func aWalkKeepsItsTrackerWhenTheSwitchFlips() async {
        let demo = demo()
        let simulate = Mutex(true)
        let tracker = SwitchingWalkTracker(live: LiveWalkTracker(source: ScriptedWalkSource()), demo: demo) {
            simulate.withLock { $0 }
        }
        await tracker.begin(reservationID: id, destination: door)
        simulate.withLock { $0 = false }
        await tracker.begin(reservationID: id, destination: door)  // e.g. the pickup screen resuming
        #expect(await tracker.status(reservationID: id) == .tracking)
        #expect(await demo.isTracking(id))
    }
}
