//
//  OfferDetailModelTests.swift
//  CustomerFeaturesTests
//

import DesignSystem
import Domain
import Foundation
import Platform
import Testing

@testable import CustomerFeatures

@MainActor
@Suite("Offer detail & reserve")
struct OfferDetailModelTests {
    static let todayID = "breakfast-2026-09-24"
    static let tomorrowID = "breakfast-2026-09-25"
    static let offers = [
        Fixture.offer("breakfast", start: (7, 30), end: (10, 0), price: 599, total: 5, reserved: 1),
        Fixture.offer("breakfast", day: 25, start: (7, 30), end: (10, 0), price: 599),
        Fixture.offer("lastone", start: (8, 0), end: (11, 0), total: 3, reserved: 2),
    ]

    struct Setup {
        let model: OfferDetailModel
        let harness: Harness
        let navigation: CustomerNavigation
    }

    func detail(
        _ offerID: String = todayID, at now: Date = Fixture.sep(24, 8), flags: FeatureFlags = Fixture.flags()
    ) async -> Setup {
        let harness = Harness(now: now, offers: Self.offers, flags: flags)
        let navigation = CustomerNavigation()
        let model = OfferDetailModel(
            offerID: offerID, origin: ResolvedLocation(coordinate: Fixture.licCenter, source: .device),
            dependencies: harness.dependencies, navigation: navigation)
        await model.load()
        return Setup(model: model, harness: harness, navigation: navigation)
    }

    // MARK: Content

    @Test func loadedContentUsesFullDateCopy() async {
        let model = await detail().model
        #expect(model.state == .loaded)
        #expect(model.restaurantName == "Near Café")
        #expect(model.pickupText == "Pick up today, Thu Sep 24, 7:30–10:00 AM")
        #expect(model.urgencyText == "Ends at 10:00 AM")
        #expect(model.addressTitle == "Vernon Blvd & 48th Ave")
        #expect(model.addressSubtitle == "0.2 mi away · Long Island City")
        #expect(model.subtitle == "4.5 (100 ratings) · Breakfast")
        #expect(model.reserveButtonTitle == "Reserve · $5.99")
        #expect(model.canReserve)
    }

    @Test func tomorrowsOfferIsLabeledTomorrow() async {
        let model = await detail(Self.tomorrowID, at: Fixture.sep(24, 20, 30)).model
        #expect(model.pickupText == "Pick up tomorrow, Fri Sep 25, 7:30–10:00 AM")
        #expect(model.urgencyText == "Opens tomorrow at 7:30 AM")
        #expect(model.canReserve)
    }

    @Test func tomorrowBeforeEightPMCantBeReserved() async {
        let model = await detail(Self.tomorrowID, at: Fixture.sep(24, 19)).model
        #expect(!model.canReserve)
        #expect(model.reserveButtonTitle == "Opens for reservations at 8 PM")
    }

    @Test func notFound() async {
        #expect(await detail("nope-2026-09-24").model.state == .notFound)
    }

    @Test func failedLoad() async {
        let harness = Harness(now: Fixture.sep(24, 8), offers: Self.offers)
        harness.marketplace.failReads(true)
        let model = OfferDetailModel(
            offerID: Self.todayID, origin: ResolvedLocation(coordinate: Fixture.licCenter, source: .device),
            dependencies: harness.dependencies, navigation: CustomerNavigation())
        await model.load()
        guard case .failed = model.state else {
            Issue.record("expected failed")
            return
        }
    }

    @Test func reviewsFlagOffHidesRating() async {
        #expect(await detail(flags: Fixture.flags(reviews: false)).model.subtitle == "Breakfast")
    }

    // MARK: Quantity

    @Test func quantityIsCappedAtThreeOrWhatsLeft() async {
        let model = await detail().model
        #expect(model.reserve.maxQuantity == 3)  // 4 left
        let lastOne = await detail("lastone-2026-09-24").model
        #expect(lastOne.reserve.maxQuantity == 1)
        model.reserve.quantity = 3
        #expect(model.reserveButtonTitle == "Reserve · $17.97")
    }

    // MARK: Reserving

