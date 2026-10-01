//
//  PickupReminder+Reservation.swift
//  WalkAndTakeKit
//

import Domain
import Foundation
import Platform

extension PickupReminder {
    /// Developer mode's "your bag is ready" reminder for an order.
    init(_ reservation: Reservation, now: Date) {
        let window = reservation.snapshot.pickupWindow
        self.init(
            reservationID: reservation.id, restaurantName: reservation.snapshot.restaurantName,
            code: reservation.confirmationCode, pickupWindow: window, isOpen: window.hasStarted(at: now))
    }

    /// Fires after a second, so the banner shows while you're still looking at the app.
    static let demoDelay: TimeInterval = 1
}
