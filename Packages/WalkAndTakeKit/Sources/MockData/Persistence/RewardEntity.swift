//
//  RewardEntity.swift
//  WalkAndTakeKit
//

import Domain
import Foundation
import SwiftData

@Model
final class RewardEntity {
    #Unique<RewardEntity>([\.id])

    var id: UUID
    var milestoneMiles: Double
    var earnedAt: Date
    var redeemedAt: Date?
    var redeemedReservationID: UUID?

    init(_ reward: Reward) {
        id = reward.id
        milestoneMiles = reward.milestoneMiles
        earnedAt = reward.earnedAt
        redeemedAt = reward.redeemedAt
        redeemedReservationID = reward.redeemedReservationID
    }

    var domain: Reward {
        Reward(
            id: id,
            milestoneMiles: milestoneMiles,
            earnedAt: earnedAt,
            redeemedAt: redeemedAt,
            redeemedReservationID: redeemedReservationID
        )
    }
}