    @Test func reserveShowsConfirmation() async throws {
        let setup = await detail()
        let reserve = setup.model.reserve
        reserve.quantity = 2
        await reserve.reserve()
        let confirmation = try #require(reserve.confirmation)
        #expect(confirmation.code == "AB21")
        #expect(confirmation.bagsText == "2 × breakfast bag")
        #expect(confirmation.totalText == "$11.98")
        #expect(confirmation.pickupText == "Pick up today, Thu Sep 24, 7:30–10:00 AM")
        #expect(confirmation.pickupInstructions == "Ask at the counter.")
        #expect(confirmation.policyText.hasPrefix("Free changes and cancellation until 9:50 AM."))
        #expect(reserve.quantity == 1)
        #expect(reserve.alert == nil)
        #expect(setup.harness.marketplace.reservationCount == 1)
    }

    @Test func manageOrderFlagOffDropsTheChangePolicy() async throws {
        let reserve = await detail(flags: Fixture.flags(manageOrder: false)).model.reserve
        await reserve.reserve()
        #expect(try #require(reserve.confirmation).policyText == "Find this order anytime in the Orders tab.")
    }

    @Test(arguments: [ReservationError.soldOut, .windowClosed, .invalidQuantity, .offerNoLongerExists])
    func unavailableErrorsUseTheDraftAlert(error: ReservationError) async {
        let setup = await detail()
        setup.harness.marketplace.failNextReserve(with: error)
        await setup.model.reserve.reserve()
        #expect(setup.model.reserve.alert == .noLongerAvailable)
        #expect(setup.model.reserve.alert?.title == "This bag is no longer available")
        #expect(setup.model.reserve.confirmation == nil)
    }

    @Test func notVisibleYetExplainsEightPM() async {
        let setup = await detail()
        setup.harness.marketplace.failNextReserve(with: ReservationError.notVisibleYet)
        await setup.model.reserve.reserve()
        #expect(setup.model.reserve.alert?.title == "Opens for reservations at 8 PM")
    }

    @Test func unexpectedErrorsSaySomethingWentWrong() async {
        let setup = await detail()
        setup.harness.marketplace.failNextReserve(with: TestError())
        await setup.model.reserve.reserve()
        #expect(setup.model.reserve.alert == .failed)
    }

    @Test func viewOrderSwitchesToOrders() async throws {
        let setup = await detail()
        setup.navigation.discoverPath = [.offer(id: Self.todayID)]
        await setup.model.reserve.reserve()
        let confirmation = try #require(setup.model.reserve.confirmation)
        setup.model.viewOrder(confirmation)
        #expect(setup.model.reserve.confirmation == nil)
        #expect(setup.navigation.selectedTab == .orders)
        #expect(setup.navigation.ordersPath == [.pickup(reservationID: confirmation.id)])
        #expect(setup.navigation.discoverPath.isEmpty)
    }

    // MARK: Favorites

    @Test func favoriteToggleFollowsItsFlag() async {
        let setup = await detail()
        await setup.model.toggleFavorite()
        #expect(setup.model.isFavorite)
        #expect(setup.harness.userData.favoriteIDs == ["near"])
        let off = await detail(flags: Fixture.flags(favorites: false))
        await off.model.toggleFavorite()
        #expect(off.harness.userData.favoriteIDs.isEmpty)
    }

    // MARK: Walking rewards

    @Test func detailShowsTheWalkAndItsReward() async throws {
        let card = try #require(await detail().model.walkCard)
        #expect(card.title == "0.2 mi walk · about 4 min")
        #expect(card.detail == "Earns +0.2 mi toward your next reward")
        #expect(card.footnote == nil)
    }

    @Test func farWalksExplainThePerPickupCap() async throws {
        let far = Fixture.offer("farbag", restaurant: "far", start: (7, 30), end: (10, 0))
        let harness = Harness(now: Fixture.sep(24, 8), offers: [far])
        let model = OfferDetailModel(
            offerID: far.id, origin: ResolvedLocation(coordinate: Fixture.licCenter, source: .device),
            dependencies: harness.dependencies, navigation: CustomerNavigation())
        await model.load()
        let card = try #require(model.walkCard)
        #expect(card.title == "2.1 mi walk · about 31 min")
        #expect(card.detail == "Earns +2.0 mi toward your next reward")
        #expect(card.footnote == "One pickup can add up to 2.0 mi.")
    }

