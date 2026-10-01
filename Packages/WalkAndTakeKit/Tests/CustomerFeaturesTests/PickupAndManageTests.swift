//
//  PickupAndManageTests.swift
//  CustomerFeaturesTests
//

import DesignSystem
import Domain
import Foundation
import Platform
import Testing

@testable import CustomerFeatures

@MainActor
@Suite("Pickup")
struct PickupModelTests {
    static let breakfast = Fixture.offer("breakfast", start: (7, 30), end: (10, 0), price: 599, total: 5)
    static let tomorrow = Fixture.offer("breakfast", day: 25, start: (7, 30), end: (10, 0), price: 599)

    func pickup(
        _ reservation: Reservation, at now: Date, flags: FeatureFlags = Fixture.flags()
    ) async -> (PickupModel, Harness) {
        let harness = Harness(now: now, offers: [Self.breakfast, Self.tomorrow], flags: flags)
        harness.marketplace.add(reservation)
        let model = PickupModel(
            reservationID: reservation.id, origin: ResolvedLocation(coordinate: Fixture.licCenter, source: .device),
            dependencies: harness.dependencies)
        await model.load()
        return (model, harness)
    }

    @Test func upcomingTomorrow() async {
        let (model, _) = await pickup(Fixture.reservation(for: Self.tomorrow), at: Fixture.sep(24, 20, 30))
        #expect(model.header?.title == "Pickup opens tomorrow at 7:30 AM")
        #expect(model.header?.subtitle == "Your bag is held until 10:00 AM")
        #expect(model.confirmFromText == "You can confirm pickup from tomorrow at 7:30 AM")
        #expect(model.code == "QW3E")
        #expect(model.pickupInstructions == "Ask at the counter.")
        #expect(model.summary.map(\.value)[1] == "Pick up tomorrow, Fri Sep 25, 7:30–10:00 AM")
        #expect(model.canManage)
    }

    @Test func readyNowThenCollect() async {
        let (model, _) = await pickup(Fixture.reservation(for: Self.breakfast, quantity: 2), at: Fixture.sep(24, 8))
        #expect(model.status == .readyNow)
        #expect(model.header?.title == "Ready for pickup")
        #expect(model.header?.subtitle == "Open until 10:00 AM")
        await model.collect()
        #expect(model.status == .collected)
        #expect(model.header?.title == "Enjoy your breakfast!")
        #expect(model.canReview)
        #expect(model.impactText == "You saved $23.96 and about 5.0 kg of CO₂e.")
        model.rate(stars: 4)
        #expect(model.rateRequest?.stars == 4)
    }

    @Test func readySubtitleCountsDownInTheLastHour() async {
        let (model, _) = await pickup(Fixture.reservation(for: Self.breakfast), at: Fixture.sep(24, 9, 40))
        #expect(model.header?.subtitle == "Ends in 20 min · until 10:00 AM")
    }

    @Test func collectOutsideTheWindowShowsAnAlert() async {
        let (model, _) = await pickup(Fixture.reservation(for: Self.breakfast), at: Fixture.sep(24, 7))
        await model.collect()
        #expect(model.collectFailed)
        #expect(model.status == .upcoming)
    }

    @Test func changesCloseTenMinutesBeforeTheEnd() async {
        let (model, _) = await pickup(Fixture.reservation(for: Self.breakfast), at: Fixture.sep(24, 9, 55))
        #expect(!model.canManage)
        #expect(model.changesClosedText == "Changes closed at 9:50 AM. The store is getting your bag ready.")
    }

    @Test func manageOrderFlagOffHidesTheEntryPoint() async {
        let (model, _) = await pickup(
            Fixture.reservation(for: Self.breakfast), at: Fixture.sep(24, 7), flags: Fixture.flags(manageOrder: false))
        #expect(!model.canManage)
        #expect(model.changesClosedText == nil)
    }

    @Test func flagsHideImpactAndRating() async {
        let collected = Fixture.reservation(for: Self.breakfast, collectedAt: Fixture.sep(24, 8))
        let (model, _) = await pickup(
            collected, at: Fixture.sep(24, 9), flags: Fixture.flags(reviews: false, impact: false))
        #expect(model.impactText == nil)
        #expect(!model.canReview)
    }

