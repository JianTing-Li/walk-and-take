//
//  SimulatedWalkTracker.swift
//  WalkAndTake
//
//  DEBUG only (`-UITestSimulateWalk`): stands in for GPS so a walk can be demoed and UI-tested
//  in the simulator. Each walk is a steady 3 mph stroll that starts 0.5 mi south of the
//  restaurant and ends at its door.
//

#if DEBUG
    import Domain
    import Foundation
    import Platform

    actor SimulatedWalkTracker: WalkTracking {
        private var destinations: [UUID: Coordinate] = [:]
        private var startedAt: [UUID: Date] = [:]
        /// How long the stand-in walk takes to reach the door, so progress can be watched live.
        private let demoDuration: TimeInterval = 24

        func begin(reservationID: UUID, destination: Coordinate) {
            destinations[reservationID] = destination
            startedAt[reservationID] = .now
        }

        func status(reservationID: UUID) -> WalkTrackingStatus {
            destinations[reservationID] == nil ? .idle : .tracking
        }

        /// The part of the walk "recorded" so far: it advances about every two seconds.
        func samples(reservationID: UUID) -> [WalkSample] {
            guard let destination = destinations[reservationID], let begun = startedAt[reservationID] else { return [] }
            let track = Self.track(to: destination)
            let share = min(1, Date.now.timeIntervalSince(begun) / demoDuration)
            let count = max(0, min(track.count, Int((Double(track.count) * share).rounded(.down)) + 1))
            return Array(track.prefix(count))
        }

        /// Stopping records the whole walk, as if the customer had arrived.
        func finish(reservationID: UUID) -> [WalkSample] {
            startedAt[reservationID] = nil
            guard let destination = destinations.removeValue(forKey: reservationID) else { return [] }
            return Self.track(to: destination)
        }

        /// 0.5 mi due south of `destination`, walked at 3 mph in 12 steps ending now.
        private static func track(to destination: Coordinate) -> [WalkSample] {
            let miles = 0.5
            let milesPerDegree = 3958.8 * .pi / 180
            let steps = 12
            let duration = miles / 3 * 3600
            let start = Date.now.addingTimeInterval(-duration)
            return (0...steps).map { i in
                let remaining = miles * (1 - Double(i) / Double(steps))
                return WalkSample(
                    coordinate: Coordinate(
                        latitude: destination.latitude - remaining / milesPerDegree, longitude: destination.longitude),
                    timestamp: start.addingTimeInterval(duration * Double(i) / Double(steps)))
            }
        }
    }
#endif
