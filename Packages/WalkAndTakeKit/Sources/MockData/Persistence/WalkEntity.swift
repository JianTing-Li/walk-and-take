//
//  WalkEntity.swift
//  WalkAndTakeKit
//

import Domain
import Foundation
import SwiftData

@Model
final class WalkEntity {
    #Unique<WalkEntity>([\.id], [\.reservationID])

    var id: UUID
    var reservationID: UUID
    var restaurantID: String
    var startedAt: Date
    var finishedAt: Date?
    var creditedMiles: Double
    var rejectionRaw: String?

    init(_ walk: Walk) {
        id = walk.id
        reservationID = walk.reservationID
        restaurantID = walk.restaurantID
        startedAt = walk.startedAt
        finishedAt = walk.finishedAt
        creditedMiles = walk.creditedMiles
        rejectionRaw = walk.rejection?.rawValue
    }

    func apply(_ walk: Walk) {
        finishedAt = walk.finishedAt
        creditedMiles = walk.creditedMiles
        rejectionRaw = walk.rejection?.rawValue
    }

    var domain: Walk {
        Walk(
            id: id,
            reservationID: reservationID,
            restaurantID: restaurantID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            creditedMiles: creditedMiles,
            rejection: rejectionRaw.flatMap(WalkRejection.init(rawValue:))
        )
    }
}
