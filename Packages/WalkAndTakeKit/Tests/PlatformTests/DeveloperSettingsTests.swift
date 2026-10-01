//
//  DeveloperSettingsTests.swift
//  PlatformTests
//

import Domain
import Foundation
import Testing

@testable import Platform

@MainActor
@Suite("Developer mode settings")
struct DeveloperSettingsTests {
    func defaults() -> UserDefaults { UserDefaults(suiteName: "DeveloperSettingsTests.\(UUID().uuidString)")! }

    @Test func offByDefault() {
        let settings = DeveloperSettings(defaults: defaults())
        #expect(!settings.isOn)
        #expect(!settings.fixedLocation)
        #expect(!settings.usesFixedLocation)
    }

    @Test func switchesSurviveARelaunch() {
        let store = defaults()
        let first = DeveloperSettings(defaults: store)
        first.isOn = true
        first.fixedLocation = true
        let relaunched = DeveloperSettings(defaults: store)
        #expect(relaunched.isOn)
        #expect(relaunched.fixedLocation)
    }

    @Test func fixedLocationAppliesOnlyInDeveloperMode() {
        let settings = DeveloperSettings(defaults: defaults())
        settings.fixedLocation = true
        #expect(!settings.usesFixedLocation)
        settings.isOn = true
        #expect(settings.usesFixedLocation)
    }

    @Test func turningOffResetsEverySetting() {
        let store = defaults()
        let settings = DeveloperSettings(defaults: store)
        settings.isOn = true
        settings.fixedLocation = true
        settings.turnOff()
        #expect(!settings.isOn)
        #expect(!settings.fixedLocation)
        let relaunched = DeveloperSettings(defaults: store)
        #expect(!relaunched.isOn)
        #expect(!relaunched.fixedLocation)
    }

    @Test func theLocationProviderFollowsTheSwitch() async {
        let away = Coordinate(latitude: 40.7, longitude: -73.9)
        let device = FakeProvider(location: ResolvedLocation(coordinate: away, source: .device))
        let settings = DeveloperSettings(defaults: defaults())
        let provider = DeveloperLocationProvider(device: device, settings: settings)
        #expect(await provider.resolve().coordinate == away)
        settings.isOn = true
        settings.fixedLocation = true
        #expect(await provider.resolve().coordinate == ServiceArea.longIslandCity.center)
    }

    @Test func changingTheLocationInEffectIsAnnounced() async {
        let settings = DeveloperSettings(defaults: defaults())
        let changes = settings.locationChanges()
        settings.isOn = true  // fixed location still off: nothing changes
        settings.fixedLocation = true
        var iterator = changes.makeAsyncIterator()
        #expect(await iterator.next() != nil)
    }
}

private struct FakeProvider: LocationProvider {
    let location: ResolvedLocation
    func resolve() async -> ResolvedLocation { location }
}
