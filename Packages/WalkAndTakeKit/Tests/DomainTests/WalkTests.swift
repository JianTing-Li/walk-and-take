//
//  WalkTests.swift
//  DomainTests
//

import Foundation
import Testing

@testable import Domain

@Suite("WalkRewardLadder")
struct WalkRewardLadderTests {
    @Test func milestonesAre1_5_15_then_every10() {
        let marks = (0..<7).map(WalkRewardLadder.milestone(at:))
        #expect(marks == [1, 5, 15, 25, 35, 45, 55])
    }

    @Test func milestonesReachedAtTheBoundaries() {
        #expect(WalkRewardLadder.milestonesReached(totalMiles: 0) == 0)
        #expect(WalkRewardLadder.milestonesReached(totalMiles: 0.99) == 0)
        #expect(WalkRewardLadder.milestonesReached(totalMiles: 1) == 1)
        #expect(WalkRewardLadder.milestonesReached(totalMiles: 4.99) == 1)
        #expect(WalkRewardLadder.milestonesReached(totalMiles: 5) == 2)
        #expect(WalkRewardLadder.milestonesReached(totalMiles: 15) == 3)
        #expect(WalkRewardLadder.milestonesReached(totalMiles: 24.9) == 3)
        #expect(WalkRewardLadder.milestonesReached(totalMiles: 25) == 4)
        #expect(WalkRewardLadder.milestonesReached(totalMiles: 35) == 5)
    }

    @Test func nextMilestoneAndMilesToGo() {
        #expect(WalkRewardLadder.nextMilestone(after: 0) == 1)
        #expect(WalkRewardLadder.nextMilestone(after: 1) == 5)
        #expect(WalkRewardLadder.nextMilestone(after: 7) == 15)
        #expect(WalkRewardLadder.nextMilestone(after: 15) == 25)
        #expect(abs(WalkRewardLadder.milesToNext(totalMiles: 3.5) - 1.5) < 1e-9)
    }

    @Test func crossingSeveralMilestonesReturnsEachInOrder() {
        #expect(WalkRewardLadder.milestonesCrossed(from: 0.5, to: 0.9).isEmpty)
        #expect(WalkRewardLadder.milestonesCrossed(from: 0.5, to: 1.5) == [1])
        #expect(WalkRewardLadder.milestonesCrossed(from: 4.5, to: 15.5) == [5, 15])
    }

    @Test func progressFractionRunsBetweenMilestones() {
        #expect(WalkRewardLadder.progressFraction(totalMiles: 0) == 0)
        #expect(abs(WalkRewardLadder.progressFraction(totalMiles: 0.5) - 0.5) < 1e-9)
        #expect(abs(WalkRewardLadder.progressFraction(totalMiles: 3) - 0.5) < 1e-9)
        #expect(abs(WalkRewardLadder.progressFraction(totalMiles: 20) - 0.5) < 1e-9)
    }

    @Test func expectedMilesAreCappedPerPickup() {
        #expect(WalkRewardLadder.expectedMiles(forDistance: 0.4) == 0.4)
        #expect(WalkRewardLadder.expectedMiles(forDistance: 2) == 2)
        #expect(WalkRewardLadder.expectedMiles(forDistance: 5) == 2)
        #expect(WalkRewardLadder.expectedMiles(forDistance: -1) == 0)
    }
}

@Suite("WalkEstimate and Money discount")
struct WalkEstimateTests {
    @Test func fifteenMinutesPerMile() {
        #expect(WalkEstimate.minutes(forMiles: 1) == 15)
        #expect(WalkEstimate.minutes(forMiles: 0.5) == 8)
        #expect(WalkEstimate.minutes(forMiles: 2) == 30)
        #expect(WalkEstimate.minutes(forMiles: 0.01) == 1)
        #expect(WalkEstimate.minutes(forMiles: 0) == 0)
    }

    @Test func halfOffRoundsTheDiscountDown() {
        #expect(Money(cents: 600).discount(percent: 50) == Money(cents: 300))
        #expect(Money(cents: 599).discount(percent: 50) == Money(cents: 299))
        #expect(Money.zero.discount(percent: 50) == .zero)
    }
}