    @Test func missedAndCancelledHeaders() async {
        let (missed, _) = await pickup(Fixture.reservation(for: Self.breakfast), at: Fixture.sep(24, 10, 30))
        #expect(missed.header?.title == "Pickup window ended")
        #expect(missed.confirmFromText == nil)
        let cancelled = Fixture.reservation(for: Self.breakfast, cancelledAt: Fixture.sep(24, 7))
        let (model, _) = await pickup(cancelled, at: Fixture.sep(24, 8))
        #expect(model.header?.title == "Order cancelled")
        #expect(!model.isActive)
    }

    @Test func directionsAndNotFound() async throws {
        let (model, _) = await pickup(Fixture.reservation(for: Self.breakfast), at: Fixture.sep(24, 7))
        let url = try #require(model.directionsURL)
        #expect(url.absoluteString.contains("daddr=40.7443,-73.9532"))
        #expect(model.addressLine == "Vernon Blvd & 48th Ave, Long Island City · 0.2 mi")

        let harness = Harness(now: Fixture.sep(24, 7), offers: [])
        let missing = PickupModel(
            reservationID: UUID(), origin: ResolvedLocation(coordinate: Fixture.licCenter, source: .device),
            dependencies: harness.dependencies)
        await missing.load()
        #expect(missing.state == .notFound)
    }
}

@MainActor
@Suite("Pickup walking")
struct PickupWalkingTests {
    static let breakfast = Fixture.offer("breakfast", start: (7, 30), end: (10, 0), price: 599, total: 5)
    /// Near Café's door.
    static let door = Coordinate(latitude: 40.7443, longitude: -73.9532)

    /// A steady 3 mph walk that starts `miles` due south of the door and ends at it.
    static func track(miles: Double = 0.3, simulated: Bool = false) -> [WalkSample] {
        let milesPerDegree = 3958.8 * .pi / 180
        let steps = 6
        let seconds = miles / 3 * 3600 / Double(steps)
        let start = Fixture.sep(24, 7, 30)
        return (0...steps).map { i in
            WalkSample(
                coordinate: Coordinate(
                    latitude: door.latitude - miles * (1 - Double(i) / Double(steps)) / milesPerDegree,
                    longitude: door.longitude),
                timestamp: start.addingTimeInterval(seconds * Double(i)), isSimulated: simulated)
        }
    }

    func pickup(
        at now: Date, reservation: Reservation? = nil, flags: FeatureFlags = Fixture.flags()
    ) async -> (PickupModel, Harness, Reservation) {
        let harness = Harness(now: now, offers: [Self.breakfast], flags: flags)
        let reservation = harness.marketplace.add(reservation ?? Fixture.reservation(for: Self.breakfast))
        harness.walkTracker.script(Self.track())
        let model = PickupModel(
            reservationID: reservation.id, origin: ResolvedLocation(coordinate: Fixture.licCenter, source: .device),
            dependencies: harness.dependencies)
        await model.load()
        return (model, harness, reservation)
    }

    // MARK: Before the walk

    @Test func startWalkOpensAnHourBeforeThePickupWindow() async {
        let (early, _, _) = await pickup(at: Fixture.sep(24, 6, 29))
        #expect(early.walkSection == .opensLater("Start walk opens at 6:30 AM"))
        #expect(!early.canStartWalk)
        let (open, _, _) = await pickup(at: Fixture.sep(24, 6, 30))
        #expect(open.canStartWalk)
    }

    @Test func theReadyCardShowsTheDistanceAndTheMilesItEarns() async {
        let (model, _, _) = await pickup(at: Fixture.sep(24, 7))
        guard case .ready(let card)? = model.walkSection else {
            Issue.record("expected a ready walk section, got \(String(describing: model.walkSection))")
            return
        }
        #expect(card.title == "0.2 mi walk")
        #expect(card.detail == "Earns +0.2 mi toward your next reward")
    }

