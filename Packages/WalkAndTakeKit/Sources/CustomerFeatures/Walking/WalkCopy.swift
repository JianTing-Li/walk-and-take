//
//  WalkCopy.swift
//  WalkAndTakeKit
//
//  The walking-reward wording shared by Discover, the map and Offer Detail.
//

import Domain
import Foundation

enum WalkCopy {
    /// "0.7"
    static func miles(_ miles: Double, places: Int = 1) -> String {
        String(format: "%.\(places)f", miles)
    }

    /// A milestone's mileage without a trailing ".0": "5", "15".
    static func milestone(_ miles: Double) -> String {
        miles == miles.rounded() ? String(format: "%.0f", miles) : self.miles(miles)
    }

    /// Miles a pickup this far away would add, after the per-pickup cap.
    static func earnedMiles(forDistance distance: Double) -> Double {
        WalkRewardLadder.expectedMiles(forDistance: distance)
    }

    /// "+0.7 mi toward a reward"
    static func rewardPill(forDistance distance: Double) -> String {
        "+\(miles(earnedMiles(forDistance: distance))) mi toward a reward"
    }

    /// "0.7 mi walk"
    static func walkTitle(forDistance distance: Double) -> String {
        "\(miles(distance)) mi walk"
    }

    /// "Earns +0.7 mi toward your next reward"
    static func earnsText(forDistance distance: Double) -> String {
        "Earns +\(miles(earnedMiles(forDistance: distance))) mi toward your next reward"
    }

    /// Explains the cap only when this walk is long enough to hit it.
    static func capNote(forDistance distance: Double) -> String? {
        distance > WalkRewardLadder.maxMilesPerPickup
            ? "One pickup can add up to \(miles(WalkRewardLadder.maxMilesPerPickup)) mi."
            : nil
    }
}
