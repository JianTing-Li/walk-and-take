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

    /// What a track adds up to, before any accept/reject decision.
    private struct Analysis {
        var first: WalkSample
        var last: WalkSample
        /// Miles moved at walking speed.
        var walked: Double
        /// Miles moved too fast to be walking.
        var tooFast: Double
    }

    /// The usable fixes (accurate enough, in time order), summed into walked and too-fast miles.
    private static func analyze(_ samples: [WalkSample]) -> Analysis? {
        let fixes =
            samples
            .filter { $0.horizontalAccuracyMeters >= 0 && $0.horizontalAccuracyMeters <= maxAccuracyMeters }
            .sorted { $0.timestamp < $1.timestamp }
        guard let first = fixes.first, let last = fixes.last, fixes.count >= 2 else { return nil }

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
        return Analysis(first: first, last: last, walked: walked, tooFast: tooFast)
    }

    /// Miles to credit for a walk that began at `start`: capped at the detour and per-pickup limits.
    private static func cappedMiles(walked: Double, from start: Coordinate, to destination: Coordinate) -> Double {
        min(walked, start.distanceMiles(to: destination) * detourFactor, WalkRewardLadder.maxMilesPerPickup)
    }

    public static func verify(samples: [WalkSample], destination: Coordinate) -> WalkVerdict {
        if samples.contains(where: \.isSimulated) { return .rejected(.simulatedLocation) }
        guard let track = analyze(samples) else { return .rejected(.notEnoughData) }

        let total = track.walked + track.tooFast
        if total > 0, track.tooFast / total > maxFastShare { return .rejected(.tooFast) }
        if track.last.coordinate.distanceMiles(to: destination) > endRadiusMiles {
            return .rejected(.endedFarFromRestaurant)
        }

        let credited = cappedMiles(walked: track.walked, from: track.first.coordinate, to: destination)
        guard credited >= minMiles else { return .rejected(.notEnoughData) }
        return .credited(miles: (credited * 100).rounded() / 100)
    }

    /// Progress so far, for showing during the walk. Nil until there are two usable fixes.
    /// It doesn't judge the walk (simulated fixes, speed share, endpoint): that happens at pickup.
    public static func progress(samples: [WalkSample], destination: Coordinate) -> WalkProgress? {
        guard let track = analyze(samples) else { return nil }
        let startDistance = track.first.coordinate.distanceMiles(to: destination)
        let milesToGo = track.last.coordinate.distanceMiles(to: destination)
        let fraction = startDistance > 0.001 ? min(1, max(0, 1 - milesToGo / startDistance)) : 1
        let credited = cappedMiles(walked: track.walked, from: track.first.coordinate, to: destination)
        return WalkProgress(creditedMiles: (credited * 100).rounded() / 100, milesToGo: milesToGo, fraction: fraction)
    }
}