    @Test func theButtonStaysWhileThePickupWindowIsOpenAndGoesWhenItCloses() async {
        let (open, _, _) = await pickup(at: Fixture.sep(24, 8))
        #expect(open.canStartWalk)
        let (closed, _, _) = await pickup(at: Fixture.sep(24, 10, 0))
        #expect(!closed.canStartWalk)
        #expect(closed.walkSection == nil)
    }

    @Test func walkingIsHiddenWhenTheFlagIsOff() async {
        let (model, _, _) = await pickup(at: Fixture.sep(24, 7), flags: Fixture.flags(walkRewards: false))
        #expect(model.walkSection == nil)
        #expect(!model.canStartWalk)
        await model.startWalk()
        #expect(model.walk == nil)
    }

    // MARK: During the walk

    @Test func startingAWalkRecordsItAndShowsProgress() async throws {
        let (model, harness, reservation) = await pickup(at: Fixture.sep(24, 7))
        await model.startWalk()
        #expect(model.walk?.reservationID == reservation.id)
        #expect(model.trackingStatus == .tracking)
        #expect(harness.walkTracker.isTracking(reservation.id))
        #expect(harness.walkTracker.destination(of: reservation.id) == Self.door)
        #expect(!model.canStartWalk)
        guard case .walking(let walking)? = model.walkSection else {
            Issue.record("expected a walking section, got \(String(describing: model.walkSection))")
            return
        }
        // The scripted track already ends at the door, before the 7:30 window opens.
        #expect(walking.phase == .arrivedEarly)
        #expect(walking.title == "You've arrived")
        #expect(walking.warning == nil)
        #expect(try await harness.walkRewards.walk(reservationID: reservation.id) != nil)
    }

