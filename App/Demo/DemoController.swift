//
//  DemoController.swift
//  WalkAndTake
//
//  Developer mode's demo actions. The only place that knows the concrete clock (and, as more
//  actions land, the stores); screens see just `DemoControlling`.
//

import CustomerFeatures
import Foundation
import Platform

@MainActor
final class DemoController: DemoControlling {
    private let clock: AdjustableClock
    private let walks: DemoWalkTracker

    init(clock: AdjustableClock, walks: DemoWalkTracker) {
        self.clock = clock
        self.walks = walks
    }

    // MARK: Time

    var now: Date { clock.now }
    var isTimeLive: Bool { clock.isLive }
    func travel(to date: Date) { clock.travel(to: date) }
    func advanceTime(by interval: TimeInterval) { clock.advance(by: interval) }
    func resetTimeToLive() { clock.resetToLive() }

    // MARK: Walks

    func isSimulatedWalk(_ reservationID: UUID) async -> Bool { await walks.isTracking(reservationID) }
    func isAutoWalking(_ reservationID: UUID) async -> Bool { await walks.isAutoWalking(reservationID) }
    func advanceWalk(_ reservationID: UUID, miles: Double) async { await walks.advance(reservationID, miles: miles) }
    func arriveWalk(_ reservationID: UUID) async { await walks.arrive(reservationID) }
    func autoWalk(_ reservationID: UUID) async { await walks.autoWalk(reservationID) }
    func pauseWalk(_ reservationID: UUID) async { await walks.pause(reservationID) }
}
