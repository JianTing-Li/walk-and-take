//
//  NotificationScheduler.swift
//  WalkAndTakeKit
//
//  Local notifications for favorite restaurants: "your store's bags are open".
//

import Domain
import Foundation

/// Everything an alert needs to describe an offer.
public struct OfferAlert: Hashable, Sendable {
    public var offerID: String
    public var restaurantName: String
    public var bagName: String
    public var price: Money
    public var estimatedValue: Money
    public var pickupWindow: PickupWindow

    public init(
        offerID: String,
        restaurantName: String,
        bagName: String,
        price: Money,
        estimatedValue: Money,
        pickupWindow: PickupWindow
    ) {
        self.offerID = offerID
        self.restaurantName = restaurantName
        self.bagName = bagName
        self.price = price
        self.estimatedValue = estimatedValue
        self.pickupWindow = pickupWindow
    }

    public init(offer: Offer, restaurantName: String) {
        self.init(
            offerID: offer.id,
            restaurantName: restaurantName,
            bagName: offer.name,
            price: offer.price,
            estimatedValue: offer.estimatedValue,
            pickupWindow: offer.pickupWindow
        )
    }
}

public protocol NotificationScheduler: Sendable {
    /// Asks for permission the first time; returns whether alerts can be shown.
    func requestPermission() async -> Bool

    /// Adds an alert at each offer's pickup start. Offers already open are skipped.
    func schedule(_ alerts: [OfferAlert], now: Date) async

    /// Replaces every pending drop alert with `alerts` (used after rollover).
    func replaceAll(with alerts: [OfferAlert], now: Date) async

    func cancel(offerIDs: [String]) async

    /// Removes every pending alert, including previews.
    func cancelAll() async

    /// Sends an alert `delay` seconds from now, e.g. a sample so you can see what one looks like.
    func sendPreview(_ alert: OfferAlert, after delay: TimeInterval) async

    /// Reminds the customer to pick up a reserved bag, `delay` seconds from now.
    func sendReminder(_ reminder: PickupReminder, after delay: TimeInterval) async
}

/// "Your bag is ready" for one order.
public struct PickupReminder: Hashable, Sendable {
    public var reservationID: UUID
    public var restaurantName: String
    public var code: String
    public var pickupWindow: PickupWindow
    /// The window is open now; otherwise the reminder says when it opens.
    public var isOpen: Bool

    public init(reservationID: UUID, restaurantName: String, code: String, pickupWindow: PickupWindow, isOpen: Bool) {
        self.reservationID = reservationID
        self.restaurantName = restaurantName
        self.code = code
        self.pickupWindow = pickupWindow
        self.isOpen = isOpen
    }
}

extension NotificationScheduler {
    /// A sample alert a few seconds from now, so there's time to leave the app and watch it arrive.
    public func sendPreview(_ alert: OfferAlert) async {
        await sendPreview(alert, after: NotificationPlan.previewDelay)
    }
}

/// Identifiers and copy shared by the live scheduler and tests.
public enum NotificationPlan {
    public static let dropPrefix = "drop-"
    public static let previewPrefix = "preview-"
    public static let reminderPrefix = "reminder-"
    public static let previewDelay: TimeInterval = 5

    public static func identifier(forOfferID offerID: String) -> String {
        dropPrefix + offerID
    }

    /// Alerts that can still fire: the window hasn't opened yet.
    public static func upcoming(_ alerts: [OfferAlert], now: Date) -> [OfferAlert] {
        alerts.filter { $0.pickupWindow.start > now }
    }

    /// Which offers should have a pending alert: from favorites with alerts on,
    /// in stock, and not open yet.
    public static func alerts(
        for favorites: [FavoriteRestaurant],
        offers: [Offer],
        restaurants: [Restaurant],
        now: Date
    ) -> [OfferAlert] {
        let alerting = Set(favorites.filter(\.alertsEnabled).map(\.restaurantID))
        let names = Dictionary(uniqueKeysWithValues: restaurants.map { ($0.id, $0.name) })
        return
            offers
            .filter { alerting.contains($0.restaurantID) && !$0.isSoldOut && $0.pickupWindow.start > now }
            .compactMap { offer in names[offer.restaurantID].map { OfferAlert(offer: offer, restaurantName: $0) } }
    }

    /// "Your bag is ready at Rye & Rail" or "Pickup at Rye & Rail opens at 12:00 PM"
    public static func title(for reminder: PickupReminder) -> String {
        reminder.isOpen
            ? "Your bag is ready at \(reminder.restaurantName)"
            : "Pickup at \(reminder.restaurantName) opens at \(TimeText.time(reminder.pickupWindow.start, calendar: NYCalendar.calendar))"
    }

    /// "Show code 6VC7 at the counter by 2:00 PM. Walk there to earn miles."
    public static func body(for reminder: PickupReminder) -> String {
        let calendar = NYCalendar.calendar
        let when =
            reminder.isOpen
            ? "by \(TimeText.time(reminder.pickupWindow.end, calendar: calendar))"
            : "between \(TimeText.range(reminder.pickupWindow, calendar: calendar))"
        return "Show code \(reminder.code) at the counter \(when). Walk there to earn miles."
    }

    public static func title(for alert: OfferAlert) -> String {
        "\(alert.restaurantName) has bags ready"
    }

    /// "Breakfast Surprise Bag for $5.99 (was $18.00). Pick up 7:30–10:00 AM."
    public static func body(for alert: OfferAlert) -> String {
        let range = TimeText.range(alert.pickupWindow, calendar: NYCalendar.calendar)
        return "\(alert.bagName) for \(format(alert.price)) (was \(format(alert.estimatedValue))). Pick up \(range)."
    }

    static func format(_ money: Money) -> String {
        money.decimalDollars.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }
}
