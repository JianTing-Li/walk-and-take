//
//  WalkRewardLadder.swift
//  WalkAndTakeKit
//
//  Lifetime-mile milestones: 1, 5, 15, then every 10 miles (25, 35, ...).
//  Each milestone banks one 50%-off-one-bag reward.
//

import Foundation

public enum WalkRewardLadder {
    public static let discountPercent = 50
    /// Most miles one pickup can add to progress.
    public static let maxMilesPerPickup = 2.0

    private static let opening: [Double] = [1, 5, 15]
    private static let loopStep = 10.0
    private static let tolerance = 1e-9

    /// The mileage of the milestone at a zero-based index.
    public static func milestone(at index: Int) -> Double {
        index < opening.count
            ? opening[index] : opening[opening.count - 1] + Double(index - opening.count + 1) * loopStep
    }

    /// How many milestones a lifetime total has reached.
    public static func milestonesReached(totalMiles: Double) -> Int {
        var count = 0
        while milestone(at: count) <= totalMiles + tolerance { count += 1 }
        return count
    }

    /// The next milestone strictly above the total.
    public static func nextMilestone(after totalMiles: Double) -> Double {
        milestone(at: milestonesReached(totalMiles: totalMiles))
    }

    public static func milesToNext(totalMiles: Double) -> Double {
        max(0, nextMilestone(after: totalMiles) - totalMiles)
    }

    /// Milestones newly reached when progress moves from `oldTotal` to `newTotal`, in order.
    public static func milestonesCrossed(from oldTotal: Double, to newTotal: Double) -> [Double] {
        let before = milestonesReached(totalMiles: oldTotal)
        let after = milestonesReached(totalMiles: newTotal)
        guard after > before else { return [] }
        return (before..<after).map(milestone(at:))
    }

    /// Progress from the last milestone to the next, from 0 to 1.
    public static func progressFraction(totalMiles: Double) -> Double {
        let reached = milestonesReached(totalMiles: totalMiles)
        let lower = reached == 0 ? 0 : milestone(at: reached - 1)
        let upper = milestone(at: reached)
        return min(1, max(0, (totalMiles - lower) / (upper - lower)))
    }

    /// What one pickup of `distanceMiles` would add, before the per-pickup cap.
    public static func expectedMiles(forDistance distanceMiles: Double) -> Double {
        min(max(0, distanceMiles), maxMilesPerPickup)
    }
}
