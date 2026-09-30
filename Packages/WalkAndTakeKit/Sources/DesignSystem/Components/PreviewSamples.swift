//
//  PreviewSamples.swift
//  WalkAndTakeKit
//
//  Sample display content for component previews and render tests.
//

import Domain
import Foundation

enum PreviewSamples {
    static let bagCard = BagCard.Content(
        restaurantName: "Early Bird Bakehouse",
        bagName: "Breakfast Surprise Bag",
        category: .breakfast,
        badgeText: "4 left",
        isUrgent: false,
        savingsPercent: 67,
        rating: 4.8,
        reviewCount: 212,
        pickupText: "Today · until 10:00 AM",
        distanceText: "0.2 mi away",
        price: Money(cents: 599),
        estimatedValue: Money(cents: 1800),
        isAvailable: true,
        fitsCommute: true,
        walkRewardText: "+0.2 mi toward a reward"
    )

    static let bagCardFarther: BagCard.Content = {
        var content = bagCard
        content.distanceText = "0.9 mi away"
        content.walkRewardText = "+0.9 mi toward a reward"
        content.walkCompareText = "0.7 mi farther than the nearest · earns 0.7 mi more"
        return content
    }()

    static let bagCardUrgent: BagCard.Content = {
        var content = bagCard
        content.restaurantName = "Knead Street Bakery"
        content.bagName = "Bakery Bag"
        content.category = .bakery
        content.badgeText = "Ends in 12 min"
        content.isUrgent = true
        content.fitsCommute = false
        return content
    }()

    static let bagCardSoldOut: BagCard.Content = {
        var content = bagCard
        content.restaurantName = "Tidewater Dumplings"
        content.bagName = "Lunch Bag"
        content.category = .meal
        content.badgeText = "Sold out"
        content.isAvailable = false
        content.rating = nil
        content.pickupText = "Today · 11:30 AM–2:00 PM"
        return content
    }()

    static let bagCardTomorrow: BagCard.Content = {
        var content = bagCard
        content.badgeText = "Opens tomorrow at 7:30 AM"
        content.pickupText = "Tomorrow · 7:30–10:00 AM"
        return content
    }()

    static let mapCard = MapBagCard.Content(
        restaurantName: "Crane & Kettle",
        bagName: "Coffee & Treats Bag",
        category: .coffee,
        statusLine: "Ends in 25 min · 0.5 mi",
        isUrgent: true,
        price: Money(cents: 549),
        estimatedValue: Money(cents: 1500),
        isAvailable: true,
        walkRewardText: "+0.5 mi toward a reward"
    )

    static let walkProgress = WalkProgressCard.Content(
        milesText: "1.2 mi", milesCaption: "walked to pickups", progress: 0.05,
        targetTitle: "Next: 50% off one bag at 5 mi", targetDetail: "3.8 mi to go",
        readyText: "1 reward ready to use")

    static let walkProgressNew = WalkProgressCard.Content(
        milesText: "0.0 mi", milesCaption: "walked to pickups", progress: 0,
        targetTitle: "First reward: 50% off one bag at 1 mi", targetDetail: "1.0 mi to go")

    static let walkCard = WalkRewardCard.Content(
        title: "0.7 mi walk",
        detail: "Earns +0.7 mi toward your next reward",
        footnote: "Walk to the pickup to count your miles.",
        outcome: "After this pickup: 1.9 of 5 mi · 3.1 mi to go"
    )

    static let walkCardUnlock = WalkRewardCard.Content(
        title: "0.9 mi walk",
        detail: "Earns +0.9 mi toward your next reward",
        outcome: "After this pickup: 5.1 mi walked",
        unlock: "Unlocks a reward: 50% off one bag"
    )
}
