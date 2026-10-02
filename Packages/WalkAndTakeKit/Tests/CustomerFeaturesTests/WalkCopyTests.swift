//
//  WalkCopyTests.swift
//  CustomerFeaturesTests
//

import Testing

@testable import CustomerFeatures

@Suite("Walk copy")
struct WalkCopyTests {
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