@Suite("WalkPolicy")
struct WalkPolicyTests {
    // Window 7:30-10:00, so Start Walk opens at 6:30.
    @Test func startOpensOneHourBeforeTheWindow() {
        let r = Fixtures.reservation()
        #expect(WalkPolicy.startOpensAt(for: r) == Fixtures.date(6, 30))
        #expect(!WalkPolicy.canStart(r, at: Fixtures.date(6, 29)))
        #expect(WalkPolicy.canStart(r, at: Fixtures.date(6, 30)))
        #expect(WalkPolicy.canStart(r, at: Fixtures.date(8, 0)))
        #expect(WalkPolicy.canStart(r, at: Fixtures.date(9, 59)))
    }

    @Test func startClosesWhenTheWindowEnds() {
        let r = Fixtures.reservation()
        #expect(!WalkPolicy.canStart(r, at: Fixtures.date(10, 0)))
    }

    @Test func cancelledOrCollectedReservationsCannotStart() {
        let cancelled = Fixtures.reservation(cancelledAt: Fixtures.date(6, 0))
        let collected = Fixtures.reservation(collectedAt: Fixtures.date(8, 0))
        #expect(!WalkPolicy.canStart(cancelled, at: Fixtures.date(7, 0)))
        #expect(!WalkPolicy.canStart(collected, at: Fixtures.date(8, 30)))
    }
}

@Suite("WalkVerifier")
struct WalkVerifierTests {
    let destination = Fixtures.licCenter
    let start = Fixtures.date(7, 0)
    /// Miles per degree of latitude, for building tracks due south of the destination.
    let milesPerDegree = 3958.8 * .pi / 180

    func point(milesSouth: Double) -> Coordinate {
        Coordinate(latitude: destination.latitude - milesSouth / milesPerDegree, longitude: destination.longitude)
    }

    /// A straight walk that starts `from` miles south and ends at the destination, at `mph`.
    func track(from miles: Double, mph: Double = 3, steps: Int = 10, accuracy: Double = 5, simulated: Bool = false)
        -> [WalkSample]
    {
        let seconds = miles / mph * 3600 / Double(steps)
        return (0...steps).map { i in
            WalkSample(
                coordinate: point(milesSouth: miles * (1 - Double(i) / Double(steps))),
                timestamp: start.addingTimeInterval(seconds * Double(i)),
                horizontalAccuracyMeters: accuracy,
                isSimulated: simulated
            )
        }
    }

    @Test func aSteadyWalkEarnsItsDistance() {
        let verdict = WalkVerifier.verify(samples: track(from: 0.8), destination: destination)
        guard case .credited(let miles) = verdict else {
            Issue.record("expected credit, got \(verdict)")
            return
        }
        #expect(abs(miles - 0.8) < 0.02)
    }

    @Test func creditStopsAtTwoMilesPerPickup() {
        let verdict = WalkVerifier.verify(samples: track(from: 3.0), destination: destination)
        #expect(verdict == .credited(miles: 2.0))
    }

    @Test func drivingIsRejectedAsTooFast() {
        let verdict = WalkVerifier.verify(samples: track(from: 1.5, mph: 25), destination: destination)
        #expect(verdict == .rejected(.tooFast))
    }

    @Test func aBriefSpeedSpikeIsDroppedNotRejected() {
        var samples = track(from: 1.0, steps: 20)
        // Squeeze one 0.05-mile segment into 10 s (18 mph), well under the rejection share.
        let i = 10
        let shift = samples[i].timestamp.timeIntervalSince(samples[i - 1].timestamp) - 10
        for j in i..<samples.count { samples[j].timestamp = samples[j].timestamp.addingTimeInterval(-shift) }
        let verdict = WalkVerifier.verify(samples: samples, destination: destination)
        guard case .credited(let miles) = verdict else {
            Issue.record("expected credit, got \(verdict)")
            return
        }
        #expect(miles < 1.0)
        #expect(miles > 0.9)
    }

    @Test func simulatedFixesAreRejected() {
        let verdict = WalkVerifier.verify(samples: track(from: 0.5, simulated: true), destination: destination)
        #expect(verdict == .rejected(.simulatedLocation))
    }

    @Test func poorAccuracyFixesAreIgnored() {
        let verdict = WalkVerifier.verify(samples: track(from: 0.5, accuracy: 200), destination: destination)
        #expect(verdict == .rejected(.notEnoughData))
    }

