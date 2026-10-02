//
//  Walk.swift
//  WalkAndTakeKit
//

import Foundation

/// One GPS fix recorded during a pickup walk. Plain values so Domain stays free of CoreLocation.
public struct WalkSample: Hashable, Codable, Sendable {
    public var coordinate: Coordinate
    public var timestamp: Date
    /// Horizontal accuracy radius in meters. Negative means the fix is invalid.
    public var horizontalAccuracyMeters: Double
    /// True when the OS says the fix was produced by software rather than GPS hardware.
    public var isSimulated: Bool

    public init(
        coordinate: Coordinate,
        timestamp: Date,
        horizontalAccuracyMeters: Double = 5,
        isSimulated: Bool = false
    ) {
        self.coordinate = coordinate
        self.timestamp = timestamp
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.isSimulated = isSimulated
    }
}

/// Why a walk earned no miles. The pickup itself is never blocked.
public enum WalkRejection: String, Hashable, Codable, Sendable {
    case simulatedLocation, notEnoughData, tooFast, endedFarFromRestaurant, repeatPickupToday

    public var message: String {
        switch self {
        case .simulatedLocation: "Location looked simulated, so no miles were counted."
        case .notEnoughData: "We couldn't record enough of your walk to count miles."
        case .tooFast: "Part of the trip was too fast to be walking, so no miles were counted."
        case .endedFarFromRestaurant: "The walk didn't end at the restaurant, so no miles were counted."
        case .repeatPickupToday: "You already earned miles from this restaurant today."
        }
    }
}

/// The result of checking a recorded walk.
public enum WalkVerdict: Hashable, Sendable {
    case credited(miles: Double)
    case rejected(WalkRejection)

    public var creditedMiles: Double {
        if case .credited(let miles) = self { return miles }
        return 0
    }
}

/// A walk tied to one reservation. `creditedMiles` is 0 when rejected.
public struct Walk: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let reservationID: UUID
    public let restaurantID: String
    public let startedAt: Date
    public var finishedAt: Date?
    public var creditedMiles: Double
    public var rejection: WalkRejection?

    public init(
        id: UUID = UUID(),
        reservationID: UUID,
        restaurantID: String,
        startedAt: Date,
        finishedAt: Date? = nil,
        creditedMiles: Double = 0,
        rejection: WalkRejection? = nil
    ) {
        self.id = id
        self.reservationID = reservationID
        self.restaurantID = restaurantID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.creditedMiles = creditedMiles
        self.rejection = rejection
    }
}

/// A banked 50%-off voucher for one bag, earned at a mileage milestone.
extension Walk {
    /// Developer mode's demo miles are walks to a made-up store whose ID starts with this.
    public static let demoRestaurantPrefix = "demo"

    /// Miles added by Developer mode rather than a pickup.
    public var isDemo: Bool { restaurantID.hasPrefix(Self.demoRestaurantPrefix) }
}

public struct Reward: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let milestoneMiles: Double
    public let earnedAt: Date
    public var redeemedAt: Date?
    public var redeemedReservationID: UUID?

    public init(
        id: UUID = UUID(),
        milestoneMiles: Double,
        earnedAt: Date,
        redeemedAt: Date? = nil,
        redeemedReservationID: UUID? = nil
    ) {
        self.id = id
        self.milestoneMiles = milestoneMiles
        self.earnedAt = earnedAt
        self.redeemedAt = redeemedAt
        self.redeemedReservationID = redeemedReservationID
    }

    public var isAvailable: Bool { redeemedAt == nil }
}

/// How a walk is going, from the fixes recorded so far.
public struct WalkProgress: Hashable, Sendable {
    /// Miles that would be credited right now: fast segments dropped, capped at the detour and per-pickup limits.
    public var creditedMiles: Double
    /// Straight-line miles from the latest fix to the restaurant.
    public var milesToGo: Double
    /// How far along the trip is, from 0 (where the walk began) to 1 (at the door).
    public var fraction: Double

    public init(creditedMiles: Double, milesToGo: Double, fraction: Double) {
        self.creditedMiles = creditedMiles
        self.milesToGo = milesToGo
        self.fraction = fraction
    }
}
