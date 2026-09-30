//
//  WalkCatchphrases.swift
//  WalkAndTakeKit
//
//  The lines shown after a walked pickup. They cycle in order, one per credited pickup, so a customer
//  sees a different one each time. The first is the app-name line the team picked for launch.
//

import Foundation

public enum WalkCatchphrases {
    public static let all = [
        "Walk&Take: every mile gets you something.",
        "Walk it. Earn it.",
        "Every step pays off.",
        "Miles make meals.",
        "Walk more, eat free.",
        "Walk it off, eat it up.",
        "Steps to snacks.",
        "Your walk is worth something.",
        "Earn your appetite.",
        "Walk it. Take it.",
    ]

    /// The line for the customer's Nth credited pickup (1 is the first). Wraps after the last.
    public static func phrase(forWalkNumber number: Int) -> String {
        all[((max(1, number) - 1) % all.count + all.count) % all.count]
    }
}
