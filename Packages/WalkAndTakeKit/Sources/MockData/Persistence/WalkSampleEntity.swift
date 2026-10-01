//
//  WalkSampleEntity.swift
//  WalkAndTakeKit
//

import Domain
import Foundation
import SwiftData

/// One saved GPS fix of a walk in progress. Rows are removed once the walk is credited or abandoned.
@Model
final class WalkSampleEntity {
    var reservationID: UUID
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    var horizontalAccuracyMeters: Double
    var isSimulated: Bool

    init(_ sample: WalkSample, reservationID: UUID) {
        self.reservationID = reservationID
        latitude = sample.coordinate.latitude
        longitude = sample.coordinate.longitude
        timestamp = sample.timestamp
        horizontalAccuracyMeters = sample.horizontalAccuracyMeters
        isSimulated = sample.isSimulated
    }

    var domain: WalkSample {
        WalkSample(
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            timestamp: timestamp,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            isSimulated: isSimulated)
    }
}