    @Test func tooFewFixesIsNotEnoughData() {
        #expect(WalkVerifier.verify(samples: [], destination: destination) == .rejected(.notEnoughData))
        let one = Array(track(from: 0.5).prefix(1))
        #expect(WalkVerifier.verify(samples: one, destination: destination) == .rejected(.notEnoughData))
    }

    @Test func endingFarFromTheRestaurantIsRejected() {
        var samples = track(from: 0.8)
        samples.removeLast(3)  // stops about 0.24 mi short
        let verdict = WalkVerifier.verify(samples: samples, destination: destination)
        #expect(verdict == .rejected(.endedFarFromRestaurant))
    }

    @Test func walkingInCirclesIsCappedAtTheDetourFactor() {
        // Start 0.2 mi away but wander 0.8 mi in total: out 0.3 mi south and back, twice.
        let legs: [Double] = [0.2, 0.5, 0.2, 0.5, 0.2, 0.5, 0.0]
        var samples: [WalkSample] = []
        var t = start
        var previous = legs[0]
        samples.append(WalkSample(coordinate: point(milesSouth: previous), timestamp: t))
        for leg in legs.dropFirst() {
            t = t.addingTimeInterval(abs(leg - previous) / 3 * 3600)
            samples.append(WalkSample(coordinate: point(milesSouth: leg), timestamp: t))
            previous = leg
        }
        let verdict = WalkVerifier.verify(samples: samples, destination: destination)
        #expect(verdict == .credited(miles: 0.25))  // 0.2 mi straight line x 1.25
    }

    @Test func unsortedFixesAreOrderedByTime() {
        let verdict = WalkVerifier.verify(samples: track(from: 0.6).reversed(), destination: destination)
        guard case .credited(let miles) = verdict else {
            Issue.record("expected credit, got \(verdict)")
            return
        }
        #expect(abs(miles - 0.6) < 0.02)
    }

    @Test func rejectionsHaveUserFacingMessages() {
        for reason in [
            WalkRejection.simulatedLocation, .notEnoughData, .tooFast, .endedFarFromRestaurant, .repeatPickupToday,
        ] {
            #expect(!reason.message.isEmpty)
        }
        #expect(WalkVerdict.rejected(.tooFast).creditedMiles == 0)
        #expect(WalkVerdict.credited(miles: 0.5).creditedMiles == 0.5)
    }
}

@Suite("WalkVerifier progress")
struct WalkProgressTests {
    let destination = Fixtures.licCenter
    let start = Fixtures.date(7, 0)
    let milesPerDegree = 3958.8 * .pi / 180

    func point(milesSouth: Double) -> Coordinate {
        Coordinate(latitude: destination.latitude - milesSouth / milesPerDegree, longitude: destination.longitude)
    }

    /// A walk at 3 mph from 0.8 mi south, with only the first `steps` of 8 recorded.
    func partialWalk(steps: Int, mph: Double = 3, accuracy: Double = 5) -> [WalkSample] {
        let total = 8
        let seconds = 0.8 / mph * 3600 / Double(total)
        return (0...steps).map { i in
            WalkSample(
                coordinate: point(milesSouth: 0.8 * (1 - Double(i) / Double(total))),
                timestamp: start.addingTimeInterval(seconds * Double(i)), horizontalAccuracyMeters: accuracy)
        }
    }

    @Test func noProgressUntilThereAreTwoUsableFixes() {
        #expect(WalkVerifier.progress(samples: [], destination: destination) == nil)
        #expect(WalkVerifier.progress(samples: partialWalk(steps: 0), destination: destination) == nil)
        #expect(WalkVerifier.progress(samples: partialWalk(steps: 4, accuracy: 200), destination: destination) == nil)
    }

    @Test func halfwayThereIsHalfDone() throws {
        let progress = try #require(WalkVerifier.progress(samples: partialWalk(steps: 4), destination: destination))
        #expect(abs(progress.creditedMiles - 0.4) < 0.02)
        #expect(abs(progress.milesToGo - 0.4) < 0.02)
        #expect(abs(progress.fraction - 0.5) < 0.02)
    }

    @Test func arrivingReachesOne() throws {
        let progress = try #require(WalkVerifier.progress(samples: partialWalk(steps: 8), destination: destination))
        #expect(progress.fraction > 0.99)
        #expect(progress.milesToGo < 0.01)
    }

