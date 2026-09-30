//
//  CoreLocationWalkSource.swift
//  WalkAndTakeKit
//
//  Live fixes for a pickup walk. Holding a `CLBackgroundActivitySession` keeps updates
//  flowing with the screen locked (blue status indicator) using only When In Use access.
//  Needs the `location` background mode and NSLocationWhenInUseUsageDescription.
//

import CoreLocation
import Domain
import Foundation

public struct CoreLocationWalkSource: WalkLocationSource {
    public init() {}

    public func events() -> AsyncStream<WalkLocationEvent> {
        AsyncStream { continuation in
            let task = Task {
                let session = CLServiceSession(authorization: .whenInUse)
                let background = CLBackgroundActivitySession()
                defer {
                    background.invalidate()
                    session.invalidate()
                }
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                        if update.authorizationDenied || update.authorizationDeniedGlobally
                            || update.authorizationRestricted
                        {
                            continuation.yield(.denied)
                        } else if let location = update.location {
                            continuation.yield(.sample(Self.sample(from: location)))
                        } else if update.locationUnavailable {
                            continuation.yield(.unavailable)
                        }
                    }
                } catch {
                    continuation.yield(.unavailable)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func sample(from location: CLLocation) -> WalkSample {
        WalkSample(
            coordinate: Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            timestamp: location.timestamp,
            horizontalAccuracyMeters: location.horizontalAccuracy,
            isSimulated: location.sourceInformation?.isSimulatedBySoftware ?? false
        )
    }
}
