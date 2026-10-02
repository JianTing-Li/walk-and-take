//
//  OrderRow.swift
//  WalkAndTakeKit
//

import DesignSystem
import Domain
import Foundation
import Platform
import SwiftUI

/// One order in the list, worded from its snapshot.
public struct OrderRowContent: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let restaurantName: String
    public let bagsText: String
    public let category: FoodCategory
    public let statusText: String
    public let tone: PickupStatusPill.Tone
    public let rating: Int?
    public let showsRatePrompt: Bool

    /// - Parameter walkedMiles: Miles this order's walk earned, shown on picked-up orders.
    init(_ reservation: Reservation, now: Date, flags: FeatureFlags, walkedMiles: Double? = nil) {
        let snapshot = reservation.snapshot
        id = reservation.id
        restaurantName = snapshot.restaurantName
        bagsText = "\(reservation.quantity) × \(snapshot.bagName)"
        category = snapshot.category
        (statusText, tone) = Self.status(of: reservation, now: now, walkedMiles: walkedMiles)
        rating = flags.reviews ? reservation.review?.overall : nil
        showsRatePrompt = flags.reviews && ReviewPolicy.canReview(reservation, at: now)
    }

    /// "Ready now · Ends in 20 min", "Opens tomorrow at 7:30 AM", "Picked up today · +0.5 mi walked", …
    static func status(of reservation: Reservation, now: Date, walkedMiles: Double? = nil)
        -> (String, PickupStatusPill.Tone)
    {
        let calendar = NYCalendar.calendar
        let countdown = PickupDayFormatter.countdown(reservation.snapshot.pickupWindow, now: now, calendar: calendar)
        return switch ReservationPolicy.status(of: reservation, at: now) {
        case .readyNow: ("Ready now · \(countdown)", .readyNow)
        case .upcoming: (countdown, .upcoming)
        case .collected:
            (Self.pickedUpText(reservation.collectedAt ?? now, now: now, walkedMiles: walkedMiles), .collected)
        case .missed: ("Missed pickup", .inactive)
        case .cancelled: ("Cancelled", .inactive)
        }
    }

    /// "Picked up today", "Picked up Wed Sep 30", plus " · +0.5 mi walked" when the walk earned miles.
    private static func pickedUpText(_ date: Date, now: Date, walkedMiles: Double?) -> String {
        let calendar = NYCalendar.calendar
        let day =
            calendar.isDate(date, inSameDayAs: now) ? "today" : TimeText.shortDate(date, calendar: calendar)
        guard let walkedMiles, walkedMiles > 0 else { return "Picked up \(day)" }
        return "Picked up \(day) · +\(WalkCopy.miles(walkedMiles)) mi walked"
    }
}

struct OrderRow: View {
    let content: OrderRowContent

    var body: some View {
        HStack(spacing: Spacing.m) {
            CategoryTile(category: content.category)
            VStack(alignment: .leading, spacing: 3) {
                Text(content.restaurantName).font(.headline)
                Text(content.bagsText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                PickupStatusPill(
                    text: content.statusText, tone: content.tone, rating: content.rating,
                    showsRatePrompt: content.showsRatePrompt)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
