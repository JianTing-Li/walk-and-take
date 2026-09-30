//
//  WalkEstimate.swift
//  WalkAndTakeKit
//

import Foundation

public enum WalkEstimate {
    /// The PRD's pace: 1 mile takes 15 minutes.
    public static let minutesPerMile = 15.0

    /// Whole minutes to walk a distance, at least 1 for any distance above zero.
    public static func minutes(forMiles miles: Double) -> Int {
        guard miles > 0 else { return 0 }
        return max(1, Int((miles * minutesPerMile).rounded()))
    }
}
