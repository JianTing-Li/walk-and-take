//
//  DeveloperLocationProvider.swift
//  WalkAndTakeKit
//

import Domain
import Foundation

/// Always "at" the service-area center, as if the device reported it. No permission prompt.
public struct FixedLocationProvider: LocationProvider {
    public init() {}

    public func resolve() async -> ResolvedLocation {
        ResolvedLocation(coordinate: ServiceArea.longIslandCity.center, source: .device)
    }
}

/// The device's location, or the fixed one while Developer mode's Fixed location is on.
/// Checked on every resolve, so flipping the switch takes effect at once.
public struct DeveloperLocationProvider: LocationProvider {
    private let device: any LocationProvider
    private let fixed = FixedLocationProvider()
    private let settings: DeveloperSettings

    public init(device: any LocationProvider, settings: DeveloperSettings) {
        self.device = device
        self.settings = settings
    }

    public func resolve() async -> ResolvedLocation {
        await settings.usesFixedLocation ? fixed.resolve() : device.resolve()
    }
}
