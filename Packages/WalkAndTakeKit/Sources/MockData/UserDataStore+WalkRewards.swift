//
//  UserDataStore+WalkRewards.swift
//  WalkAndTakeKit
//
//  Walks, lifetime miles and banked rewards.
//

import Domain
import Foundation
import SwiftData

extension UserDataStore {
    public func walks() throws -> [Walk] {
        try modelContext.fetch(FetchDescriptor<WalkEntity>(sortBy: [SortDescriptor(\.startedAt)])).map(\.domain)
    }

    public func rewards() throws -> [Reward] {
        try modelContext.fetch(FetchDescriptor<RewardEntity>(sortBy: [SortDescriptor(\.earnedAt)])).map(\.domain)
    }

    public func totalMiles() throws -> Double {
        try modelContext.fetch(FetchDescriptor<WalkEntity>()).reduce(0) { $0 + $1.creditedMiles }
    }

    public func walk(reservationID: UUID) throws -> Walk? {
        try walkEntity(reservationID)?.domain
    }

    public func startWalk(reservationID: UUID, restaurantID: String, at now: Date) throws -> Walk {
        if let existing = try walkEntity(reservationID) { return existing.domain }
        let walk = Walk(reservationID: reservationID, restaurantID: restaurantID, startedAt: now)
        modelContext.insert(WalkEntity(walk))
        try save(.walkRewardsChanged)
        return walk
    }

    public func finishWalk(
        reservationID: UUID, verdict: WalkVerdict, at now: Date, calendar: Calendar
    ) throws -> WalkCompletion {
        guard let entity = try walkEntity(reservationID) else { throw WalkRewardsError.walkNotFound }
        let before = try totalMiles()
        if entity.finishedAt != nil {
            return WalkCompletion(walk: entity.domain, newRewards: [], totalMiles: before)
        }

        var verdict = verdict
        if case .credited = verdict,
            try hasCreditedPickup(restaurantID: entity.restaurantID, on: now, calendar: calendar)
        {
            verdict = .rejected(.repeatPickupToday)
        }

        var walk = entity.domain
        walk.finishedAt = now
        switch verdict {
        case .credited(let miles):
            walk.creditedMiles = miles
            walk.rejection = nil
        case .rejected(let reason):
            walk.creditedMiles = 0
            walk.rejection = reason
        }
        entity.apply(walk)

        let after = before + walk.creditedMiles
        let rewards = WalkRewardLadder.milestonesCrossed(from: before, to: after)
            .map { Reward(milestoneMiles: $0, earnedAt: now) }
        rewards.forEach { modelContext.insert(RewardEntity($0)) }
        try save(.walkRewardsChanged)
        return WalkCompletion(walk: walk, newRewards: rewards, totalMiles: after)
    }

    public func redeemReward(id: UUID, reservationID: UUID, at now: Date) throws -> Reward {
        guard
            let entity = try modelContext.fetch(FetchDescriptor<RewardEntity>(predicate: #Predicate { $0.id == id }))
                .first
        else { throw WalkRewardsError.rewardNotFound }
        guard entity.redeemedAt == nil else { throw WalkRewardsError.rewardAlreadyRedeemed }
        entity.redeemedAt = now
        entity.redeemedReservationID = reservationID
        try save(.walkRewardsChanged)
        return entity.domain
    }

    public func releaseReward(reservationID: UUID) throws {
        let used = try modelContext.fetch(
            FetchDescriptor<RewardEntity>(predicate: #Predicate { $0.redeemedReservationID == reservationID }))
        guard !used.isEmpty else { return }
        for entity in used {
            entity.redeemedAt = nil
            entity.redeemedReservationID = nil
        }
        try save(.walkRewardsChanged)
    }

    // MARK: - Developer mode

    /// Banks a reward without changing miles (Developer mode's "Grant a reward").
    public func bankReward(milestoneMiles: Double, at now: Date) throws -> Reward {
        let reward = Reward(milestoneMiles: milestoneMiles, earnedAt: now)
        modelContext.insert(RewardEntity(reward))
        try save(.walkRewardsChanged)
        return reward
    }

    /// Clears finished walks and every reward, back to zero miles. Walks still in progress stay,
    /// so open orders keep recording.
    public func clearWalksAndRewards() throws {
        for walk in try modelContext.fetch(FetchDescriptor<WalkEntity>()) where walk.finishedAt != nil {
            modelContext.delete(walk)
        }
        try modelContext.delete(model: RewardEntity.self)
        try save(.walkRewardsChanged)
    }

    // MARK: - Helpers

    private func walkEntity(_ reservationID: UUID) throws -> WalkEntity? {
        try modelContext.fetch(
            FetchDescriptor<WalkEntity>(predicate: #Predicate { $0.reservationID == reservationID })
        )
        .first
    }

    /// True if a walk from this restaurant already earned miles on the same calendar day.
    private func hasCreditedPickup(restaurantID: String, on day: Date, calendar: Calendar) throws -> Bool {
        try modelContext.fetch(
            FetchDescriptor<WalkEntity>(
                predicate: #Predicate { $0.restaurantID == restaurantID && $0.creditedMiles > 0 })
        )
        .contains { $0.finishedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    }
}

// MARK: - Saved GPS fixes

extension UserDataStore {
    /// Fixes saved here change nothing on screen, so this saves without announcing a change.
    public func appendSamples(_ samples: [WalkSample], reservationID: UUID) throws {
        guard !samples.isEmpty else { return }
        for sample in samples { modelContext.insert(WalkSampleEntity(sample, reservationID: reservationID)) }
        try saveQuietly()
    }

    public func savedSamples(reservationID: UUID) throws -> [WalkSample] {
        try modelContext.fetch(
            FetchDescriptor<WalkSampleEntity>(
                predicate: #Predicate { $0.reservationID == reservationID },
                sortBy: [SortDescriptor(\.timestamp)])
        ).map(\.domain)
    }

    public func discardSamples(reservationID: UUID) throws {
        let rows = try modelContext.fetch(
            FetchDescriptor<WalkSampleEntity>(predicate: #Predicate { $0.reservationID == reservationID }))
        guard !rows.isEmpty else { return }
        rows.forEach(modelContext.delete)
        try saveQuietly()
    }

    private func saveQuietly() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
