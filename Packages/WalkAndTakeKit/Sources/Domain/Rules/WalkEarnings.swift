//
//  WalkEarnings.swift
//  WalkAndTakeKit
//
//  What one finished walk added to the customer's lifetime miles, worked out from their walk
//  history alone, so it reads the same right after the pickup and on any later visit.
//

import Foundation

public struct WalkEarnings: Hashable, Sendable {
    /// Miles this pickup added.
    public var milesEarned: Double
    /// Lifetime credited miles just before this pickup.
    public var totalBefore: Double
    /// Lifetime credited miles including this pickup.
    public var totalAfter: Double
    /// Milestones this pickup reached (each one banked a reward).
    public var unlockedMilestones: [Double]
    /// This pickup's place among the customer's credited pickups, starting at 1.
    public var walkNumber: Int

    public var milesToNextReward: Double { WalkRewardLadder.milesToNext(totalMiles: totalAfter) }
    public var nextMilestone: Double { WalkRewardLadder.nextMilestone(after: totalAfter) }
    public var catchphrase: String { WalkCatchphrases.phrase(forWalkNumber: walkNumber) }

    /// Nil unless `walk` finished and earned miles. Walks are ordered by when they finished.
    public static func of(_ walk: Walk, in walks: [Walk]) -> WalkEarnings? {
        guard walk.finishedAt != nil, walk.creditedMiles > 0 else { return nil }
        let credited = walks.filter { $0.finishedAt != nil && $0.creditedMiles > 0 }.sorted(by: finishedBefore)
        guard let index = credited.firstIndex(where: { $0.id == walk.id }) else { return nil }
        let before = credited[..<index].reduce(0) { $0 + $1.creditedMiles }
        let after = before + walk.creditedMiles
        return WalkEarnings(
            milesEarned: walk.creditedMiles,
            totalBefore: before,
            totalAfter: after,
            unlockedMilestones: WalkRewardLadder.milestonesCrossed(from: before, to: after),
            walkNumber: index + 1)
    }

    private static func finishedBefore(_ a: Walk, _ b: Walk) -> Bool {
        let (fa, fb) = (a.finishedAt ?? .distantFuture, b.finishedAt ?? .distantFuture)
        if fa != fb { return fa < fb }
        if a.startedAt != b.startedAt { return a.startedAt < b.startedAt }
        return a.id.uuidString < b.id.uuidString
    }
}
