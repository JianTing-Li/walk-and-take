//
//  DiscoverModel+Demo.swift
//  WalkAndTakeKit
//
//  Developer mode's Demo menu on Discover: jump the clock to when bags open.
//

import Domain
import Foundation

extension DiscoverModel {
    struct DemoJump: Identifiable {
        var id: String { title }
        let title: String
        let date: Date
    }

    /// Breakfast, lunch, tomorrow's bags (8 PM) and just before midnight, today in New York.
    var demoTimeJumps: [DemoJump] {
        DemoTime.presets.compactMap { preset in
            DemoTime.date(preset, on: now).map { DemoJump(title: preset.label, date: $0) }
        }
    }

    func demoTravel(to date: Date) { dependencies.demo.travel(to: date) }

    /// Shown only after time traveling.
    var demoCanResetTime: Bool { !dependencies.demo.isTimeLive }

    func demoResetTime() { dependencies.demo.resetTimeToLive() }
}