    @Test func walkRewardFlagOffHidesThePanel() async {
        #expect(await detail(flags: Fixture.flags(walkRewards: false)).model.walkCard == nil)
    }

    // MARK: Using a walking reward

    static func reward(_ miles: Double = 1, earnedAt: Date = Fixture.sep(20, 9)) -> Reward {
        Reward(milestoneMiles: miles, earnedAt: earnedAt)
    }

    func detailWithReward(flags: FeatureFlags = Fixture.flags()) async -> Setup {
        let setup = await detail(flags: flags)
        setup.harness.walkRewards.seed(rewards: [Self.reward()])
        await setup.model.load()
        return setup
    }

    @Test func noToggleWithoutABankedReward() async {
        let setup = await detail()
        #expect(!setup.model.reserve.showsRewardToggle)
        #expect(setup.model.rewardLine == nil)
    }

    @Test func aBankedRewardShowsTheToggleAndTheDiscountBeforeConfirming() async {
        let model = await detailWithReward().model
        #expect(model.reserve.showsRewardToggle)
        #expect(model.reserveButtonTitle == "Reserve · $5.99")
        model.reserve.useReward = true
        #expect(model.reserve.rewardDiscount == Money(cents: 299))
        #expect(model.reserveButtonTitle == "Reserve · $3.00")
        #expect(model.rewardLine == "50% off one bag: −$2.99")
        model.reserve.quantity = 2
        #expect(model.reserveButtonTitle == "Reserve · $8.99")  // 2 x $5.99 - $2.99
    }

    @Test func reservingWithARewardUsesItUp() async throws {
        let setup = await detailWithReward()
        setup.model.reserve.useReward = true
        await setup.model.reserve.reserve()
        let confirmation = try #require(setup.model.reserve.confirmation)
        #expect(confirmation.rewardText == "50% off one bag: −$2.99")
        #expect(confirmation.totalText == "$3.00")
        let saved = try #require(try await setup.harness.marketplace.reservation(id: confirmation.id))
        #expect(saved.rewardID != nil)
        let rewards = try await setup.harness.walkRewards.rewards()
        #expect(rewards.allSatisfy { !$0.isAvailable })
        #expect(rewards.first?.redeemedReservationID == saved.id)
        #expect(!setup.model.reserve.showsRewardToggle)
        #expect(!setup.model.reserve.useReward)
    }

    @Test func aRewardThatWasAlreadyUsedBlocksTheReservation() async throws {
        let setup = await detailWithReward()
        setup.model.reserve.useReward = true
        // Another screen spends the reward first.
        let reward = try #require(try await setup.harness.walkRewards.rewards().first)
        _ = try await setup.harness.walkRewards.redeemReward(
            id: reward.id, reservationID: UUID(), at: Fixture.sep(24, 8))
        await setup.model.reserve.reserve()
        #expect(setup.model.reserve.alert == .rewardUnavailable)
        #expect(setup.model.reserve.confirmation == nil)
        #expect(setup.harness.marketplace.reservationCount == 0)
        #expect(!setup.model.reserve.showsRewardToggle)
    }

    @Test func aFailedReservationHandsTheRewardBack() async throws {
        let setup = await detailWithReward()
        setup.model.reserve.useReward = true
        setup.harness.marketplace.failNextReserve(with: ReservationError.soldOut)
        await setup.model.reserve.reserve()
        #expect(setup.model.reserve.alert == .noLongerAvailable)
        #expect(try await setup.harness.walkRewards.rewards().first?.isAvailable == true)
        #expect(setup.model.reserve.showsRewardToggle)
    }

    @Test func rewardsStayOffWhenTheFlagIsOff() async {
        let setup = await detailWithReward(flags: Fixture.flags(walkRewards: false))
        #expect(!setup.model.reserve.showsRewardToggle)
    }