    @Test func aWalkWithLocationOffWarnsTheCustomer() async {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 7))
        harness.walkTracker.setLocationOff(true)
        await model.startWalk()
        guard case .walking(let walking)? = model.walkSection else {
            Issue.record("expected a walking section")
            return
        }
        #expect(walking.warning?.contains("Location is off") == true)
    }

    @Test func aWalkTheAppLostStartsRecordingAgain() async throws {
        let harness = Harness(now: Fixture.sep(24, 8), offers: [Self.breakfast])
        let reservation = harness.marketplace.add(Fixture.reservation(for: Self.breakfast))
        _ = try await harness.walkRewards.startWalk(
            reservationID: reservation.id, restaurantID: "near", at: Fixture.sep(24, 7, 40))
        let model = PickupModel(
            reservationID: reservation.id, origin: ResolvedLocation(coordinate: Fixture.licCenter, source: .device),
            dependencies: harness.dependencies)
        await model.load()
        #expect(harness.walkTracker.isTracking(reservation.id))
        #expect(model.trackingStatus == .tracking)
    }

    @Test func cancellingTheOrderStopsTheRecording() async {
        let (model, harness, reservation) = await pickup(at: Fixture.sep(24, 7))
        await model.startWalk()
        _ = try? await harness.marketplace.cancel(reservationID: reservation.id, reason: nil, at: Fixture.sep(24, 7, 5))
        await model.load()
        #expect(!harness.walkTracker.isTracking(reservation.id))
        #expect(model.trackingStatus == .idle)
    }

    // MARK: Live progress

    func walkingContent(_ model: PickupModel) -> PickupModel.WalkSection.Walking? {
        if case .walking(let walking)? = model.walkSection { return walking }
        return nil
    }

    @Test func noProgressBeforeTheWalkStarts() async {
        let (model, _, _) = await pickup(at: Fixture.sep(24, 7))
        #expect(model.liveProgress == nil)
    }

    @Test func progressShowsMilesWalkedAndMilesToGo() async throws {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.walkTracker.script(Array(Self.track().prefix(3)))  // a third of the way
        await model.startWalk()
        let walking = try #require(walkingContent(model))
        #expect(walking.phase == .walking)
        #expect(walking.progressText == "0.1 mi walked · 0.2 mi to go")
        #expect(abs(walking.fraction - 1.0 / 3) < 0.02)
        #expect(walking.detail == "Started at 8:00 AM. Swipe to confirm pickup when you arrive.")
        #expect(!walking.ticks.isEmpty)  // a tick every 0.1 mi
    }

    @Test func progressAdvancesAsFixesArrive() async throws {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.walkTracker.script(Array(Self.track().prefix(3)))
        await model.startWalk()
        harness.walkTracker.script(Array(Self.track().prefix(5)))
        await model.refreshLiveProgress()
        let walking = try #require(walkingContent(model))
        #expect(walking.progressText == "0.2 mi walked · 0.1 mi to go")
    }

    @Test func arrivingWhileOpenShrinksToOneLine() async throws {
        let (model, _, _) = await pickup(at: Fixture.sep(24, 8))
        await model.startWalk()  // the full track ends at the door
        let walking = try #require(walkingContent(model))
        #expect(walking.phase == .arrived)
        #expect(walking.title == "0.3 mi walked · swipe below to confirm")
        #expect(walking.detail == nil)
        #expect(walking.fraction == 1)
    }

    @Test func arrivingBeforeTheWindowOpensSaysYouAreEarly() async throws {
        // 7:00, window opens at 7:30; Start walk opened at 6:30.
        let (model, _, _) = await pickup(at: Fixture.sep(24, 7))
        await model.startWalk()
        let walking = try #require(walkingContent(model))
        #expect(walking.phase == .arrivedEarly)
        #expect(walking.title == "You've arrived")
        #expect(walking.detail == "You're here early. Pickup opens at 7:30 AM — your miles are saved.")
        #expect(walking.progressText == "0.3 mi walked")
    }

    @Test func walkingBeforeTheWindowSaysWhenPickupOpens() async throws {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 7))
        harness.walkTracker.script(Array(Self.track().prefix(3)))
        await model.startWalk()
        let walking = try #require(walkingContent(model))
        #expect(walking.phase == .walking)
        #expect(walking.detail == "Started at 7:00 AM. Pickup opens at 7:30 AM.")
    }

    @Test func waitsForAFirstLocation() async throws {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.walkTracker.script([])
        await model.startWalk()
        let walking = try #require(walkingContent(model))
        #expect(walking.progressText == "Waiting for your first location…")
        #expect(walking.fraction == 0)  // the bar still shows, empty
        #expect(walking.warning == nil)
    }

    @Test func aLongWaitForALocationSuggestsKeepingTheAppOpen() async throws {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.walkTracker.script([])
        await model.startWalk()
        for _ in 0..<PickupModel.noFixHintAfterPolls { await model.refreshLiveProgress() }
        let walking = try #require(walkingContent(model))
        #expect(walking.warning == "No location yet. Keep Walk & Take open while you walk.")
    }

    @Test func progressClearsOnceThePickupIsConfirmed() async {
        let (model, _, _) = await pickup(at: Fixture.sep(24, 8))
        await model.startWalk()
        #expect(model.liveProgress != nil)
        await model.collect()
        #expect(model.liveProgress == nil)
    }

    // MARK: Developer mode

    @Test func noDemoControlsOutsideDeveloperMode() async {
        let (model, _, _) = await pickup(at: Fixture.sep(24, 6))
        #expect(model.demoWalkControls == nil)
        #expect(!model.canOpenPickupNow)
    }

    @Test func developerModeCanStartAWalkBeforeTheUsualHour() async {
        // 6:00: the window opens at 7:30, so the real Start walk button opens at 6:30.
        let (model, harness, reservation) = await pickup(at: Fixture.sep(24, 6))
        harness.developer.isOn = true
        #expect(!model.canStartWalk)
        #expect(model.demoWalkControls == .startNow)
        await model.startWalkNow()
        #expect(model.walk != nil)
        #expect(harness.walkTracker.isTracking(reservation.id))
    }

    @Test func aSimulatedWalkOffersStepPauseAndArrive() async {
        let (model, harness, reservation) = await pickup(at: Fixture.sep(24, 8))
        harness.developer.isOn = true
        harness.demo.simulatedWalks.insert(reservation.id)
        harness.demo.autoWalking.insert(reservation.id)
        harness.walkTracker.script(Array(Self.track().prefix(3)))
        await model.startWalk()
        #expect(model.demoWalkControls == .simulated(isAutoWalking: true, arrived: false))
        await model.demoStep()
        #expect(model.demoWalkControls == .simulated(isAutoWalking: false, arrived: false))
        await model.demoToggleAutoWalk()
        await model.demoArrive()
        #expect(harness.demo.walkCalls == ["advance 0.1", "auto", "arrive"])
    }

    @Test func aGPSWalkCantBeDriven() async {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.developer.isOn = true
        await model.startWalk()
        #expect(model.demoWalkControls == .live)
    }

    @Test func theOrderScreenSendsItsPickupReminder() async throws {
        let (model, harness, reservation) = await pickup(at: Fixture.sep(24, 8))
        harness.developer.isOn = true
        await model.demoSendReminder()
        let sent = try #require(harness.notifications.sentReminders.first)
        #expect(sent.reservationID == reservation.id)
        #expect(sent.isOpen)
    }

    @Test func confirmPickupNowOpensTheWindowAndCompletesThePickup() async {
        let (model, harness, reservation) = await pickup(at: Fixture.sep(24, 7))
        harness.developer.isOn = true
        await model.demoConfirmPickup()
        #expect(harness.clock.now == reservation.snapshot.pickupWindow.start)
        #expect(model.status == .collected)
    }

    @Test func openPickupNowMovesTheClockToTheWindow() async {
        let (model, harness, reservation) = await pickup(at: Fixture.sep(24, 7))
        harness.developer.isOn = true
        #expect(model.canOpenPickupNow)
        model.openPickupNow()
        #expect(harness.clock.now == reservation.snapshot.pickupWindow.start)
        model.jumpToClosing()
        #expect(harness.clock.now == reservation.snapshot.pickupWindow.end.addingTimeInterval(-300))
    }

    // MARK: Miles earned

    @Test func aWalkedPickupShowsTheMilesEarnedWithTheFirstCatchphrase() async throws {
        let (model, _, _) = await pickup(at: Fixture.sep(24, 8))
        #expect(model.walkEarned == nil)  // nothing until the pickup is done
        await model.startWalk()
        await model.collect()
        let card = try #require(model.walkEarned)
        #expect(card.headline == "+0.3 mi earned")
        #expect(card.catchphrase == "Walk&Take: every mile gets you something.")
        #expect(card.contribution == "Walked pickup #1")
        #expect(card.progress == "0.3 mi walked in total · 0.7 mi to your next reward")
        #expect(card.unlock == nil)
    }

    @Test func eachCreditedPickupGetsTheNextCatchphrase() async throws {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.walkRewards.seed(miles: 0.4)  // one earlier credited pickup
        await model.startWalk()
        await model.collect()
        let card = try #require(model.walkEarned)
        #expect(card.catchphrase == "Walk it. Earn it.")
        #expect(card.contribution == "Walked pickup #2")
        #expect(card.progress == "0.7 mi walked in total · 0.3 mi to your next reward")
    }

    @Test func reachingAMilestoneShowsTheUnlock() async throws {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.walkRewards.seed(miles: 0.9)
        await model.startWalk()
        await model.collect()
        let card = try #require(model.walkEarned)
        #expect(card.unlock == "Reward unlocked: 50% off one bag")
        #expect(card.progress == "1.2 mi walked in total · 3.8 mi to your next reward")
    }

    @Test func theSameCardShowsWhenTheOrderIsOpenedAgain() async throws {
        let (model, harness, reservation) = await pickup(at: Fixture.sep(24, 8))
        harness.walkRewards.seed(miles: 0.9)
        await model.startWalk()
        await model.collect()
        let reopened = PickupModel(
            reservationID: reservation.id, origin: ResolvedLocation(coordinate: Fixture.licCenter, source: .device),
            dependencies: harness.dependencies)
        await reopened.load()
        #expect(reopened.walkEarned == model.walkEarned)
        #expect(reopened.walkEarned?.unlock != nil)
    }

    @Test func noCardWithoutCreditedMilesOrWithoutAWalk() async {
        let (rejected, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.walkTracker.script(Self.track(simulated: true))
        await rejected.startWalk()
        await rejected.collect()
        #expect(rejected.walkEarned == nil)

        let (unwalked, _, _) = await pickup(at: Fixture.sep(24, 8))
        await unwalked.collect()
        #expect(unwalked.walkEarned == nil)
    }

    @Test func noCardWithTheFlagOff() async {
        let (model, _, _) = await pickup(at: Fixture.sep(24, 8), flags: Fixture.flags(walkRewards: false))
        await model.collect()
        #expect(model.walkEarned == nil)
    }

    // MARK: Completing

    @Test func swipingAtTheCounterCreditsTheMiles() async throws {
        let (model, harness, reservation) = await pickup(at: Fixture.sep(24, 8))
        await model.startWalk()
        await model.collect()
        let walk = try #require(model.walk)
        #expect(walk.finishedAt != nil)
        #expect(walk.rejection == nil)
        #expect(abs(walk.creditedMiles - 0.3) < 0.02)
        #expect(model.walkResultText == "+0.3 mi counted toward rewards")
        #expect(model.walkEarned != nil)
        #expect(!model.summary.contains { $0.label == "Walk" })  // the earned card already says it
        #expect(!harness.walkTracker.isTracking(reservation.id))
        #expect(model.trackingStatus == .idle)
        #expect(abs(try await harness.walkRewards.totalMiles() - 0.3) < 0.02)
        #expect(model.walkSection == nil)
    }

    @Test func crossingAMilestoneBanksAReward() async throws {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.walkRewards.seed(miles: 0.9)
        await model.startWalk()
        await model.collect()
        #expect(model.walkCompletion?.newRewards.map(\.milestoneMiles) == [1])
        #expect(try await harness.walkRewards.rewards().count == 1)
    }

    @Test func aSuspectTrackStillCompletesThePickupButEarnsNothing() async throws {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.walkTracker.script(Self.track(simulated: true))
        await model.startWalk()
        await model.collect()
        #expect(model.status == .collected)
        #expect(model.walk?.creditedMiles == 0)
        #expect(model.walk?.rejection == .simulatedLocation)
        #expect(model.walkResultText == WalkRejection.simulatedLocation.message)
        #expect(model.summary.last?.label == "Walk")  // no earned card, so the row explains why
        #expect(try await harness.walkRewards.totalMiles() == 0)
    }

    @Test func noRecordedFixesMeansNoMiles() async {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        harness.walkTracker.script([])
        await model.startWalk()
        await model.collect()
        #expect(model.status == .collected)
        #expect(model.walk?.rejection == .notEnoughData)
    }

    @Test func pickingUpWithoutAWalkJustCollects() async throws {
        let (model, harness, _) = await pickup(at: Fixture.sep(24, 8))
        await model.collect()
        #expect(model.status == .collected)
        #expect(model.walk == nil)
        #expect(model.walkResultText == nil)
        #expect(try await harness.walkRewards.totalMiles() == 0)
    }

    @Test func aRefusedPickupKeepsTheWalkGoing() async {
        // Too early for the swipe: the window opens at 7:30.
        let (model, harness, reservation) = await pickup(at: Fixture.sep(24, 7))
        await model.startWalk()
        await model.collect()
        #expect(model.collectFailed)
        #expect(model.walk?.finishedAt == nil)
        #expect(harness.walkTracker.isTracking(reservation.id))
    }

    @Test func aSecondPickupFromTheSameRestaurantTodayEarnsNothing() async throws {
        let (first, harness, _) = await pickup(at: Fixture.sep(24, 8))
        await first.startWalk()
        await first.collect()
        #expect(first.walk?.creditedMiles ?? 0 > 0)

        let second = harness.marketplace.add(Fixture.reservation(for: Self.breakfast))
        let model = PickupModel(
            reservationID: second.id, origin: ResolvedLocation(coordinate: Fixture.licCenter, source: .device),
            dependencies: harness.dependencies)
        await model.load()
        await model.startWalk()
        await model.collect()
        #expect(model.walk?.rejection == .repeatPickupToday)
        #expect(model.walkResultText == WalkRejection.repeatPickupToday.message)
    }
}

