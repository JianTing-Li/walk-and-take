//
//  AppDependencies.swift
//  WalkAndTake
//
//  The composition root: the only place that knows concrete stores exist.
//  Features receive Domain repository protocols and a Clock from here.
//

import CustomerFeatures
import Domain
import Foundation
import MockData
import OSLog
import Platform
import SwiftData
import SwiftUI

@MainActor
final class AppDependencies {
    let role: UserRole = .customer
    let flags: FeatureFlags
    let clock: any Clock
    #if DEBUG
        /// The same clock as `clock`, exposed for time travel.
        let debugClock: AdjustableClock
    #endif

    let marketplace: MarketplaceStore
    let userData: UserDataStore
    let location: any LocationProvider
    let walkTracker: any WalkTracking
    let notifications: any NotificationScheduler
    let notificationDelegate = NotificationBannerDelegate()
    let rollover: RolloverService
    let resetter: any DemoDataResetting
    let navigation = CustomerNavigation()
    let screens: CustomerScreens

    // Repositories, as the protocols features depend on.
    var offers: any OfferRepository { marketplace }
    var reservations: any ReservationRepository { marketplace }
    var reviews: any ReviewRepository { marketplace }
    var favorites: any FavoritesRepository { userData }
    var preferences: any PreferencesRepository { userData }

    private static let log = Logger(subsystem: "org.pursuit.Walk-And-Take", category: "App")

    init() {
        flags = .default
        #if DEBUG
            let options = LaunchOptions.current
            debugClock = options.fixedNow.map(AdjustableClock.init(fixedAt:)) ?? AdjustableClock()
            clock = debugClock
        #else
            clock = LiveClock()
        #endif

        let seed: Seed
        let container: ModelContainer
        do {
            seed = try SeedLoader.loadBundled()
            #if DEBUG
                container =
                    options.inMemoryStore
                    ? try ModelContainerFactory.makeInMemory() : try ModelContainerFactory.makePersistent()
            #else
                container = try ModelContainerFactory.makePersistent()
            #endif
        } catch {
            fatalError("Walk & Take can't start without its seed data and store: \(error)")
        }

        marketplace = MarketplaceStore(modelContainer: container, seed: seed)
        userData = UserDataStore(modelContainer: container)
        #if DEBUG
            location =
                options.fixedLocation
                ? FixedLocationProvider() : DeviceLocationProvider(source: CoreLocationSource())
        #else
            location = DeviceLocationProvider(source: CoreLocationSource())
        #endif
        #if DEBUG
            walkTracker =
                options.simulateWalk
                ? SimulatedWalkTracker() : LiveWalkTracker(source: CoreLocationWalkSource())
        #else
            walkTracker = LiveWalkTracker(source: CoreLocationWalkSource())
        #endif
        notifications = LiveNotificationScheduler()
        rollover = RolloverService(
            marketplace: marketplace, userData: userData, notifications: notifications, clock: clock,
            alertsEnabled: flags.alertsEnabled)
        resetter = DemoDataResetter(
            marketplace: marketplace, userData: userData, notifications: notifications, clock: clock)
        #if DEBUG
            let developerDestination = Self.developerTools(clock: debugClock, offers: marketplace)
        #else
            let developerDestination: ((ProfileRoute) -> AnyView)? = nil
        #endif
        screens = CustomerScreens(
            dependencies: CustomerDependencies(
                offers: marketplace, reservations: marketplace, reviews: marketplace, favorites: userData,
                preferences: userData, walkRewards: userData, walkTracker: walkTracker, location: location,
                notifications: notifications,
                resetter: resetter,
                clock: clock,
                flags: flags),
            navigation: navigation,
            developerDestination: developerDestination)
    }

    #if DEBUG
        /// Profile's Developer section: debug builds only.
        private static func developerTools(
            clock: AdjustableClock, offers: any OfferRepository
        ) -> (ProfileRoute) -> AnyView {
            { route in
                switch route {
                case .timeTravel: AnyView(TimeTravelView(clock: clock))
                case .seedMap: AnyView(SeedMapView(offers: offers))
                case .walkHistory, .rewards: AnyView(EmptyView())  // Profile shows these itself
                }
            }
        }
    #endif

    #if DEBUG
        /// `-UITestSeedReward` (one finished 1.2 mi walk, which banks the first 50% reward) or
        /// `-UITestSeedMiles N` (one finished walk of N miles, banking whatever milestones that reaches).
        func seedDemoRewardIfRequested() async {
            let options = LaunchOptions.current
            guard (try? await userData.walks().isEmpty) == true else { return }
            if options.seedHistory { await seedDemoHistory() }
            guard let miles = options.seedMiles ?? (options.seedReward ? 1.2 : nil) else { return }
            let id = UUID()
            _ = try? await userData.startWalk(reservationID: id, restaurantID: "demo", at: clock.now)
            _ = try? await userData.finishWalk(
                reservationID: id, verdict: .credited(miles: miles), at: clock.now, calendar: .current)
        }

        /// `-UITestSeedHistory`: three finished walks at real restaurants over the last two days.
        private func seedDemoHistory() async {
            guard let restaurants = try? await marketplace.restaurants(), restaurants.count >= 3 else { return }
            let walks: [(restaurant: Restaurant, miles: Double, hoursAgo: Double)] = [
                (restaurants[0], 0.4, 49), (restaurants[1], 0.9, 26), (restaurants[2], 0.6, 2),
            ]
            for entry in walks {
                let finished = clock.now.addingTimeInterval(-entry.hoursAgo * 3600)
                let id = UUID()
                _ = try? await userData.startWalk(
                    reservationID: id, restaurantID: entry.restaurant.id, at: finished.addingTimeInterval(-900))
                _ = try? await userData.finishWalk(
                    reservationID: id, verdict: .credited(miles: entry.miles), at: finished, calendar: .current)
            }
        }
    #endif

    /// Rolls the marketplace over if the New York day (or seed) changed. Safe to call often.
    func runRollover(reason: String) async {
        do {
            if try await rollover.run() {
                Self.log.info("Rolled over (\(reason, privacy: .public))")
            }
        } catch {
            Self.log.error("Rollover failed (\(reason, privacy: .public)): \(error)")
        }
    }
}
