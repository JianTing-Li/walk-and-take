//
//  MilestoneProgressBarTests.swift
//  DesignSystemTests
//

import Testing

@testable import DesignSystem

@Suite("Milestone progress bar ticks")
struct MilestoneProgressBarTests {
    func close(_ a: [Double], _ b: [Double]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    @Test func aTickPerMileBetweenMilestones() {
        #expect(close(MilestoneProgressBar.ticks(from: 1, to: 5, every: 1), [0.25, 0.5, 0.75]))
        #expect(MilestoneProgressBar.ticks(from: 15, to: 25, every: 1).count == 9)
    }

    @Test func noTickOnTheEnds() {
        // 0.3 to 0.6 every 0.1: 0.4 and 0.5 only, despite floating-point drift.
        #expect(close(MilestoneProgressBar.ticks(from: 0.3, to: 0.6, every: 0.1), [1.0 / 3, 2.0 / 3]))
    }

    @Test func shortWalksHaveFewTicks() {
        #expect(MilestoneProgressBar.ticks(from: 0, to: 0.7, every: 0.1).count == 6)
        #expect(MilestoneProgressBar.ticks(from: 0, to: 0.05, every: 0.1).isEmpty)
    }

    @Test func tooManyTicksWidenTheStep() {
        #expect(MilestoneProgressBar.ticks(from: 0, to: 10, every: 0.1, limit: 20).count <= 20)
    }

    @Test func emptyOrBackwardRangesHaveNoTicks() {
        #expect(MilestoneProgressBar.ticks(from: 5, to: 5, every: 1).isEmpty)
        #expect(MilestoneProgressBar.ticks(from: 5, to: 1, every: 1).isEmpty)
    }
}
