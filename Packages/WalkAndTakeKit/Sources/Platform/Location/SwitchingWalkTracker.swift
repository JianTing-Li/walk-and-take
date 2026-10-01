//
//  SwitchingWalkTracker.swift
//  WalkAndTakeKit
//

import Domain
import Foundation

/// Sends each walk to GPS or to Developer mode's simulated walks, decided when the walk begins.
public actor SwitchingWalkTracker: WalkTracking {
    public let demo: DemoWalkTracker
    private let live: any WalkTracking
    private let useDemo: @Sendable () async -> Bool

    /// - Parameter useDemo: Whether a walk beginning now is simulated.
    public init(live: any WalkTracking, demo: DemoWalkTracker, useDemo: @escaping @Sendable () async -> Bool) {
        self.live = live
        self.demo = demo
        self.useDemo = useDemo
    }

    public func begin(reservationID: UUID, destination: Coordinate) async {
        if await demo.isTracking(reservationID) { return }
        if await live.status(reservationID: reservationID) != .idle { return }
        if await useDemo() {
            await demo.begin(reservationID: reservationID, destination: destination)
        } else {
            await live.begin(reservationID: reservationID, destination: destination)
        }
    }

    public func status(reservationID: UUID) async -> WalkTrackingStatus {
        await tracker(for: reservationID).status(reservationID: reservationID)
    }

    public func samples(reservationID: UUID) async -> [WalkSample] {
        await tracker(for: reservationID).samples(reservationID: reservationID)
    }

    public func finish(reservationID: UUID) async -> [WalkSample] {
        await tracker(for: reservationID).finish(reservationID: reservationID)
    }

    private func tracker(for reservationID: UUID) async -> any WalkTracking {
        await demo.isTracking(reservationID) ? demo : live
    }
}
