//
//  DemoTime.swift
//  WalkAndTakeKit
//
//  The New York times Developer mode jumps to, shared by Time travel and the Demo menu.
//

import Foundation
import Platform

enum DemoTime {
    struct Preset: Identifiable, Hashable {
        var id: String { label }
        let label: String
        let hour: Int
        let minute: Int
    }

    static let presets: [Preset] = [
        Preset(label: "Breakfast · 7:45 AM", hour: 7, minute: 45),
        Preset(label: "Lunch · 12:30 PM", hour: 12, minute: 30),
        Preset(label: "Tomorrow's bags open · 8:15 PM", hour: 20, minute: 15),
        Preset(label: "Just before midnight · 11:50 PM", hour: 23, minute: 50),
    ]

    /// `preset`'s time on the New York day of `now`.
    static func date(_ preset: Preset, on now: Date) -> Date? {
        NYCalendar.date(on: NYCalendar.dayKey(for: now), hour: preset.hour, minute: preset.minute)
    }
}
