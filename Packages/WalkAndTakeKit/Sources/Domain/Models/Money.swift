//
//  Money.swift
//  WalkAndTakeKit
//

import Foundation

/// An amount in US cents. Prices stay whole cents end to end;
/// formatting as dollars happens only at the UI edge.
public struct Money: Hashable, Comparable, Sendable, Codable {
    public var cents: Int

    public init(cents: Int) {
        self.cents = cents
    }

    public static let zero = Money(cents: 0)

    /// Exact dollar value, for currency formatting.
    public var decimalDollars: Decimal { Decimal(cents) / 100 }

    public static func < (lhs: Money, rhs: Money) -> Bool { lhs.cents < rhs.cents }
    public static func + (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents + rhs.cents) }
    public static func - (lhs: Money, rhs: Money) -> Money { Money(cents: lhs.cents - rhs.cents) }
    public static func * (lhs: Money, rhs: Int) -> Money { Money(cents: lhs.cents * rhs) }
    public static func += (lhs: inout Money, rhs: Money) { lhs = lhs + rhs }

    /// The amount taken off by a whole-number percent discount. Rounds down, so the customer never pays less.
    public func discount(percent: Int) -> Money {
        Money(cents: cents * percent / 100)
    }
}
