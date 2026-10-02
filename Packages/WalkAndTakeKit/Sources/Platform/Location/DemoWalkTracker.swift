//
//  DemoWalkTracker.swift
//  WalkAndTakeKit
//
//  Developer mode's simulated walks: a straight route from where you are to the restaurant's door,
//  walked on its own (auto-walk) or nudged along with the demo buttons. The fixes are paced like a
//  real 3 mph walk, so `WalkVerifier` credits a finished route exactly as it would a real one.
//

import Domain
import Foundation

public actor DemoWalkTracker: WalkTracking {
    private struct Route {
        var start: Coordinate
        var destination: Coordinate
        var miles: Double
        /// Miles walked, as of `since` when auto-walking.
        var walked = 0.0
        /// Auto-walk: when it (re)started, and how long the whole route takes.
        var autoSince: Date?
        var autoDuration: TimeInterval

        /// Miles walked right now.
        func walked(at now: Date) -> Double {
            guard let autoSince, autoDuration > 0 else { return walked }
            let speed = miles / autoDuration
            return min(miles, walked + speed * now.timeIntervalSince(autoSince))
        }
    }

    /// Walking pace of the generated fixes.
    public static let paceMph = 3.0
    /// Miles between generated fixes.
    static let stepMiles = 0.02
    /// A start this close to the door would make no walk, so the route starts this far south instead.
    static let fallbackMiles = 0.5

    private let location: any LocationProvider
    private let autoWalkSeconds: @Sendable () async -> Int
    private let now: @Sendable () -> Date
    private var routes: [UUID: Route] = [:]

    /// - Parameters:
    ///   - location: Where a walk starts.
    ///   - autoWalkSeconds: How long auto-walk takes to reach the door.
    ///   - now: Wall-clock time (not the app clock, which may be frozen or time traveling).
    public init(
        location: any LocationProvider,
        autoWalkSeconds: @escaping @Sendable () async -> Int,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.location = location
        self.autoWalkSeconds = autoWalkSeconds
        self.now = now
    }

    // MARK: WalkTracking

    /// Starts the route and walks it on its own.
    public func begin(reservationID: UUID, destination: Coordinate) async {
        guard routes[reservationID] == nil else { return }
        var start = await location.resolve().coordinate
        if start.distanceMiles(to: destination) < 0.05 {
            let milesPerDegree = 3958.8 * .pi / 180
            start = Coordinate(
                latitude: destination.latitude - Self.fallbackMiles / milesPerDegree, longitude: destination.longitude)
        }
        let duration = TimeInterval(await autoWalkSeconds())
        guard routes[reservationID] == nil else { return }  // begun again while resolving
        routes[reservationID] = Route(
            start: start, destination: destination, miles: start.distanceMiles(to: destination),
            autoSince: now(), autoDuration: duration)
    }

    public func status(reservationID: UUID) -> WalkTrackingStatus {
        routes[reservationID] == nil ? .idle : .tracking
    }

    public func samples(reservationID: UUID) -> [WalkSample] {
        guard let route = routes[reservationID] else { return [] }
        return Self.track(route, walked: route.walked(at: now()), endingAt: now())
    }

    /// Stops and returns the route walked so far. Confirming before arriving ends far from the door,
    /// so the verifier rejects it, just like a real walk.
    public func finish(reservationID: UUID) -> [WalkSample] {
        guard let route = routes.removeValue(forKey: reservationID) else { return [] }
        return Self.track(route, walked: route.walked(at: now()), endingAt: now())
    }

    // MARK: Demo controls

    public func isTracking(_ reservationID: UUID) -> Bool { routes[reservationID] != nil }

    public func isAutoWalking(_ reservationID: UUID) -> Bool {
        guard let route = routes[reservationID], route.autoSince != nil else { return false }
        return route.walked(at: now()) < route.miles
    }

    /// Steps forward (pausing auto-walk), never past the door.
    public func advance(_ reservationID: UUID, miles: Double) {
        guard var route = routes[reservationID] else { return }
        route.walked = min(route.miles, route.walked(at: now()) + miles)
        route.autoSince = nil
        routes[reservationID] = route
    }

    /// Straight to the door.
    public func arrive(_ reservationID: UUID) {
        advance(reservationID, miles: .infinity)
    }

    /// Walks the rest of the way on its own, at the auto-walk pace.
    public func autoWalk(_ reservationID: UUID) async {
        let duration = TimeInterval(await autoWalkSeconds())
        guard var route = routes[reservationID] else { return }
        route.walked = route.walked(at: now())
        route.autoSince = now()
        route.autoDuration = duration
        routes[reservationID] = route
    }

    public func pause(_ reservationID: UUID) {
        advance(reservationID, miles: 0)
    }

    // MARK: Track

    /// Fixes every `stepMiles` from the start to `walked`, timed at `paceMph` so the last one is `end`.
    private static func track(_ route: Route, walked: Double, endingAt end: Date) -> [WalkSample] {
        let secondsPerMile = 3600 / paceMph
        var distances = Array(stride(from: 0, to: walked, by: stepMiles))
        distances.append(walked)
        if distances.count < 2 { distances.insert(0, at: 0) }  // standing at the start still shows the bar
        return distances.enumerated().map { index, distance in
            let share = route.miles > 0 ? distance / route.miles : 1
            let coordinate = Coordinate(
                latitude: route.start.latitude + (route.destination.latitude - route.start.latitude) * share,
                longitude: route.start.longitude + (route.destination.longitude - route.start.longitude) * share)
            // A standing start gets one second between its two fixes.
            let seconds = walked > 0 ? (walked - distance) * secondsPerMile : Double(distances.count - 1 - index)
            return WalkSample(coordinate: coordinate, timestamp: end.addingTimeInterval(-seconds))
        }
    }
}
