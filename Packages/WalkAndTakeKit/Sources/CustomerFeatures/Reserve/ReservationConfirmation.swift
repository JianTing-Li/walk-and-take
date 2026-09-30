//
//  ReservationConfirmation.swift
//  WalkAndTakeKit
//

import DesignSystem
import Domain
import Foundation
import Platform

/// What the confirmation sheet shows, worded from the reservation's snapshot.
public struct ReservationConfirmation: Identifiable, Hashable, Sendable {
    /// The success message shown when a walking reward was used on this reservation.
    public struct RewardRedeemed: Hashable, Sendable {
        /// "Reward redeemed"
        public let title: String
        /// "50% off one bag saved you $2.99."
        public let detail: String
        /// "1 more reward is ready to use.", or a nudge to keep walking after the last one.
        public let footer: String
    }

    public let id: UUID
    public let restaurantName: String
    public let code: String
    /// "Pick up tomorrow, Fri Sep 25, 7:30–10:00 AM"
    public let pickupText: String
    public let pickupInstructions: String
    public let address: String
    public let bagsText: String
    public let totalText: String
    /// "50% off one bag: −$2.75", or nil when no reward was used.
    public let rewardText: String?
    /// Nil when no reward was used.
    public let rewardRedeemed: RewardRedeemed?
    /// Why the pickup must be walked to earn miles, and when Start walk opens. Nil when walking rewards are off.
    public let walkReminderText: String?
    /// "Free changes and cancellation until 9:50 AM. …", or nil when changes are off.
    public let policyText: String

    init(
        reservation: Reservation, now: Date, showsChangePolicy: Bool, showsWalkReminder: Bool = false,
        rewardsLeft: Int = 0
    ) {
        let snapshot = reservation.snapshot
        let calendar = NYCalendar.calendar
        id = reservation.id
        restaurantName = snapshot.restaurantName
        code = reservation.confirmationCode
        pickupText = PickupDayFormatter.full(snapshot.pickupWindow, now: now, calendar: calendar)
        pickupInstructions = snapshot.pickupInstructions
        address = snapshot.address.shortLine
        bagsText = "\(reservation.quantity) × \(snapshot.bagName)"
        totalText = reservation.total.usd
        rewardText =
            reservation.rewardID == nil
            ? nil : "\(WalkRewardLadder.discountPercent)% off one bag: −\(reservation.discount.usd)"
        rewardRedeemed =
            reservation.rewardID == nil
            ? nil : WalkCopy.rewardRedeemed(discount: reservation.discount, rewardsLeft: rewardsLeft)
        walkReminderText =
            showsWalkReminder
            ? WalkCopy.confirmationReminder(
                startOpensAt: WalkPolicy.startOpensAt(for: reservation), now: now, calendar: calendar)
            : nil
        let findIt = "Find this order anytime in the Orders tab."
        if showsChangePolicy {
            let deadline = TimeText.time(ReservationPolicy.changeDeadline(for: reservation), calendar: calendar)
            policyText = "Free changes and cancellation until \(deadline). \(findIt)"
        } else {
            policyText = findIt
        }
    }
}
