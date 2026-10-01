//
//  WalkHistoryModel.swift
//  WalkAndTakeKit
//
//  Every finished walk, newest first: where it went, when, and the miles it earned.
//

import Domain
import Foundation
import Observation
import Platform

@Observable
@MainActor
public final class WalkHistoryModel {
    public enum State: Equatable {
        case loading, loaded
        case failed(String)
    }

    /// One finished walk.
    public struct Row: Identifiable, Hashable, Sendable {
        public let id: UUID
        /// The restaurant, e.g. "Crane & Kettle".
        public let title: String
        /// "Wed Sep 30 · 8:00 AM"
        public let dateText: String
        /// "+0.50 mi", or "0 mi" when nothing counted.
        public let milesText: String
        /// The running total after this walk, or why nothing counted.
        public let detail: String
        public let earnedMiles: Bool
    }

    public private(set) var state: State = .loading
    public private(set) var rows: [Row] = []
    /// "3 walked pickups · 1.70 mi counted"
    public private(set) var summaryText = ""

    private let dependencies: CustomerDependencies

    public init(dependencies: CustomerDependencies) {
        self.dependencies = dependencies
    }

    public var isEmpty: Bool { rows.isEmpty }

    // MARK: - Lifecycle

    public func run() async {
        await load()
        for await _ in dependencies.walkRewards.changes() { await load() }
    }

    public func load() async {
        do {
            let walks = try await dependencies.walkRewards.walks()
            let names = Dictionary(
                uniqueKeysWithValues: try await dependencies.offers.restaurants().map { ($0.id, $0.name) })
            apply(walks: walks, names: names)
            state = .loaded
        } catch {
            if state == .loading { state = .failed("Couldn't load your walks. Please try again.") }
        }
    }

    private func apply(walks: [Walk], names: [String: String]) {
        let calendar = NYCalendar.calendar
        let finished = walks.filter { $0.finishedAt != nil }
            .sorted {
                ($0.finishedAt ?? .distantPast, $0.id.uuidString) > ($1.finishedAt ?? .distantPast, $1.id.uuidString)
            }

        rows = finished.map { walk in
            let finishedAt = walk.finishedAt ?? walk.startedAt
            let earnings = WalkEarnings.of(walk, in: walks)
            return Row(
                id: walk.id,
                title: walk.isDemo ? "Demo walk" : names[walk.restaurantID] ?? "Walk & Take pickup",
                dateText:
                    "\(TimeText.shortDate(finishedAt, calendar: calendar)) · \(TimeText.time(finishedAt, calendar: calendar))",
                milesText: walk.creditedMiles > 0 ? "+\(WalkCopy.miles(walk.creditedMiles)) mi" : "0 mi",
                detail: earnings.map { "\(WalkCopy.miles($0.totalAfter)) mi walked in total" }
                    ?? walk.rejection?.message ?? "No miles counted.",
                earnedMiles: walk.creditedMiles > 0)
        }

        let counted = finished.filter { $0.creditedMiles > 0 }
        let total = counted.reduce(0) { $0 + $1.creditedMiles }
        summaryText =
            "\(finished.count) walked \(finished.count == 1 ? "pickup" : "pickups") · "
            + "\(WalkCopy.miles(total)) mi counted"
    }
}
