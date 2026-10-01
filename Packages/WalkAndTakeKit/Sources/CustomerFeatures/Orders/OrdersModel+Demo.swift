//
//  OrdersModel+Demo.swift
//  WalkAndTakeKit
//
//  Developer mode's Demo menu on Orders: send an order's "your bag is ready" reminder right away.
//

import Domain
import Foundation
import Platform

extension OrdersModel {
    struct DemoReminder: Identifiable {
        var id: UUID { reminder.reservationID }
        /// "Pickup reminder · Rye & Rail Sandwich Shop"
        let title: String
        let reminder: PickupReminder
    }

    /// One per upcoming or ready order, soonest first.
    var demoReminders: [DemoReminder] {
        active
            .sorted { $0.snapshot.pickupWindow.start < $1.snapshot.pickupWindow.start }
            .map { reservation in
                DemoReminder(
                    title: "Pickup reminder · \(reservation.snapshot.restaurantName)",
                    reminder: PickupReminder(reservation, now: now))
            }
    }

    func demoSend(_ reminder: PickupReminder) async {
        guard await dependencies.notifications.requestPermission() else { return }
        await dependencies.notifications.sendReminder(reminder, after: PickupReminder.demoDelay)
    }
}
