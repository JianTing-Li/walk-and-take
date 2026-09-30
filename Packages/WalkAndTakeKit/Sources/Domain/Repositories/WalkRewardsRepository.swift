//
//  WalkRewardsRepository.swift
//  WalkAndTakeKit
//

import Foundation

/// What finishing a walk produced.
public struct WalkCompletion: Hashable, Sendable {
    public var walk: Walk
    /// Rewards newly banked because a milestone was crossed, in order.
    public var newRewards: [Reward]
    /// Lifetime credited miles after this walk.
    public var totalMiles: Double

    public init(walk: Walk, newRewards: [Reward], totalMiles: Double) {
        self.walk = walk
        self.newRewards = newRewards
        self.totalMiles = totalMiles
    }
}

public enum WalkRewardsError: Error, Hashable, Sendable {
    case walkNotFound
    case rewardNotFound
    case rewardAlreadyRedeemed
}

/// Walks, lifetime miles and banked rewards. Miles are the sum of credited walks, so they never reset.
public protocol WalkRewardsRepository: Sendable {
    func walks() async throws -> [Walk]
    func rewards() async throws -> [Reward]
    func totalMiles() async throws -> Double
    func walk(reservationID: UUID) async throws -> Walk?
    /// Starts a walk for a reservation. Calling it again returns the walk already started.
    func startWalk(reservationID: UUID, restaurantID: String, at now: Date) async throws -> Walk
    /// Records the verdict, credits miles and banks any rewards earned. Finishing twice changes nothing.
    /// A second credited pickup from the same restaurant on the same `calendar` day earns no miles.
    func finishWalk(
        reservationID: UUID, verdict: WalkVerdict, at now: Date, calendar: Calendar
    ) async throws -> WalkCompletion
    /// Marks a banked reward as used by a reservation. Throws if it is already used.
    func redeemReward(id: UUID, reservationID: UUID, at now: Date) async throws -> Reward
    /// Undoes `redeemReward` for a reservation, e.g. when the reservation could not be made.
    func releaseReward(reservationID: UUID) async throws
    func changes() -> AsyncStream<UserDataChange>
}