@MainActor
@Suite("Manage order")
struct ManageOrderModelTests {
    static let offer = Fixture.offer("breakfast", start: (7, 30), end: (10, 0), price: 599, total: 5, reserved: 1)

    func manage(quantity: Int = 2, at now: Date = Fixture.sep(24, 8)) async -> (ManageOrderModel, Harness) {
        let harness = Harness(now: now, offers: [Self.offer])
        let reservation = harness.marketplace.add(Fixture.reservation(for: Self.offer, quantity: quantity))
        let model = ManageOrderModel(reservationID: reservation.id, dependencies: harness.dependencies)
        await model.load()
        return (model, harness)
    }

    @Test func limitsAndCopy() async {
        let (model, _) = await manage()  // 5 total, 1 simulated + 2 ours → 2 left
        #expect(model.quantity == 2)
        #expect(model.maxQuantity == 3)
        #expect(!model.canSave)
        #expect(model.quantityFooter == "You can hold up to 3 bags. Near Café has 1 more available.")
        #expect(model.deadlineNotice.title == "Free changes until 9:50 AM")
        #expect(model.deadlineNotice.detail == "10 minutes before pickup ends")
        #expect(model.pickupText == "Today · until 10:00 AM")
    }

    @Test func minutesLeftUnderAnHour() async {
        let (model, _) = await manage(at: Fixture.sep(24, 9, 25))
        #expect(model.deadlineNotice.detail == "25 min left")
    }

