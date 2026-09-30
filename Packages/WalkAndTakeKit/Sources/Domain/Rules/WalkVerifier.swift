//
//  WalkVerifier.swift
//  WalkAndTakeKit
//
//  Checks a recorded GPS track and decides how many miles to credit.
//  Uses only GPS signals: speed gate, accuracy, simulated fixes, and endpoint checks.
//

import Foundation

public enum WalkVerifier {
    /// Segments faster than this are not walking.
    public static let maxWalkingMph = 5.0
    /// If more than this share of distance was too fast, the whole walk is rejected.
    public static let maxFastShare = 0.2
    public static let maxAccuracyMeters = 50.0
    /// The walk must finish this close to the restaurant.
    public static let endRadiusMiles = 100.0 / 1609.344
    /// Credit is capped at this multiple of the straight-line distance.
    public static let detourFactor = 1.25
    /// Below this, a walk is too short to count at all.
    public static let minMiles = 0.01

    public static func verify(samples: [WalkSample], destination: Coordinate) -> WalkVerdict {
        if samples.contains(where: \.isSimulated) { return .rejected(.simulatedLocation) }

        let fixes =
            samples
            .filter { $0.horizontalAccuracyMeters >= 0 && $0.horizontalAccuracyMeters <= maxAccuracyMeters }
            .sorted { $0.timestamp < $1.timestamp }
        guard fixes.count >= 2, let first = fixes.first, let last = fixes.last else {
            return .rejected(.notEnoughData)
        }

        var walked = 0.0
        var tooFast = 0.0
        for (a, b) in zip(fixes, fixes.dropFirst()) {
            let miles = a.coordinate.distanceMiles(to: b.coordinate)
            let hours = b.timestamp.timeIntervalSince(a.timestamp) / 3600
            guard hours > 0 else {
                if miles > 0 { tooFast += miles }
                continue
            }
            if miles / hours > maxWalkingMph {
                tooFast += miles
            } else {
                walked += miles
            }
        }

        let total = walked + tooFast
        if total > 0, tooFast / total > maxFastShare { return .rejected(.tooFast) }
        if last.coordinate.distanceMiles(to: destination) > endRadiusMiles {
            return .rejected(.endedFarFromRestaurant)
        }

        let straight = first.coordinate.distanceMiles(to: destination)
        let credited = min(walked, straight * detourFactor, WalkRewardLadder.maxMilesPerPickup)
        guard credited >= minMiles else { return .rejected(.notEnoughData) }
        return .credited(miles: (credited * 100).rounded() / 100)
    }
}
