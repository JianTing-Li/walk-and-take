//
//  ReservationRepository.swift
//  WalkAndTakeKit
//

import Foundation

/// Reserving and managing orders. Each mutation is atomic: stock and the
/// reservation change together or not at all. Domain failures throw `ReservationError`.
public protocol ReservationRepository: Sendable {
    /// Reserves bags. With a `rewardID`, 50% comes off one bag's price and the reward is marked used by this
    /// reservation in the **same save**, so the reward is spent exactly when the reservation exists. Throws
    /// `ReservationError.rewardUnavailable` (and changes nothing) if the reward is missing or already used.
    func reserve(offerID: String, quantity: Int, reservationID: UUID, rewardID: UUID?, at now: Date) async throws
        -> Reservation
    func changeQuantity(reservationID: UUID, to quantity: Int, at now: Date) async throws -> Reservation
    func cancel(reservationID: UUID, reason: CancelReason?, at now: Date) async throws -> Reservation
    func markCollected(reservationID: UUID, at now: Date) async throws -> Reservation
    /// All reservations, newest first.
    func reservations() async throws -> [Reservation]
    func reservation(id: UUID) async throws -> Reservation?
    func changes() -> AsyncStream<MarketplaceChange>
}

extension ReservationRepository {
    /// A plain reservation with no reward.
    public func reserve(offerID: String, quantity: Int, at now: Date) async throws -> Reservation {
        try await reserve(offerID: offerID, quantity: quantity, reservationID: UUID(), rewardID: nil, at: now)
    }
}