    @Test func saveChangesStock() async {
        let (model, harness) = await manage()
        model.quantity = 3
        #expect(model.canSave)
        #expect(model.newTotal == Money(cents: 1797))
        await model.saveQuantity()
        #expect(model.finished)
        #expect(harness.marketplace.offerLeft(Self.offer.id) == 1)
    }

    @Test func cancelWithReasonReturnsStock() async throws {
        let (model, harness) = await manage()
        model.reason = .plansChanged
        #expect(model.cancelMessage == "Your bags go back on sale for other customers. You won't be charged.")
        await model.cancel()
        #expect(model.finished)
        #expect(harness.marketplace.offerLeft(Self.offer.id) == 4)
        #expect(try await harness.marketplace.reservations().first?.cancelReason == .plansChanged)
    }

    @Test func refusedChangesRaiseTheAlert() async {
        let (model, harness) = await manage()
        harness.marketplace.failNextReserve(with: ReservationError.changeClosed)
        await model.cancel()
        #expect(model.failed)
        #expect(!model.finished)
    }

    @Test func closedAfterTheDeadline() async {
        let (model, _) = await manage(at: Fixture.sep(24, 9, 51))
        #expect(!model.isOpen)
        #expect(model.deadlineNotice.title == "Changes closed at 9:50 AM")
    }

    @Test func cancellingGivesBackTheRewardTheOrderUsed() async throws {
        let harness = Harness(now: Fixture.sep(24, 8), offers: [Self.offer])
        let reward = Reward(milestoneMiles: 1, earnedAt: Fixture.sep(20, 9))
        harness.walkRewards.seed(rewards: [reward])
        let reservationID = UUID()
        _ = try await harness.walkRewards.redeemReward(
            id: reward.id, reservationID: reservationID, at: Fixture.sep(24, 7))
        let reserved = try await harness.marketplace.reserve(
            offerID: Self.offer.id, quantity: 1, reservationID: reservationID, rewardID: reward.id,
            at: Fixture.sep(24, 7))
        let model = ManageOrderModel(reservationID: reserved.id, dependencies: harness.dependencies)
        await model.load()
        await model.cancel()
        #expect(model.finished)
        #expect(try await harness.walkRewards.rewards().first?.isAvailable == true)
    }
}
