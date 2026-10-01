//
//  TimeTravelView.swift
//  WalkAndTakeKit
//
//  Developer mode: jump the app's clock to interesting New York times. Moving the clock
//  triggers rollover (AppRoot watches clock changes), so crossing midnight or
//  8 PM behaves exactly as it would in real time.
//

import DesignSystem
import Domain
import Platform
import SwiftUI

struct TimeTravelView: View {
    let demo: any DemoControlling

    var body: some View {
        TimelineView(.animation(minimumInterval: 1)) { _ in
            let now = demo.now
            List {
                Section("App time (New York)") {
                    LabeledContent("Day", value: TimeText.shortDate(now, calendar: NYCalendar.calendar))
                    LabeledContent("Time", value: TimeText.time(now, calendar: NYCalendar.calendar))
                    LabeledContent("Mode", value: demo.isTimeLive ? "Live" : "Time traveling")
                }

                Section {
                    ForEach(DemoTime.presets) { preset in
                        Button(preset.label) {
                            if let date = DemoTime.date(preset, on: now) { demo.travel(to: date) }
                        }
                    }
                    Button("Next day, same time") { demo.advanceTime(by: 24 * 60 * 60) }
                } header: {
                    Text("Jump to (today, New York)")
                } footer: {
                    Text("Time keeps running from where you jump. Rollover runs automatically.")
                }

                Section {
                    Button("Back to live time", role: .destructive) { demo.resetTimeToLive() }
                        .disabled(demo.isTimeLive)
                }
            }
        }
        .navigationTitle("Time travel")
        .navigationBarTitleDisplayMode(.inline)
    }

}
