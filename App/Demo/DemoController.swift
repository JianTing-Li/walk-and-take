//
//  DemoController.swift
//  WalkAndTake
//
//  Developer mode's demo actions. The only place that knows the concrete clock (and, as more
//  actions land, the stores and the demo walk tracker); screens see just `DemoControlling`.
//

import CustomerFeatures
import Foundation
import Platform

@MainActor
final class DemoController: DemoControlling {
    private let clock: AdjustableClock

    init(clock: AdjustableClock) {
        self.clock = clock
    }

    // MARK: Time

    var now: Date { clock.now }
    var isTimeLive: Bool { clock.isLive }
    func travel(to date: Date) { clock.travel(to: date) }
    func advanceTime(by interval: TimeInterval) { clock.advance(by: interval) }
    func resetTimeToLive() { clock.resetToLive() }
}
