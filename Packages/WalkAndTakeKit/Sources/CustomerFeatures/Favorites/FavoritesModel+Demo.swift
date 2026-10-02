//
//  FavoritesModel+Demo.swift
//  WalkAndTakeKit
//
//  Developer mode's Demo menu on Favorites: fire a store's "bags ready" alert right away, instead of
//  waiting for its pickup window to open.
//

import Domain
import Foundation
import Platform

extension FavoritesModel {
    /// Fires after a second, so the banner shows while you're still looking at the app.
    static let demoAlertDelay: TimeInterval = 1

    struct DemoAlert: Identifiable {
        var id: String { alert.offerID }
        /// "Alert from Skyline Tortillería"
        let title: String
        let alert: OfferAlert
    }

    /// One per favorite store with a bag today (or tomorrow, after 8 PM), in the list's order. With none,
    /// a sample alert for any bag, so there's always something to show.
    var demoAlerts: [DemoAlert] {
        guard showsAlerts else { return [] }
        let stores = rows.compactMap { row -> DemoAlert? in
            guard let restaurant = restaurants[row.id],
                let offer = offers.first(where: { $0.restaurantID == restaurant.id })
            else { return nil }
            return DemoAlert(
                title: "Alert from \(restaurant.name)", alert: OfferAlert(offer: offer, restaurantName: restaurant.name)
            )
        }
        if stores.isEmpty, let sample = previewAlert { return [DemoAlert(title: "Sample alert", alert: sample)] }
        return stores
    }

    func demoFire(_ alert: OfferAlert) async {
        guard await dependencies.notifications.requestPermission() else {
            notificationsBlocked = true
            return
        }
        await dependencies.notifications.sendPreview(alert, after: Self.demoAlertDelay)
    }
}