    // MARK: Effect on progress

    func detailWithMiles(_ miles: Double) async -> OfferDetailModel {
        let setup = await detail()
        setup.harness.walkRewards.seed(miles: miles)
        await setup.model.load()
        return setup.model
    }

    @Test func detailShowsProgressAfterThisPickup() async throws {
        let card = try #require(await detailWithMiles(1.2).walkCard)
        #expect(card.outcome == "After this pickup: 1.4 of 5 mi · 3.6 mi to go")
        #expect(card.unlock == nil)
    }

    @Test func detailSaysWhenThePickupUnlocksAReward() async throws {
        let card = try #require(await detailWithMiles(0.9).walkCard)
        #expect(card.outcome == "After this pickup: 1.1 mi walked")
        #expect(card.unlock == "Unlocks a reward: 50% off one bag")
    }

    @Test func aFirstTimeWalkerSeesTheFirstReward() async throws {
        let card = try #require(await detail().model.walkCard)
        #expect(card.outcome == "After this pickup: 0.2 of 1 mi · 0.8 mi to go")
    }

    // MARK: Walk-to-qualify reminder (confirmation sheet)

    @Test func theConfirmationExplainsWhenStartWalkOpens() async throws {
        // At 8:00 the window (7:30) is already open, so Start walk is open now.
        let open = await detail().model.reserve
        await open.reserve()
        let openText = try #require(open.confirmation?.walkReminderText)
        #expect(openText.hasPrefix("Walk to count your miles: tap Start walk on this order, then swipe to confirm"))
        #expect(openText.hasSuffix("Driving or riding earns no miles."))

        // Reserving tomorrow's bag at 8:30 PM: Start walk opens tomorrow at 6:30 AM.
        let later = await detail(Self.tomorrowID, at: Fixture.sep(24, 20, 30)).model.reserve
        await later.reserve()
        let laterText = try #require(later.confirmation?.walkReminderText)
        #expect(
            laterText.hasPrefix("Walk to count your miles: Start walk opens on Fri Sep 25 at 6:30 AM on this order."))
    }

    @Test func noConfirmationReminderWhenTheFlagIsOff() async {
        let reserve = await detail(flags: Fixture.flags(walkRewards: false)).model.reserve
        await reserve.reserve()
        #expect(reserve.confirmation?.walkReminderText == nil)
    }

    // MARK: Reward redeemed message

    func reserveWithRewards(_ rewards: [Reward]) async throws -> ReserveModel {
        let setup = await detail()
        setup.harness.walkRewards.seed(rewards: rewards)
        await setup.model.load()
        setup.model.reserve.useReward = true
        await setup.model.reserve.reserve()
        return setup.model.reserve
    }

    @Test func usingTheLastRewardSaysSoAndWhatItSaved() async throws {
        let reserve = try await reserveWithRewards([Self.reward()])
        let redeemed = try #require(reserve.confirmation?.rewardRedeemed)
        #expect(redeemed.title == "Reward redeemed")
        #expect(redeemed.detail == "50% off one bag saved you $2.99.")
        #expect(redeemed.footer == "That was your last reward. Keep walking to earn the next one.")
    }

    @Test func theMessageCountsTheRewardsStillBanked() async throws {
        let one = try await reserveWithRewards([Self.reward(), Self.reward(5)])
        #expect(try #require(one.confirmation?.rewardRedeemed).footer == "1 more reward is ready to use.")
        let two = try await reserveWithRewards([Self.reward(), Self.reward(5), Self.reward(15)])
        #expect(try #require(two.confirmation?.rewardRedeemed).footer == "2 more rewards are ready to use.")
    }

    @Test func noRedeemedMessageWhenNoRewardWasUsed() async throws {
        let setup = await detail()
        setup.harness.walkRewards.seed(rewards: [Self.reward()])
        await setup.model.load()
        await setup.model.reserve.reserve()  // reward toggle left off
        #expect(setup.model.reserve.confirmation?.rewardRedeemed == nil)
        #expect(try await setup.harness.walkRewards.rewards().first?.isAvailable == true)
    }
}
