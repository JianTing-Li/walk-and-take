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

    /// Shows the floating Demo button on screens. Off keeps every screen exactly as customers see it,
    /// while the other settings keep working. Applies only while `isOn`.
    public var showsDemoControls: Bool {
        didSet { defaults.set(showsDemoControls, forKey: Key.showsDemoControls) }
    }

    /// The Demo button is showing (both switches on).
    public var usesDemoControls: Bool { isOn && showsDemoControls }

    /// Fixed location is in effect (both switches on).
    public var usesFixedLocation: Bool { isOn && fixedLocation }

    /// Walks follow a scripted route instead of GPS, driven by the demo controls. Applies only while `isOn`.
    public var simulatedWalks: Bool {
        didSet { defaults.set(simulatedWalks, forKey: Key.simulatedWalks) }
    }

    /// Seconds a simulated walk takes to reach the door on its own.
    public var autoWalkSeconds: Int {
        didSet { defaults.set(autoWalkSeconds, forKey: Key.autoWalkSeconds) }
    }

    public static let autoWalkOptions = [10, 20, 60]
    public static let defaultAutoWalkSeconds = 20

    /// New walks are simulated (both switches on).
    public var usesSimulatedWalks: Bool { isOn && simulatedWalks }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let locationBroadcaster = Broadcaster<Void>()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isOn = defaults.bool(forKey: Key.isOn)
        fixedLocation = defaults.bool(forKey: Key.fixedLocation)
        showsDemoControls = defaults.object(forKey: Key.showsDemoControls) as? Bool ?? true
        simulatedWalks = defaults.object(forKey: Key.simulatedWalks) as? Bool ?? true
        autoWalkSeconds = defaults.object(forKey: Key.autoWalkSeconds) as? Int ?? Self.defaultAutoWalkSeconds
    }

    /// Developer mode off, and every setting under it back to its default.
    public func turnOff() {
        isOn = false
        fixedLocation = false
        showsDemoControls = true
        simulatedWalks = true
        autoWalkSeconds = Self.defaultAutoWalkSeconds
    }

    /// Yields when the location in effect changes, so screens can resolve it again.
    public nonisolated func locationChanges() -> AsyncStream<Void> {
        locationBroadcaster.stream()
    }

    private enum Key {
        static let isOn = "developer.isOn"
        static let fixedLocation = "developer.fixedLocation"
        static let showsDemoControls = "developer.showsDemoControls"
        static let simulatedWalks = "developer.simulatedWalks"
        static let autoWalkSeconds = "developer.autoWalkSeconds"
    }
}