    @Test func fastSegmentsDoNotCountTowardCredit() throws {
        // Driving pace: the distance moves along the route but earns nothing.
        let progress = try #require(
            WalkVerifier.progress(samples: partialWalk(steps: 4, mph: 25), destination: destination))
        #expect(progress.creditedMiles == 0)
        #expect(progress.fraction > 0.4)
    }

    @Test func creditSoFarMatchesWhatVerifyWouldCredit() throws {
        let samples = partialWalk(steps: 8)
        let progress = try #require(WalkVerifier.progress(samples: samples, destination: destination))
        #expect(
            WalkVerifier.verify(samples: samples, destination: destination) == .credited(miles: progress.creditedMiles))
    }
}

@Suite("WalkCatchphrases and WalkEarnings")
struct WalkEarningsTests {
    func walk(_ miles: Double, finished hour: Int?, day: Int = 24) -> Walk {
        Walk(
            reservationID: UUID(), restaurantID: "r", startedAt: Fixtures.date(6, day: day),
            finishedAt: hour.map { Fixtures.date($0, day: day) }, creditedMiles: miles)
    }

    @Test func tenDistinctLinesStartingWithTheAppNameOne() {
        #expect(WalkCatchphrases.all.count == 10)
        #expect(Set(WalkCatchphrases.all).count == 10)
        #expect(WalkCatchphrases.phrase(forWalkNumber: 1) == "Walk&Take: every mile gets you something.")
    }

    @Test func linesCycleInOrderAndWrap() {
        let firstTwenty = (1...20).map(WalkCatchphrases.phrase(forWalkNumber:))
        #expect(Array(firstTwenty[0..<10]) == WalkCatchphrases.all)
        #expect(Array(firstTwenty[10..<20]) == WalkCatchphrases.all)
        #expect(WalkCatchphrases.phrase(forWalkNumber: 2) != WalkCatchphrases.phrase(forWalkNumber: 1))
        #expect(WalkCatchphrases.phrase(forWalkNumber: 0) == WalkCatchphrases.phrase(forWalkNumber: 1))
    }

    @Test func aFirstWalkAddsToZero() throws {
        let first = walk(0.5, finished: 8)
        let earnings = try #require(WalkEarnings.of(first, in: [first]))
        #expect(earnings.milesEarned == 0.5)
        #expect(earnings.totalBefore == 0)
        #expect(earnings.totalAfter == 0.5)
        #expect(earnings.walkNumber == 1)
        #expect(earnings.unlockedMilestones.isEmpty)
        #expect(abs(earnings.milesToNextReward - 0.5) < 1e-9)
        #expect(earnings.nextMilestone == 1)
    }

    @Test func laterWalksBuildOnEarlierOnesByFinishTime() throws {
        let a = walk(0.6, finished: 8)
        let b = walk(0.7, finished: 9)
        let c = walk(1.0, finished: 10)
        let shuffled = [c, a, b]
        let second = try #require(WalkEarnings.of(b, in: shuffled))
        #expect(second.walkNumber == 2)
        #expect(abs(second.totalBefore - 0.6) < 1e-9)
        #expect(abs(second.totalAfter - 1.3) < 1e-9)
        #expect(second.unlockedMilestones == [1])
        #expect(try #require(WalkEarnings.of(c, in: shuffled)).walkNumber == 3)
    }

    @Test func aWalkThatLandsOnAMilestoneUnlocksIt() throws {
        let a = walk(1.5, finished: 8)
        let b = walk(2.0, finished: 9)
        let c = walk(1.5, finished: 10)  // 1.5 + 2.0 + 1.5 = 5.0
        let earnings = try #require(WalkEarnings.of(c, in: [a, b, c]))
        #expect(earnings.unlockedMilestones == [5])
    }

    @Test func rejectedAndUnfinishedWalksHaveNoEarningsAndDontCount() throws {
        let rejected = walk(0, finished: 8)
        let unfinished = walk(0.4, finished: nil)
        let real = walk(0.5, finished: 9)
        #expect(WalkEarnings.of(rejected, in: [rejected]) == nil)
        #expect(WalkEarnings.of(unfinished, in: [unfinished]) == nil)
        let earnings = try #require(WalkEarnings.of(real, in: [rejected, unfinished, real]))
        #expect(earnings.walkNumber == 1)
        #expect(earnings.totalBefore == 0)
    }

    @Test func aWalkMissingFromTheHistoryHasNoEarnings() {
        #expect(WalkEarnings.of(walk(0.5, finished: 8), in: []) == nil)
    }
}
