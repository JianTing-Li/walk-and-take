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

    // MARK: Walks

    /// This order's walk is simulated, so the demo buttons can drive it.
    func isSimulatedWalk(_ reservationID: UUID) async -> Bool
    /// The simulated walk is moving on its own.
    func isAutoWalking(_ reservationID: UUID) async -> Bool
    /// Steps the simulated walk forward (and pauses auto-walk).
    func advanceWalk(_ reservationID: UUID, miles: Double) async
    /// Straight to the restaurant's door.
    func arriveWalk(_ reservationID: UUID) async
    /// Walks the rest of the way on its own.
    func autoWalk(_ reservationID: UUID) async
    func pauseWalk(_ reservationID: UUID) async
}
