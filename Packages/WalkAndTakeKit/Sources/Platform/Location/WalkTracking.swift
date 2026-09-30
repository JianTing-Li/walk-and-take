//
//  WalkTracking.swift
//  WalkAndTakeKit
//
//  Records the GPS fixes of a pickup walk. Verifying them is Domain's `WalkVerifier`.
//

import Domain
import Foundation

/// What a walk location source reports.
public enum WalkLocationEvent: Hashable, Sendable {
    case sample(WalkSample)
    /// The user refused, or location is restricted.
    case denied
    /// Location can't produce fixes right now.
    case unavailable
}

/// Produces walk fixes; `CoreLocationWalkSource` in the app, a fake in tests.
public protocol WalkLocationSource: Sendable {
    func events() -> AsyncStream<WalkLocationEvent>
}

public enum WalkTrackingStatus: Hashable, Sendable {
    /// Nothing is being recorded for this reservation.
    case idle
    case tracking
    /// Recording, but location is denied or unavailable, so no miles will count.
    case locationOff
}

/// Records walks per reservation. Lives for the whole app, so a walk keeps recording
/// after the customer leaves the pickup screen.
public protocol WalkTracking: Sendable {
    /// Starts recording for a reservation. Does nothing if it is already recording.
    func begin(reservationID: UUID, destination: Coordinate) async
    func status(reservationID: UUID) async -> WalkTrackingStatus
    /// Everything recorded so far, without stopping.
    func samples(reservationID: UUID) async -> [WalkSample]
    /// Stops recording and returns everything recorded.
    func finish(reservationID: UUID) async -> [WalkSample]
}

/// Records fixes from a `WalkLocationSource`, one session per reservation.
public actor LiveWalkTracker: WalkTracking {
    private struct Session {
        var samples: [WalkSample] = []
        var locationOff = false
        var task: Task<Void, Never>?
    }

    private let source: any WalkLocationSource
    private var sessions: [UUID: Session] = [:]

    public init(source: any WalkLocationSource) {
        self.source = source
    }

    public func begin(reservationID: UUID, destination: Coordinate) {
        guard sessions[reservationID] == nil else { return }
        let events = source.events()
        var session = Session()
        session.task = Task { [weak self] in
            for await event in events {
                await self?.record(event, for: reservationID)
            }
        }
        sessions[reservationID] = session
    }

    public func status(reservationID: UUID) -> WalkTrackingStatus {
        guard let session = sessions[reservationID] else { return .idle }
        return session.locationOff ? .locationOff : .tracking
    }

    public func samples(reservationID: UUID) -> [WalkSample] {
        sessions[reservationID]?.samples ?? []
    }

    public func finish(reservationID: UUID) -> [WalkSample] {
        guard let session = sessions.removeValue(forKey: reservationID) else { return [] }
        session.task?.cancel()
        return session.samples
    }

    private func record(_ event: WalkLocationEvent, for reservationID: UUID) {
        guard sessions[reservationID] != nil else { return }
        switch event {
        case .sample(let sample):
            sessions[reservationID]?.samples.append(sample)
            sessions[reservationID]?.locationOff = false
        case .denied, .unavailable:
            sessions[reservationID]?.locationOff = true
        }
    }
}
