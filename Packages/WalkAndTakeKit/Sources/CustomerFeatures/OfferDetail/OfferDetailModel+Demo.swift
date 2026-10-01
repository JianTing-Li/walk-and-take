//
//  OfferDetailModel+Demo.swift
//  WalkAndTakeKit
//
//  Developer mode's Demo menu on a bag: jump the clock to its pickup window.
//

import Domain
import Foundation

extension OfferDetailModel {
    /// Before the window opens: jump to its start.
    var demoCanJumpToPickup: Bool {
        guard let window = offer?.pickupWindow else { return false }
        return now < window.start
    }

    func demoJumpToPickup() {
        guard demoCanJumpToPickup, let window = offer?.pickupWindow else { return }
        dependencies.demo.travel(to: window.start)
    }

    /// Up to 5 minutes before it closes: jump there, to show the "ending soon" state.
    var demoCanJumpToClosing: Bool {
        guard let window = offer?.pickupWindow else { return false }
        return now < window.end.addingTimeInterval(-5 * 60)
    }

    func demoJumpToClosing() {
        guard demoCanJumpToClosing, let window = offer?.pickupWindow else { return }
        dependencies.demo.travel(to: window.end.addingTimeInterval(-5 * 60))
    }
}
