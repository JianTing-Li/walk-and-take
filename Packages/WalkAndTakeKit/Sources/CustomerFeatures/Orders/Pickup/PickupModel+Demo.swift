//
//  PickupModel+Demo.swift
//  WalkAndTakeKit
//
//  Developer mode's controls on the order screen: start a walk any time, drive a simulated walk,
//  and move the clock to the pickup window.
//

import Domain
import Foundation
import Platform

extension PickupModel {
    /// What the inline demo panel offers right now. Nil hides it.
    public enum DemoWalkControls: Hashable, Sendable {
        /// No walk yet, and the real Start walk button isn't showing.
        case startNow
        /// A simulated walk: step it, let it walk itself, or jump to the door.
        case simulated(isAutoWalking: Bool, arrived: Bool)
        /// A GPS walk, which the demo can't drive.
        case live
    }

    public var demoWalkControls: DemoWalkControls? {
        guard developer.isOn, flags.walkRewards, isActive else { return nil }
        guard let walk else { return canStartWalk ? nil : .startNow }
        guard walk.finishedAt == nil else { return nil }
        guard walkIsSimulated else { return .live }
        let arrived = liveProgress.map(WalkCopy.isAtDoor) ?? false
        return .simulated(isAutoWalking: isAutoWalking && !arrived, arrived: arrived)
    }

    /// Developer mode: start a walk outside the usual hour before pickup.
    public func startWalkNow() async {
        guard developer.isOn, flags.walkRewards, walk == nil, isActive else { return }
        await beginWalk()
    }

    public func demoStep() async {
        await dependencies.demo.advanceWalk(reservationID, miles: 0.1)
        await refreshLiveProgress()
    }

    public func demoArrive() async {
        await dependencies.demo.arriveWalk(reservationID)
        await refreshLiveProgress()
    }

    /// Auto-walk on, or paused where it is.
    public func demoToggleAutoWalk() async {
        if isAutoWalking {
            await dependencies.demo.pauseWalk(reservationID)
        } else {
            await dependencies.demo.autoWalk(reservationID)
        }
        await refreshLiveProgress()
    }

    /// Before the window: jump the clock to when pickup opens.
    public var canOpenPickupNow: Bool { developer.isOn && status == .upcoming }

    public func openPickupNow() {
        guard canOpenPickupNow, let window = reservation?.snapshot.pickupWindow else { return }
        dependencies.demo.travel(to: window.start)
    }

    /// Sends this order's "your bag is ready" notification in a second.
    public func demoSendReminder() async {
        guard developer.isOn, isActive, let reservation else { return }
        guard await dependencies.notifications.requestPermission() else { return }
        await dependencies.notifications.sendReminder(
            PickupReminder(reservation, now: now), after: PickupReminder.demoDelay)
    }

    /// Confirms pickup without the swipe, opening the window first if it hasn't yet.
    public func demoConfirmPickup() async {
        guard developer.isOn, isActive, let window = reservation?.snapshot.pickupWindow else { return }
        if status == .upcoming {
            dependencies.demo.travel(to: window.start)
        }
        await collect()
    }

    /// Jump to 5 minutes before the window closes, to show the closing countdown.
    public var canJumpToClosing: Bool {
        guard developer.isOn, isActive, let window = reservation?.snapshot.pickupWindow else { return false }
        return now < window.end.addingTimeInterval(-5 * 60)
    }

    public func jumpToClosing() {
        guard canJumpToClosing, let window = reservation?.snapshot.pickupWindow else { return }
        dependencies.demo.travel(to: window.end.addingTimeInterval(-5 * 60))
    }
}
