//
//  WalkCopy.swift
//  WalkAndTakeKit
//
//  The walking-reward wording shared by Discover, the map and Offer Detail.
//

import DesignSystem
import Domain
import Foundation
import Platform

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

    /// How an offer compares with the nearest reservable one, by walking distance.
    /// "Nearest bag", or "0.4 mi farther than the nearest · earns 0.4 mi more". Distances are compared as shown
    /// (rounded to a tenth) so the line always agrees with the "0.5 mi away" text.
    static func compareText(distance: Double, nearest: Double) -> String? {
        let shown = (distance * 10).rounded() / 10
        let base = (nearest * 10).rounded() / 10
        let farther = shown - base
        guard farther > 0.05 else { return "Nearest bag" }
        // Earned miles come from the same rounded distances, so "farther" and "earns more" agree.
        let extra = ((earnedMiles(forDistance: shown) - earnedMiles(forDistance: base)) * 10).rounded() / 10
        var text = "\(miles(farther)) mi farther than the nearest"
        if extra > 0.05 { text += " · earns \(miles(extra)) mi more" }
        return text
    }

    /// After-pickup progress: "After this pickup: 1.7 of 5 mi · 3.3 mi to go", or just the total once a
    /// milestone is reached (the unlock line carries the news).
    static func outcomeText(currentMiles: Double, distance: Double) -> String {
        let after = currentMiles + earnedMiles(forDistance: distance)
        if WalkRewardLadder.milestonesCrossed(from: currentMiles, to: after).isEmpty {
            let next = WalkRewardLadder.nextMilestone(after: after)
            let toGo = WalkRewardLadder.milesToNext(totalMiles: after)
            return "After this pickup: \(miles(after)) of \(milestone(next)) mi · \(miles(toGo)) mi to go"
        }
        return "After this pickup: \(miles(after)) mi walked"
    }

    /// "Unlocks a reward: 50% off one bag" when this pickup reaches a milestone.
    static func unlockText(currentMiles: Double, distance: Double) -> String? {
        let crossed = WalkRewardLadder.milestonesCrossed(
            from: currentMiles, to: currentMiles + earnedMiles(forDistance: distance)
        ).count
        guard crossed > 0 else { return nil }
        let discount = "\(WalkRewardLadder.discountPercent)% off one bag"
        return crossed == 1 ? "Unlocks a reward: \(discount)" : "Unlocks \(crossed) rewards: \(discount) each"
    }

    // MARK: Reminders

    /// Reserve bar: miles only count for walkers who start the walk in the app.
    static let reserveReminder = "Miles count only if you walk to pickup and tap Start walk on your order."

    /// Confirmation sheet: when Start walk opens, and that driving or riding earns nothing.
    static func confirmationReminder(startOpensAt: Date, now: Date, calendar: Calendar) -> String {
        let steps = "then swipe to confirm when you arrive. Driving or riding earns no miles."
        guard startOpensAt > now else {
            return "Walk to count your miles: tap Start walk on this order, \(steps)"
        }
        let time = TimeText.time(startOpensAt, calendar: calendar)
        let when =
            calendar.isDate(startOpensAt, inSameDayAs: now)
            ? "at \(time)" : "on \(TimeText.shortDate(startOpensAt, calendar: calendar)) at \(time)"
        return "Walk to count your miles: Start walk opens \(when) on this order. Tap it, \(steps)"
    }

    // MARK: Live progress

    /// "0.3 mi walked · 0.2 mi to go", or "You've arrived" once at the door.
    static func progressText(_ progress: WalkProgress) -> String {
        let arrived = progress.milesToGo * 1609.344 <= WalkVerifier.endRadiusMiles * 1609.344
        let walked = "\(miles(progress.creditedMiles, places: 2)) mi walked"
        return arrived
            ? "\(walked) · You're at the door" : "\(walked) · \(miles(progress.milesToGo, places: 2)) mi to go"
    }

    /// "Counting +0.30 mi so far" once some of the walk counts.
    static func countingText(_ progress: WalkProgress) -> String? {
        progress.creditedMiles > 0 ? "Counting +\(miles(progress.creditedMiles, places: 2)) mi so far" : nil
    }

    // MARK: Earned

    /// The card after a walked pickup, from what that pickup added to the customer's history.
    static func earnedCard(_ earnings: WalkEarnings) -> WalkEarnedCard.Content {
        let discount = "\(WalkRewardLadder.discountPercent)% off one bag"
        let earned = miles(earnings.milesEarned, places: 2)
        return WalkEarnedCard.Content(
            headline: "+\(earned) mi earned",
            catchphrase: earnings.catchphrase,
            contribution: "Walked pickup #\(earnings.walkNumber) · added \(earned) mi",
            progress:
                "\(miles(earnings.totalAfter, places: 2)) mi walked in total · "
                + "\(miles(earnings.milesToNextReward, places: 2)) mi to your next reward",
            unlock: earnings.unlockedMilestones.isEmpty
                ? nil
                : earnings.unlockedMilestones.count == 1
                    ? "Reward unlocked: \(discount)"
                    : "\(earnings.unlockedMilestones.count) rewards unlocked: \(discount) each")
    }
}
