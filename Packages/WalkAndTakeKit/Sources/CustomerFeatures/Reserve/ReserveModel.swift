//
//  ReserveModel.swift
//  WalkAndTakeKit
//

import Domain
import Foundation
import Observation
import Platform

/// Quantity, the reserve call, and what happens after: an alert or a confirmation.
@Observable
@MainActor
public final class ReserveModel {
    public enum Alert: Hashable, Identifiable, Sendable {
        /// Sold out, window closed, or the quantity is no longer possible.
        case noLongerAvailable
        /// Tomorrow's bags can't be reserved before 20:00 New York.
        case notOpenYet
        /// The chosen walking reward was already used.
        case rewardUnavailable
        /// Anything unexpected (e.g. storage).
        case failed

        public var id: Self { self }

        public var title: String {
            switch self {
            case .noLongerAvailable: "This bag is no longer available"
            case .notOpenYet: "Opens for reservations at 8 PM"
            case .rewardUnavailable: "That reward was already used"
            case .failed: "Something went wrong"
            }
        }

        public var message: String {
            switch self {
            case .noLongerAvailable: "It sold out or the pickup window ended. Try another bag nearby."
            case .notOpenYet: "Tomorrow's bags can be reserved from 8 PM tonight."
            case .rewardUnavailable: "Your bag wasn't reserved. Pick another reward, or reserve at full price."
            case .failed: "Your bag wasn't reserved. Please try again."
            }
        }
    }

    public var quantity = 1
    public private(set) var maxQuantity = 1
    public private(set) var isReserving = false
    public var alert: Alert?
    public var confirmation: ReservationConfirmation?
    /// Turn on to take the banked reward's 50% off one bag.
    public var useReward = false
    /// The oldest unused walking reward, if the flag is on.
    public private(set) var availableReward: Reward?
    public private(set) var unitPrice = Money.zero

    private let offerID: String
    private let dependencies: CustomerDependencies

    init(offerID: String, dependencies: CustomerDependencies) {
        self.offerID = offerID
        self.dependencies = dependencies
    }

    /// Keeps the stepper within 1…min(3, bags left).
    func update(quantityLeft: Int, unitPrice: Money) {
        maxQuantity = max(1, ReservationPolicy.maxQuantity(forNewReservationWithLeft: quantityLeft))
        quantity = min(max(quantity, 1), maxQuantity)
        self.unitPrice = unitPrice
    }

    /// Reloads the banked rewards. The toggle turns itself off if the reward is gone.
    func refreshRewards() async {
        guard dependencies.flags.walkRewards else {
            availableReward = nil
            useReward = false
            return
        }
        let rewards = (try? await dependencies.walkRewards.rewards()) ?? []
        availableReward = rewards.filter(\.isAvailable).min { $0.earnedAt < $1.earnedAt }
        if availableReward == nil { useReward = false }
    }

    public var showsRewardToggle: Bool { availableReward != nil }

    /// What the reward takes off: 50% of one bag. Zero when it isn't being used.
    public var rewardDiscount: Money {
        useReward && availableReward != nil ? unitPrice.discount(percent: WalkRewardLadder.discountPercent) : .zero
    }

    public var total: Money { unitPrice * quantity - rewardDiscount }

    public func reserve() async {
        guard !isReserving else { return }
        isReserving = true
        defer { isReserving = false }
        let now = dependencies.clock.now
        let reservationID = UUID()
        var rewardID: UUID?
        if useReward, let reward = availableReward {
            // Claim the reward first so it can only ever back one reservation.
            do {
                _ = try await dependencies.walkRewards.redeemReward(
                    id: reward.id, reservationID: reservationID, at: now)
                rewardID = reward.id
            } catch {
                await refreshRewards()
                alert = .rewardUnavailable
                return
            }
        }
        do {
            let reservation = try await dependencies.reservations.reserve(
                offerID: offerID, quantity: quantity, reservationID: reservationID, rewardID: rewardID, at: now)
            quantity = 1
            useReward = false
            confirmation = ReservationConfirmation(
                reservation: reservation, now: now, showsChangePolicy: dependencies.flags.manageOrder,
                showsWalkReminder: dependencies.flags.walkRewards)
        } catch let error as ReservationError {
            alert = error == .notVisibleYet ? .notOpenYet : .noLongerAvailable
        } catch {
            alert = .failed
        }
        if rewardID != nil {
            // If the reservation failed, hand the reward back.
            if confirmation == nil { try? await dependencies.walkRewards.releaseReward(reservationID: reservationID) }
            await refreshRewards()
        }
    }
}
