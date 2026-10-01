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

    /// "0.7 mi walk · about 11 min" (15 minutes per mile).
    static func walkTitleWithTime(forDistance distance: Double) -> String {
        "\(walkTitle(forDistance: distance)) · about \(WalkEstimate.minutes(forMiles: distance)) min"
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

    /// At the door: within the radius the final check accepts as "arrived".
    static func isAtDoor(_ progress: WalkProgress) -> Bool {
        progress.milesToGo <= WalkVerifier.endRadiusMiles
    }

    /// "0.3 mi walked"
    static func walkedText(_ progress: WalkProgress) -> String {
        "\(miles(progress.creditedMiles)) mi walked"
    }

    /// "0.3 mi walked · 0.2 mi to go"
    static func progressText(_ progress: WalkProgress) -> String {
        "\(walkedText(progress)) · \(miles(progress.milesToGo)) mi to go"
    }

    /// Tick marks every 0.1 mi along a walk (every 0.25 mi past a mile), as 0...1 positions.
    static func walkTicks(forDistance distance: Double) -> [Double] {
        MilestoneProgressBar.ticks(from: 0, to: distance, every: distance <= 1 ? 0.1 : 0.25)
    }

    // MARK: Earned

    /// The card after a walked pickup, from what that pickup added to the customer's history.
    static func earnedCard(_ earnings: WalkEarnings) -> WalkEarnedCard.Content {
        let discount = "\(WalkRewardLadder.discountPercent)% off one bag"
        let earned = miles(earnings.milesEarned)
        return WalkEarnedCard.Content(
            headline: "+\(earned) mi earned",
            catchphrase: earnings.catchphrase,
            contribution: "Walked pickup #\(earnings.walkNumber)",
            progress:
                "\(miles(earnings.totalAfter)) mi walked in total · "
                + "\(miles(earnings.milesToNextReward)) mi to your next reward",
            unlock: earnings.unlockedMilestones.isEmpty
                ? nil
                : earnings.unlockedMilestones.count == 1
                    ? "Reward unlocked: \(discount)"
                    : "\(earnings.unlockedMilestones.count) rewards unlocked: \(discount) each")
    }

    // MARK: Redeemed

    /// The message after a reward is used: what it saved, and how many are left.
    static func rewardRedeemed(discount: Money, rewardsLeft: Int) -> ReservationConfirmation.RewardRedeemed {
        let footer =
            switch rewardsLeft {
            case ..<1: "That was your last reward. Keep walking to earn the next one."
            case 1: "1 more reward is ready to use."
            default: "\(rewardsLeft) more rewards are ready to use."
            }
        return ReservationConfirmation.RewardRedeemed(
            title: "Reward redeemed",
            detail: "\(WalkRewardLadder.discountPercent)% off one bag saved you \(discount.usd).",
            footer: footer)
    }
}
