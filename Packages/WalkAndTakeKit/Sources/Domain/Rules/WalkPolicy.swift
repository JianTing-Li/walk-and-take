//
//  WalkPolicy.swift
//  WalkAndTakeKit
//

import Foundation

public enum WalkPolicy {
    /// A walk can start this long before the pickup window opens.
    public static let startLeadTime: TimeInterval = 60 * 60

    /// When the Start Walk button first appears.
    public static func startOpensAt(for reservation: Reservation) -> Date {
        reservation.snapshot.pickupWindow.start.addingTimeInterval(-startLeadTime)
    }

    /// Start is allowed from 1 h before the window until the window closes,
    /// while the reservation is still active.
    public static func canStart(_ reservation: Reservation, at now: Date) -> Bool {
        ReservationPolicy.isActive(reservation, at: now) && now >= startOpensAt(for: reservation)
    }
}
