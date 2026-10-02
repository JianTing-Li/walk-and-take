//
//  DemoController.swift
//  WalkAndTake
//
//  Developer mode's demo actions. The only place that knows the concrete clock, store and demo
//  walk tracker; screens see just `DemoControlling`.
//

import CustomerFeatures
import Domain
import Foundation
import MockData
import Platform

@MainActor
final class DemoController: DemoControlling {
    private let clock: AdjustableClock
    private let walks: DemoWalkTracker
    private let userData: UserDataStore

    init(clock: AdjustableClock, walks: DemoWalkTracker, userData: UserDataStore) {
        self.clock = clock
        self.walks = walks
        self.userData = userData
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

    // MARK: Rewards

    func addMiles(_ miles: Double) async -> [Reward] {
        // Each demo walk gets its own store ID, so the one-pickup-per-store-per-day rule never blocks it.
        let id = UUID()
        let now = clock.now
        do {
            _ = try await userData.startWalk(
                reservationID: id, restaurantID: "\(Walk.demoRestaurantPrefix)-\(id.uuidString)", at: now)
            return try await userData.finishWalk(
                reservationID: id, verdict: .credited(miles: miles), at: now, calendar: .current
            ).newRewards
        } catch {
            return []
        }
    }

    func completeNextMilestone() async -> [Reward] {
        let total = (try? await userData.totalMiles()) ?? 0
        // A hair over, so rounding never leaves the total just short of the milestone.
        return await addMiles(WalkRewardLadder.milesToNext(totalMiles: total) + 1e-6)
    }

    func grantReward() async -> Reward? {
        let total = (try? await userData.totalMiles()) ?? 0
        return try? await userData.bankReward(
            milestoneMiles: WalkRewardLadder.nextMilestone(after: total), at: clock.now)
    }

    func clearWalksAndRewards() async {
        try? await userData.clearWalksAndRewards()
    }
}
