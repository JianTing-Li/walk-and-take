//
//  WalkSampleStoring.swift
//  WalkAndTakeKit
//

import Foundation

/// Keeps the GPS fixes of a walk on disk, so an app that is killed mid-walk doesn't lose the part already walked.
/// The tracker writes fixes in small batches; `savedSamples` hands them back, oldest first, when it resumes.
public protocol WalkSampleStoring: Sendable {
    /// Adds fixes to what is saved for a reservation's walk.
    func appendSamples(_ samples: [WalkSample], reservationID: UUID) async throws
    /// Everything saved for a reservation's walk, oldest first.
    func savedSamples(reservationID: UUID) async throws -> [WalkSample]
    /// Forgets a walk's fixes once it is credited or abandoned.
    func discardSamples(reservationID: UUID) async throws
}
