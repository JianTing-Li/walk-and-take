//
//  WalkCopyTests.swift
//  CustomerFeaturesTests
//

import Testing

@testable import CustomerFeatures

@Suite("Walk copy")
struct WalkCopyTests {
    // MARK: Comparing with the nearest bag

    @Test func theNearestBagIsLabelled() {
        #expect(WalkCopy.compareText(distance: 0.23, nearest: 0.23) == "Nearest bag")
        // Both read "0.2 mi away", so neither is "farther".
        #expect(WalkCopy.compareText(distance: 0.24, nearest: 0.21) == "Nearest bag")
    }

    @Test func fartherBagsSayHowMuchFartherAndHowMuchMoreTheyEarn() {
        #expect(
            WalkCopy.compareText(distance: 0.6, nearest: 0.2) == "0.4 mi farther than the nearest · earns 0.4 mi more")
    }

    @Test func theMoreEarnedPartDropsOutOnceBothHitTheCap() {
        // Nearest is already 2.0 mi (the most a pickup earns), so going farther earns nothing more.
        #expect(WalkCopy.compareText(distance: 2.6, nearest: 2.1) == "0.5 mi farther than the nearest")
    }

    @Test func fartherAndEarnsMoreAgreeWhenRoundingSplitsThem() {
        // 0.04 mi reads "0.0", 0.49 mi reads "0.5": 0.5 farther, and 0.5 more earned (not 0.45 -> 0.4).
        #expect(
            WalkCopy.compareText(distance: 0.49, nearest: 0.04) == "0.5 mi farther than the nearest · earns 0.5 mi more"
        )
    }

    @Test func theCapLimitsWhatFartherEarns() {
        // 0.5 -> 3.0 mi is 2.5 mi farther, but earning only goes from 0.5 to 2.0.
        #expect(
            WalkCopy.compareText(distance: 3.0, nearest: 0.5) == "2.5 mi farther than the nearest · earns 1.5 mi more")
    }

    // MARK: Effect on progress

    @Test func progressBeforeAMilestoneShowsMilesToGo() {
        #expect(
            WalkCopy.outcomeText(currentMiles: 1.2, distance: 0.5) == "After this pickup: 1.7 of 5 mi · 3.3 mi to go")
        #expect(WalkCopy.unlockText(currentMiles: 1.2, distance: 0.5) == nil)
    }

    @Test func reachingAMilestoneUnlocksAReward() {
        #expect(WalkCopy.outcomeText(currentMiles: 0.9, distance: 0.5) == "After this pickup: 1.4 mi walked")
        #expect(WalkCopy.unlockText(currentMiles: 0.9, distance: 0.5) == "Unlocks a reward: 50% off one bag")
    }

    @Test func landingExactlyOnAMilestoneCounts() {
        #expect(WalkCopy.unlockText(currentMiles: 4.5, distance: 0.5) != nil)
        #expect(WalkCopy.unlockText(currentMiles: 4.4, distance: 0.5) == nil)
    }

    @Test func farWalksOnlyCountTheirCappedMiles() {
        // A 5 mi walk adds only 2.0: 3.0 -> 5.0 lands right on the 5 mi milestone, 2.9 -> 4.9 doesn't.
        #expect(WalkCopy.unlockText(currentMiles: 3.0, distance: 5) != nil)
        #expect(WalkCopy.unlockText(currentMiles: 2.9, distance: 5) == nil)
        #expect(WalkCopy.outcomeText(currentMiles: 1, distance: 5) == "After this pickup: 3.0 of 5 mi · 2.0 mi to go")
    }

    @Test func wholeMilestonesDropTheDecimal() {
        #expect(WalkCopy.milestone(5) == "5")
        #expect(WalkCopy.milestone(15) == "15")
        #expect(WalkCopy.milestone(2.5) == "2.5")
    }

    @Test func walkTitleAddsTheEstimatedTime() {
        #expect(WalkCopy.walkTitleWithTime(forDistance: 1.0) == "1.0 mi walk · about 15 min")
        #expect(WalkCopy.walkTitleWithTime(forDistance: 0.5) == "0.5 mi walk · about 8 min")
        #expect(WalkCopy.walkTitleWithTime(forDistance: 0.04) == "0.0 mi walk · about 1 min")
    }
}
