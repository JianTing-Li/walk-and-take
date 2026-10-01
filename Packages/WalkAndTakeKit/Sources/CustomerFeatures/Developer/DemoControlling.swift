//
//  DemoControlling.swift
//  WalkAndTakeKit
//
//  What Developer mode's demo tools can do. Screens only see this protocol; the app implements it
//  with the concrete clock and stores, so features never reach past their repository protocols.
//

import Foundation

@MainActor
public protocol DemoControlling: AnyObject, Sendable {
    // MARK: Time

    /// The app's current time.
    var now: Date { get }
    /// False while time traveling.
    var isTimeLive: Bool { get }
    /// Jumps the app's clock; rollover and every screen follow.
    func travel(to date: Date)
    func advanceTime(by interval: TimeInterval)
    func resetTimeToLive()
}
