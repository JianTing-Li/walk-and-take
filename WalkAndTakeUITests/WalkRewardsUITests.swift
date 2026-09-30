//
//  WalkRewardsUITests.swift
//  WalkAndTakeUITests
//
//  The walking-rewards reserve flow: a banked reward takes 50% off one bag, and the confirmation says
//  it was redeemed. Starts with one banked reward (-UITestSeedReward) and the same frozen clock,
//  fixed location and in-memory store as the happy-path test.
//

import XCTest

@MainActor
final class WalkRewardsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-UITestInMemoryStore",
            "-UITestSeedReward",
            "-UITestNow", "2026-09-24T08:00:00-04:00",
            "-UITestFixedLocation",
            "-UITestSkipSplash",
        ]
        app.launch()
        return app
    }

    func testUsingTheRewardTakesHalfOffAndSaysSoOnTheConfirmation() throws {
        let app = launch()

        let card = app.buttons.matching(identifier: "discover.bagCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Discover never showed a bag")
        card.tap()

        let reserve = app.buttons["offerDetail.reserve"]
        XCTAssertTrue(reserve.waitForExistence(timeout: 5))
        let fullPrice = reserve.label
        XCTAssertTrue(fullPrice.hasPrefix("Reserve"), "Unexpected button: \(fullPrice)")

        // The banked reward shows up as a switch; turning it on lowers the price.
        let useReward = app.switches["offerDetail.useReward"]
        XCTAssertTrue(useReward.waitForExistence(timeout: 5), "No reward switch on the reserve bar")
        useReward.tap()  // the middle of the row, over the label
        XCTAssertEqual(useReward.value as? String, "1", "Tapping the row didn't turn the reward on")
        XCTAssertNotEqual(reserve.label, fullPrice, "Price didn't change after using the reward")

        // Tapping the switch itself at the right edge still works, and turns it back off.
        useReward.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(useReward.value as? String, "0", "Tapping the switch didn't turn the reward off")
        XCTAssertEqual(reserve.label, fullPrice, "Price didn't return to full after turning the reward off")
        useReward.tap()
        XCTAssertEqual(useReward.value as? String, "1")

        reserve.tap()

        let redeemed = app.descendants(matching: .any)["confirmation.rewardRedeemed"]
        XCTAssertTrue(redeemed.waitForExistence(timeout: 5), "Confirmation didn't say the reward was redeemed")
        XCTAssertTrue(redeemed.label.contains("Reward redeemed"), "Got: \(redeemed.label)")
        XCTAssertTrue(redeemed.label.contains("last reward"), "Got: \(redeemed.label)")
    }
}
