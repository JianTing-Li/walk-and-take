//
//  MarketplaceStore+Reservations.swift
//  WalkAndTakeKit
//

import Domain
import Foundation
import Platform
import SwiftData

extension MarketplaceStore {
    /// Reserves bags if the offer is visible, open and in stock. Throws `ReservationError`.
    /// A reward takes 50% off one bag and is marked used in the same save, so the two commit or fail together.
    /// Throws `ReservationError`, including `.rewardUnavailable` when the reward is missing or already used.
    public func reserve(
        offerID: String, quantity: Int, reservationID: UUID = UUID(), rewardID: UUID? = nil, at now: Date
    ) throws -> Reservation {
        guard let offer = try offerEntity(id: offerID) else { throw ReservationError.offerNoLongerExists }
        try ReservationPolicy.validateReservation(of: offer.domain, quantity: quantity, at: now, calendar: calendar)
        guard let restaurant = try restaurantEntity(id: offer.restaurantID)?.domain else {
            throw ReservationError.offerNoLongerExists
        }
        // Checked after every other rule and changed only just before the save, so a refusal leaves it untouched.
        var claimedReward: RewardEntity?
        if let rewardID {
            guard let reward = try rewardEntity(id: rewardID), reward.redeemedAt == nil else {
                throw ReservationError.rewardUnavailable
            }
            claimedReward = reward
        }

        let reservation = Reservation(
            id: reservationID,
            confirmationCode: codes.makeCode(),
            quantity: quantity,
            snapshot: OfferSnapshot(offer: offer.domain, restaurant: restaurant),
            reservedAt: now,
            rewardID: rewardID,
            discount: rewardID == nil ? .zero : offer.domain.price.discount(percent: WalkRewardLadder.discountPercent)
        )
        offer.quantityReserved += quantity
        modelContext.insert(ReservationEntity(reservation))
        claimedReward?.redeemedAt = now
        claimedReward?.redeemedReservationID = reservationID
        try save()

        broadcaster.send(.stockChanged(offerID: offerID))
        broadcaster.send(.reservationsChanged)
        if claimedReward != nil { rewardChanges.send(.walkRewardsChanged) }
        return reservation
    }

    /// Changes how many bags are held; the difference goes back to or comes from stock.
    public func changeQuantity(reservationID: UUID, to quantity: Int, at now: Date) throws -> Reservation {
        guard let entity = try reservationEntity(id: reservationID) else { throw ReservationError.reservationNotFound }
        var reservation = entity.domain
        guard ReservationPolicy.canChange(reservation, at: now) else { throw ReservationError.changeClosed }
        guard let offer = try offerEntity(id: entity.offerID) else { throw ReservationError.offerNoLongerExists }
        try ReservationPolicy.validateChange(
            of: reservation, to: quantity, offerQuantityLeft: offer.quantityLeft, at: now)

        offer.quantityReserved += quantity - reservation.quantity
        reservation.quantity = quantity
        entity.apply(reservation)
        try save()

        broadcaster.send(.stockChanged(offerID: offer.id))
        broadcaster.send(.reservationsChanged)
        return reservation
    }

    /// Cancels the order, puts its bags back on sale and gives back a walking reward it used, in one save.
    public func cancel(reservationID: UUID, reason: CancelReason?, at now: Date) throws -> Reservation {
        guard let entity = try reservationEntity(id: reservationID) else { throw ReservationError.reservationNotFound }
        var reservation = entity.domain
        try ReservationPolicy.validateCancel(of: reservation, at: now)
        guard let offer = try offerEntity(id: entity.offerID) else { throw ReservationError.offerNoLongerExists }

        offer.quantityReserved = max(0, offer.quantityReserved - reservation.quantity)
        reservation.cancelledAt = now
        reservation.cancelReason = reason
        entity.apply(reservation)
        let usedRewards = try modelContext.fetch(
            FetchDescriptor<RewardEntity>(predicate: #Predicate { $0.redeemedReservationID == reservationID }))
        for reward in usedRewards {
            reward.redeemedAt = nil
            reward.redeemedReservationID = nil
        }
        try save()

        broadcaster.send(.stockChanged(offerID: offer.id))
        broadcaster.send(.reservationsChanged)
        if !usedRewards.isEmpty { rewardChanges.send(.walkRewardsChanged) }
        return reservation
    }

    /// Confirms pickup at the counter; only allowed during the pickup window.
    public func markCollected(reservationID: UUID, at now: Date) throws -> Reservation {
        guard let entity = try reservationEntity(id: reservationID) else { throw ReservationError.reservationNotFound }
        var reservation = entity.domain
        try ReservationPolicy.validateCollect(of: reservation, at: now)

        reservation.collectedAt = now
        entity.apply(reservation)
        try save()

        broadcaster.send(.reservationsChanged)
        return reservation
    }

    /// Saves a rating and folds it into the restaurant's average in the same save.
    /// Throws `ReviewError`.
    public func submitReview(_ review: Review, for reservationID: UUID, at now: Date) throws -> Restaurant? {
        guard let entity = try reservationEntity(id: reservationID) else { throw ReviewError.notEligible }
        var reservation = entity.domain
        try ReviewPolicy.validate(review, for: reservation, at: now)

        var saved = review
        saved.submittedAt = now
        reservation.review = saved
        entity.apply(reservation)

        let restaurant = try restaurantEntity(id: entity.restaurantID)
        if let restaurant {
            let folded = ReviewPolicy.foldedRating(
                rating: restaurant.rating, reviewCount: restaurant.reviewCount, adding: review.overall)
            restaurant.rating = folded.rating
            restaurant.reviewCount = folded.reviewCount
        }
        try save()

        broadcaster.send(.reservationsChanged)
        broadcaster.send(.ratingChanged(restaurantID: entity.restaurantID))
        return restaurant?.domain
    }
}
