//
//  DeveloperSettings.swift
//  WalkAndTakeKit
//
//  Developer mode: a switch at the bottom of Profile, in every build, that shows demo tools so the
//  whole flow can be shown without walking anywhere. Saved in UserDefaults, so it survives relaunches
//  and Reset demo data.
//

import Foundation
import Observation

@Observable
@MainActor
public final class DeveloperSettings {
    /// Shows the Developer section and the demo controls.
    public var isOn: Bool {
        didSet {
            defaults.set(isOn, forKey: Key.isOn)
            if isOn != oldValue, fixedLocation { locationBroadcaster.send(()) }
        }
    }

    /// Pretend to be at the service-area center, with no location prompt. Applies only while `isOn`.
    public var fixedLocation: Bool {
        didSet {
            defaults.set(fixedLocation, forKey: Key.fixedLocation)
            if fixedLocation != oldValue, isOn { locationBroadcaster.send(()) }
        }
    }

    /// Fixed location is in effect (both switches on).
    public var usesFixedLocation: Bool { isOn && fixedLocation }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locationBroadcaster = Broadcaster<Void>()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isOn = defaults.bool(forKey: Key.isOn)
        fixedLocation = defaults.bool(forKey: Key.fixedLocation)
    }

    /// Developer mode off, and every setting under it back to its default.
    public func turnOff() {
        isOn = false
        fixedLocation = false
    }

    /// Yields when the location in effect changes, so screens can resolve it again.
    public nonisolated func locationChanges() -> AsyncStream<Void> {
        locationBroadcaster.stream()
    }

    private enum Key {
        static let isOn = "developer.isOn"
        static let fixedLocation = "developer.fixedLocation"
    }
}
