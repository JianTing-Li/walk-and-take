//
//  CustomerDependencies.swift
//  WalkAndTakeKit
//

import Domain
import Platform

/// Everything customer screens need, as protocols. Built by the app's composition root.
public struct CustomerDependencies: Sendable {
    public var offers: any OfferRepository
    public var reservations: any ReservationRepository
    public var reviews: any ReviewRepository
    public var favorites: any FavoritesRepository
    public var preferences: any PreferencesRepository
    public var walkRewards: any WalkRewardsRepository
    public var walkTracker: any WalkTracking
    public var location: any LocationProvider
    public var notifications: any NotificationScheduler
    public var resetter: any DemoDataResetting
    public var clock: any Clock
    public var flags: FeatureFlags
    /// Developer mode's switches.
    public var developer: DeveloperSettings
    /// Developer mode's demo actions (time travel and, later, walks and rewards).
    public var demo: any DemoControlling

    public init(
        offers: any OfferRepository,
        reservations: any ReservationRepository,
        reviews: any ReviewRepository,
        favorites: any FavoritesRepository,
        preferences: any PreferencesRepository,
        walkRewards: any WalkRewardsRepository,
        walkTracker: any WalkTracking,
        location: any LocationProvider,
        notifications: any NotificationScheduler,
        resetter: any DemoDataResetting,
        clock: any Clock,
        flags: FeatureFlags,
        developer: DeveloperSettings,
        demo: any DemoControlling
    ) {
        self.offers = offers
        self.reservations = reservations
        self.reviews = reviews
        self.favorites = favorites
        self.preferences = preferences
        self.walkRewards = walkRewards
        self.walkTracker = walkTracker
        self.location = location
        self.notifications = notifications
        self.resetter = resetter
        self.clock = clock
        self.flags = flags
        self.developer = developer
        self.demo = demo
    }
}
