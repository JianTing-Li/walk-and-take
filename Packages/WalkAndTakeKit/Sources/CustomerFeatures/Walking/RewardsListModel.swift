//
//  RewardsListModel.swift
//  WalkAndTakeKit
//
//  Every walking reward the customer has earned: the ones ready to use, then the ones already used
//  with where and when they were spent.
//

import DesignSystem
import Domain
import Foundation
import Observation
import Platform

@Observable
@MainActor
public final class RewardsListModel {
    public enum State: Equatable {
        case loading, loaded
        case failed(String)
    }

    public struct Row: Identifiable, Hashable, Sendable {
        public let id: UUID
        /// "50% off one bag"
        public let title: String
        /// "Earned at 5 mi · Wed Sep 30"
        public let earnedText: String
        /// "Used Tue Sep 29 at Crane & Kettle · saved $2.74". Nil while the reward is still available.
        public let usedText: String?

        public var isAvailable: Bool { usedText == nil }
    }

    public private(set) var state: State = .loading
    public private(set) var ready: [Row] = []
    public private(set) var used: [Row] = []

    private let dependencies: CustomerDependencies

    public init(dependencies: CustomerDependencies) {
        self.dependencies = dependencies
    }

    public var isEmpty: Bool { ready.isEmpty && used.isEmpty }

    /// "1 ready to use · 2 used"
    public var summaryText: String { "\(ready.count) ready to use · \(used.count) used" }

    /// What to say before the first reward: how far away it is.
    public var emptyMessage: String {
        "Walk \(WalkCopy.milestone(WalkRewardLadder.milestone(at: 0))) mi in total to earn your first "
            + "\(WalkRewardLadder.discountPercent)% off. Every pickup you walk counts."
    }

    // MARK: - Lifecycle

    public func run() async {
        await load()
        for await _ in dependencies.walkRewards.changes() { await load() }
    }

    public func load() async {
        do {
            let rewards = try await dependencies.walkRewards.rewards()
            var used: [(reward: Reward, row: Row)] = []
            var ready: [Row] = []
            for reward in rewards {
                if reward.isAvailable {
                    ready.append(await row(for: reward))
                } else {
                    used.append((reward, await row(for: reward)))
                }
            }
            // Oldest first is the order they get spent in; used ones show the latest first.
            self.ready = ready
            self.used = used.sorted { ($0.reward.redeemedAt ?? .distantPast) > ($1.reward.redeemedAt ?? .distantPast) }
                .map(\.row)
            state = .loaded
        } catch {
            if state == .loading { state = .failed("Couldn't load your rewards. Please try again.") }
        }
    }

    // MARK: - Rows

    private func row(for reward: Reward) async -> Row {
        let calendar = NYCalendar.calendar
        let earned =
            "Earned at \(WalkCopy.milestone(reward.milestoneMiles)) mi · "
            + TimeText.shortDate(reward.earnedAt, calendar: calendar)
        var usedText: String?
        if let redeemedAt = reward.redeemedAt {
            var text = "Used \(TimeText.shortDate(redeemedAt, calendar: calendar))"
            if let id = reward.redeemedReservationID,
                let reservation = try? await dependencies.reservations.reservation(id: id)
            {
                text += " at \(reservation.snapshot.restaurantName)"
                if reservation.discount > .zero { text += " · saved \(reservation.discount.usd)" }
            }
            usedText = text
        }
        return Row(
            id: reward.id, title: "\(WalkRewardLadder.discountPercent)% off one bag", earnedText: earned,
            usedText: usedText)
    }
}
