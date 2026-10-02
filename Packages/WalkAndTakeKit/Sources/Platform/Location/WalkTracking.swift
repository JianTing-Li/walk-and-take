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
    /// Starts recording for a reservation, picking up fixes already saved if the app was killed mid-walk.
    /// Does nothing if it is already recording.
    func begin(reservationID: UUID, destination: Coordinate) async
    func status(reservationID: UUID) async -> WalkTrackingStatus
    /// Everything recorded so far, without stopping.
    func samples(reservationID: UUID) async -> [WalkSample]
    /// Stops recording and returns everything recorded. Saved fixes are kept until `discard`, so a walk that was
    /// confirmed but not yet credited when the app died can still be finished.
    func finish(reservationID: UUID) async -> [WalkSample]
    /// The fixes saved for a walk, without starting to record. For finishing a walk after a kill.
    func recover(reservationID: UUID) async -> [WalkSample]
    /// Forgets a walk's saved fixes once it is credited or abandoned.
    func discard(reservationID: UUID) async
}

extension WalkTracking {
    /// Trackers that save nothing have nothing to recover.
    public func recover(reservationID: UUID) async -> [WalkSample] { [] }
    public func discard(reservationID: UUID) async {}
}

/// Records fixes from a `WalkLocationSource`, one session per reservation. With a store, fixes are saved in small
/// batches as they arrive, so a killed app resumes with the walk so far instead of an empty one.
public actor LiveWalkTracker: WalkTracking {
    /// Fixes are saved once this many are waiting...
    public static let saveEvery = 5
    /// ...or once this much walking time has passed since the last save, whichever comes first.
    public static let saveInterval: TimeInterval = 5

    private struct Session {
        var samples: [WalkSample] = []
        /// How many of `samples` are already saved, and when the newest saved one was taken.
        var saved = 0
        var lastSavedAt: Date?
        var locationOff = false
        var task: Task<Void, Never>?
    }

    private let source: any WalkLocationSource
    private let store: (any WalkSampleStoring)?
    private var sessions: [UUID: Session] = [:]

    public init(source: any WalkLocationSource, store: (any WalkSampleStoring)? = nil) {
        self.source = source
        self.store = store
    }

    public func begin(reservationID: UUID, destination: Coordinate) async {
        guard sessions[reservationID] == nil else { return }
        sessions[reservationID] = Session()  // claim the slot before waiting on the store
        let saved = (try? await store?.savedSamples(reservationID: reservationID)) ?? []
        guard sessions[reservationID] != nil else { return }  // finished while loading
        sessions[reservationID]?.samples = saved
        sessions[reservationID]?.saved = saved.count
        sessions[reservationID]?.lastSavedAt = saved.last?.timestamp
        let events = source.events()
        sessions[reservationID]?.task = Task { [weak self] in
            for await event in events {
                await self?.record(event, for: reservationID)
            }
        }
    }

    public func status(reservationID: UUID) -> WalkTrackingStatus {
        guard let session = sessions[reservationID] else { return .idle }
        return session.locationOff ? .locationOff : .tracking
    }

    public func samples(reservationID: UUID) -> [WalkSample] {
        sessions[reservationID]?.samples ?? []
    }

    public func finish(reservationID: UUID) async -> [WalkSample] {
        guard let session = sessions[reservationID] else { return [] }
        session.task?.cancel()
        await save(reservationID, upTo: session.samples.count)  // the arrival fixes matter most
        let samples = sessions[reservationID]?.samples ?? session.samples
        sessions[reservationID] = nil
        return samples
    }

    public func recover(reservationID: UUID) async -> [WalkSample] {
        if let session = sessions[reservationID] { return session.samples }
        return (try? await store?.savedSamples(reservationID: reservationID)) ?? []
    }

    public func discard(reservationID: UUID) async {
        try? await store?.discardSamples(reservationID: reservationID)
    }

    private func record(_ event: WalkLocationEvent, for reservationID: UUID) async {
        guard sessions[reservationID] != nil else { return }
        switch event {
        case .sample(let sample):
            sessions[reservationID]?.samples.append(sample)
            sessions[reservationID]?.locationOff = false
            guard let session = sessions[reservationID] else { return }
            let waiting = session.samples.count - session.saved
            let sinceSave = session.lastSavedAt.map { sample.timestamp.timeIntervalSince($0) } ?? .infinity
            if waiting >= Self.saveEvery || sinceSave >= Self.saveInterval {
                await save(reservationID, upTo: session.samples.count)
            }
        case .denied, .unavailable:
            sessions[reservationID]?.locationOff = true
        }
    }

    /// Saves the fixes not yet saved, up to `count`. A failed save is retried with the next batch.
    private func save(_ reservationID: UUID, upTo count: Int) async {
        guard let store, let session = sessions[reservationID], count > session.saved else { return }
        let batch = Array(session.samples[session.saved..<count])
        let start = session.saved
        sessions[reservationID]?.saved = count  // claim it so a fix arriving mid-save doesn't save these twice
        sessions[reservationID]?.lastSavedAt = batch.last?.timestamp
        do {
            try await store.appendSamples(batch, reservationID: reservationID)
        } catch {
            if let now = sessions[reservationID]?.saved, now == count { sessions[reservationID]?.saved = start }
        }
    }
}
