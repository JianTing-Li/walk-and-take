//
//  PickupModel.swift
//  WalkAndTakeKit
//
//  Everything here reads the reservation's snapshot, never the live offer.
//

import DesignSystem
import Domain
import Foundation
import Observation
import Platform

@Observable
@MainActor
public final class PickupModel {
    public enum State: Equatable {
        case loading, loaded, notFound
        case failed(String)
    }

    public struct Header: Hashable, Sendable {
        public let symbol: String
        public let tone: PickupStatusPill.Tone
        public let title: String
        public let subtitle: String
    }

    public private(set) var state: State = .loading
    public var collectFailed = false
    /// Set when a walk couldn't be started.
    public var walkFailed = false
    /// This order's walk, once started.
    public private(set) var walk: Walk?
    public private(set) var trackingStatus: WalkTrackingStatus = .idle
    /// What finishing the walk produced: miles counted and any rewards banked.
    public private(set) var walkCompletion: WalkCompletion?
    /// Live progress of the walk in progress, from the fixes recorded so far.
    public private(set) var liveProgress: WalkProgress?
    /// What a finished, credited walk added to the customer's miles. Worked out from their walk history,
    /// so it's the same right after pickup and whenever the order is opened later.
    public private(set) var earnings: WalkEarnings?
    /// A walk is being started; Start walk can't be tapped again meanwhile.
    public private(set) var isStartingWalk = false
    private var isCompletingWalk = false
    /// Developer mode: this walk is simulated, and whether it's walking on its own.
    public private(set) var walkIsSimulated = false
    public private(set) var isAutoWalking = false
    /// Progress checks in a row with no usable fix. After a few, the card suggests keeping the app open.
    private var emptyPolls = 0
    /// About 30 s of polling (every 3 s).
    static let noFixHintAfterPolls = 10
    /// Stars tapped on the rating card; presents the rating sheet.
    public var rateRequest: RateRequest?

    private(set) var reservation: Reservation?
    private(set) var now: Date
    let reservationID: UUID
    private let origin: ResolvedLocation
    let dependencies: CustomerDependencies

    public init(reservationID: UUID, origin: ResolvedLocation, dependencies: CustomerDependencies) {
        self.reservationID = reservationID
        self.origin = origin
        self.dependencies = dependencies
        now = dependencies.clock.now
    }

    public var flags: FeatureFlags { dependencies.flags }
    public var developer: DeveloperSettings { dependencies.developer }
    private var calendar: Calendar { NYCalendar.calendar }

    // MARK: - Lifecycle

    public func run() async {
        await load()
        let changes = dependencies.reservations.changes()
        let clockChanges = dependencies.clock.changes()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in changes { await self.load() } }
            group.addTask { for await _ in clockChanges { await self.load() } }
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(15))
                    await self.load()
                }
            }
            group.addTask {
                // The walk moves faster than the order does, so its progress refreshes more often.
                while !Task.isCancelled {
                    // Simulated walks refresh every second so Developer mode's demo moves smoothly.
                    try? await Task.sleep(for: .seconds(self.walkIsSimulated ? 1 : 3))
                    await self.refreshLiveProgress()
                }
            }
        }
    }

    public func load() async {
        do {
            reservation = try await dependencies.reservations.reservation(id: reservationID)
            now = dependencies.clock.now
            state = reservation == nil ? .notFound : .loaded
            await refreshWalk()
        } catch {
            if state == .loading { state = .failed("Couldn't load this order. Please try again.") }
        }
    }

    /// Reads the walk and its recording state. Resumes recording for a walk the app lost (e.g. relaunch)
    /// and drops the recording of an order that was cancelled or missed.
    private func refreshWalk() async {
        guard flags.walkRewards else { return }
        walk = try? await dependencies.walkRewards.walk(reservationID: reservationID)
        await refreshEarnings()
        guard let reservation else { return }
        var tracking = await dependencies.walkTracker.status(reservationID: reservationID)
        switch status {
        case .upcoming, .readyNow:
            if let walk, walk.finishedAt == nil, tracking == .idle {
                await dependencies.walkTracker.begin(
                    reservationID: reservationID, destination: reservation.snapshot.coordinate)
                tracking = await dependencies.walkTracker.status(reservationID: reservationID)
            }
        case .cancelled, .missed:
            if tracking != .idle {
                _ = await dependencies.walkTracker.finish(reservationID: reservationID)
                tracking = .idle
            }
            if walk != nil { await dependencies.walkTracker.discard(reservationID: reservationID) }
        case .collected:
            // Confirmed, but the app died before the walk was credited: finish it from the saved fixes.
            if let walk, walk.finishedAt == nil { await completeWalk() }
        case nil:
            break
        }
        trackingStatus = tracking
        await refreshLiveProgress()
    }

    private func refreshEarnings() async {
        guard let walk, walk.finishedAt != nil, walk.creditedMiles > 0,
            let walks = try? await dependencies.walkRewards.walks()
        else {
            earnings = nil
            return
        }
        earnings = WalkEarnings.of(walk, in: walks)
    }

    /// Re-reads the recorded fixes while a walk is in progress. Cleared when there's no walk to show.
    func refreshLiveProgress() async {
        guard flags.walkRewards, let walk, walk.finishedAt == nil, let snapshot = reservation?.snapshot,
            trackingStatus != .idle
        else {
            if liveProgress != nil { liveProgress = nil }
            return
        }
        let samples = await dependencies.walkTracker.samples(reservationID: reservationID)
        let progress = WalkVerifier.progress(samples: samples, destination: snapshot.coordinate)
        // Only a real change redraws the screen.
        if progress != liveProgress { liveProgress = progress }
        if developer.isOn {
            walkIsSimulated = await dependencies.demo.isSimulatedWalk(reservationID)
            isAutoWalking = await dependencies.demo.isAutoWalking(reservationID)
        }
        emptyPolls = liveProgress == nil ? emptyPolls + 1 : 0
        trackingStatus = await dependencies.walkTracker.status(reservationID: reservationID)
    }

    // MARK: - Actions

    /// Confirms pickup at the counter (after the swipe).
    public func collect() async {
        do {
            reservation = try await dependencies.reservations.markCollected(
                reservationID: reservationID, at: dependencies.clock.now)
            now = dependencies.clock.now
            await completeWalk()
        } catch {
            collectFailed = true
        }
    }

    /// Starts recording the walk to the restaurant.
    public func startWalk() async {
        guard canStartWalk else { return }
        await beginWalk()
    }

    func beginWalk() async {
        guard !isStartingWalk, walk == nil, let snapshot = reservation?.snapshot else { return }
        isStartingWalk = true
        defer { isStartingWalk = false }
        do {
            walk = try await dependencies.walkRewards.startWalk(
                reservationID: reservationID, restaurantID: snapshot.restaurantID, at: dependencies.clock.now)
            await dependencies.walkTracker.begin(reservationID: reservationID, destination: snapshot.coordinate)
            trackingStatus = await dependencies.walkTracker.status(reservationID: reservationID)
            await refreshLiveProgress()
        } catch {
            walkFailed = true
        }
    }

    /// After a confirmed pickup: stop recording, check the track, and credit the miles.
    /// A failed check still leaves the pickup done; it just earns no miles.
    private func completeWalk() async {
        guard flags.walkRewards, let walk, walk.finishedAt == nil, let snapshot = reservation?.snapshot,
            !isCompletingWalk
        else { return }
        // The swipe and a screen reload can both get here; only one may credit the walk.
        isCompletingWalk = true
        defer { isCompletingWalk = false }
        var samples = await dependencies.walkTracker.finish(reservationID: reservationID)
        // No live recording means the app was killed mid-walk: read back the fixes it had saved.
        if samples.isEmpty { samples = await dependencies.walkTracker.recover(reservationID: reservationID) }
        trackingStatus = .idle
        liveProgress = nil
        let verdict = WalkVerifier.verify(samples: samples, destination: snapshot.coordinate)
        do {
            // The repeat-pickup rule counts days in the customer's current time zone.
            let completion = try await dependencies.walkRewards.finishWalk(
                reservationID: reservationID, verdict: verdict, at: dependencies.clock.now, calendar: .current)
            walkCompletion = completion
            self.walk = completion.walk
            // Credited, so the saved fixes have done their job. (If crediting failed they stay for a retry.)
            await dependencies.walkTracker.discard(reservationID: reservationID)
        } catch {
            self.walk = try? await dependencies.walkRewards.walk(reservationID: reservationID)
        }
        await refreshEarnings()
    }

    public func rate(stars: Int) {
        rateRequest = RateRequest(reservationID: reservationID, stars: stars)
    }

    // MARK: - Output

    public var status: ReservationPolicy.Status? {
        reservation.map { ReservationPolicy.status(of: $0, at: now) }
    }

    public var isActive: Bool { status == .upcoming || status == .readyNow }
    public var restaurantName: String { reservation?.snapshot.restaurantName ?? "" }
    public var code: String { reservation?.confirmationCode ?? "" }
    public var pickupInstructions: String { reservation?.snapshot.pickupInstructions ?? "" }

    public var header: Header? {
        guard let reservation, let status else { return nil }
        let window = reservation.snapshot.pickupWindow
        let countdown = PickupDayFormatter.countdown(window, now: now, calendar: calendar)
        let end = time(window.end)
        return switch status {
        case .readyNow:
            Header(
                symbol: "bag.fill", tone: .readyNow, title: "Ready for pickup",
                subtitle: countdown.hasPrefix("Ends in") ? "\(countdown) · until \(end)" : "Open until \(end)")
        case .upcoming:
            Header(
                symbol: "clock.fill", tone: .upcoming,
                title: countdown.replacingOccurrences(of: "Opens", with: "Pickup opens"),
                subtitle: "Your bag is held until \(end)")
        case .collected:
            Header(
                symbol: "checkmark.circle.fill", tone: .collected,
                title: reservation.snapshot.category == .breakfast ? "Enjoy your breakfast!" : "Enjoy your food!",
                subtitle: "Picked up at \(time(reservation.collectedAt ?? now))")
        case .missed:
            Header(
                symbol: "xmark.circle.fill", tone: .inactive, title: "Pickup window ended",
                subtitle: "This order wasn't collected before \(end).")
        case .cancelled:
            Header(
                symbol: "xmark.circle.fill", tone: .inactive, title: "Order cancelled",
                subtitle: "Cancelled at \(time(reservation.cancelledAt ?? now)). You won't be charged, "
                    + "and your bag is back on sale for someone else."
                    + (reservation.rewardID != nil ? " Your walking reward is back in your rewards." : ""))
        }
    }

    /// Show "Change or cancel order" (manage flag on, before the deadline).
    public var canManage: Bool {
        guard flags.manageOrder, let reservation else { return false }
        return ReservationPolicy.canChange(reservation, at: now)
    }

    /// Shown instead of the manage link once changes close.
    public var changesClosedText: String? {
        guard flags.manageOrder, isActive, !canManage, let reservation else { return nil }
        let deadline = time(ReservationPolicy.changeDeadline(for: reservation))
        return "Changes closed at \(deadline). The store is getting your bag ready."
    }

    /// "Vernon Blvd & 48th Ave, Long Island City · 0.2 mi"
    public var addressLine: String {
        guard let snapshot = reservation?.snapshot else { return "" }
        let miles = PreferenceMatcher.distanceMiles(to: snapshot.coordinate, from: origin)
        return String(format: "%@ · %.1f mi", snapshot.address.shortLine, miles)
    }

    /// Apple Maps walking/transit directions to the restaurant.
    public var directionsURL: URL? {
        guard let snapshot = reservation?.snapshot else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(snapshot.coordinate.latitude),\(snapshot.coordinate.longitude)"),
            URLQueryItem(name: "q", value: snapshot.restaurantName),
        ]
        return components?.url
    }

    // MARK: - Walking

    /// Where the Start Walk button is: before the window's last hour, ready, or already walking.
    public enum WalkSection: Hashable, Sendable {
        /// "Start walk opens at 6:30 AM"
        case opensLater(String)
        /// The walk and its reward, with a Start Walk button.
        case ready(WalkRewardCard.Content)
        /// Recording: live progress, what to do next, and a warning if location is off.
        case walking(Walking)

        public struct Walking: Hashable, Sendable {
            public enum Phase: Hashable, Sendable {
                /// On the way (or waiting for a location).
                case walking
                /// At the door before the pickup window opens.
                case arrivedEarly
                /// At the door with the window open: the card shrinks so the code and swipe show.
                case arrived
            }

            public var phase: Phase
            public var title: String
            public var detail: String?
            public var warning: String?
            /// 0...1 along the route; 0 until there are two usable fixes.
            public var fraction: Double
            /// Tick marks on the bar, 0...1.
            public var ticks: [Double]
            /// "0.3 mi walked · 0.2 mi to go", or what we're waiting for.
            public var progressText: String
        }
    }

    public var canStartWalk: Bool {
        guard flags.walkRewards, walk == nil, let reservation else { return false }
        return WalkPolicy.canStart(reservation, at: now)
    }

    /// Miles from where distances are measured to the restaurant.
    private var walkDistance: Double? {
        reservation.map { PreferenceMatcher.distanceMiles(to: $0.snapshot.coordinate, from: origin) }
    }

    public var walkSection: WalkSection? {
        guard flags.walkRewards, isActive, let reservation, let distance = walkDistance else { return nil }
        if let walk, walk.finishedAt == nil {
            return .walking(walking(walk, reservation: reservation, distance: distance))
        }
        if canStartWalk {
            return .ready(
                WalkRewardCard.Content(
                    title: WalkCopy.walkTitle(forDistance: distance),
                    detail: WalkCopy.earnsText(forDistance: distance),
                    footnote: WalkCopy.capNote(forDistance: distance)))
        }
        guard walk == nil, now < WalkPolicy.startOpensAt(for: reservation) else { return nil }
        return .opensLater("Start walk opens at \(time(WalkPolicy.startOpensAt(for: reservation)))")
    }

    /// The walk card while recording: on the way, here early, or here with the window open.
    private func walking(_ walk: Walk, reservation: Reservation, distance: Double) -> WalkSection.Walking {
        let ticks = WalkCopy.walkTicks(forDistance: distance)
        let opens = time(reservation.snapshot.pickupWindow.start)
        // With location off the recording can't be trusted, so it stays "walking" with the warning.
        if let progress = liveProgress, trackingStatus != .locationOff, WalkCopy.isAtDoor(progress) {
            if status == .upcoming {
                return .init(
                    phase: .arrivedEarly, title: "You've arrived",
                    detail: "You're here early. Pickup opens at \(opens) — your miles are saved.",
                    fraction: 1, ticks: ticks, progressText: WalkCopy.walkedText(progress))
            }
            return .init(
                phase: .arrived, title: "\(WalkCopy.walkedText(progress)) · swipe below to confirm",
                fraction: 1, ticks: ticks, progressText: WalkCopy.walkedText(progress))
        }
        let started = "Started at \(time(walk.startedAt))."
        let waitingTooLong = liveProgress == nil && emptyPolls >= Self.noFixHintAfterPolls
        let warning: String? =
            switch trackingStatus {
            case .locationOff: "Location is off, so your miles can't be counted. Turn it on in Settings."
            default: waitingTooLong ? "No location yet. Keep Walk & Take open while you walk." : nil
            }
        return .init(
            phase: .walking, title: "Walk in progress",
            detail: status == .upcoming
                ? "\(started) Pickup opens at \(opens)." : "\(started) Swipe to confirm pickup when you arrive.",
            warning: warning,
            fraction: liveProgress?.fraction ?? 0, ticks: ticks,
            progressText: liveProgress.map(WalkCopy.progressText) ?? "Waiting for your first location…")
    }

    /// The "miles earned" celebration after a credited walk. Nil for other pickups or with the flag off.
    public var walkEarned: WalkEarnedCard.Content? {
        guard flags.walkRewards, status == .collected, let earnings else { return nil }
        return WalkCopy.earnedCard(earnings)
    }

    /// After pickup: miles counted, or why none were.
    public var walkResultText: String? {
        guard flags.walkRewards, let walk, walk.finishedAt != nil else { return nil }
        if walk.creditedMiles > 0 { return "+\(WalkCopy.miles(walk.creditedMiles)) mi counted toward rewards" }
        return walk.rejection?.message
    }

    public var review: Review? { flags.reviews ? reservation?.review : nil }

    public var canReview: Bool {
        guard flags.reviews, let reservation else { return false }
        return ReviewPolicy.canReview(reservation, at: now)
    }

    /// "You saved $12.51 and about 2.5 kg of CO₂e." (impact flag, collected only)
    public var impactText: String? {
        guard flags.impact, status == .collected, let reservation else { return nil }
        let kg = ImpactCalculator.co2e(forBags: reservation.quantity)
        return "You saved \(reservation.savings.usd) and about \(String(format: "%.1f", kg)) kg of CO₂e."
    }

    public var summary: [(label: String, value: String)] {
        guard let reservation else { return [] }
        // After pickup, say when it happened rather than when to go.
        let when: (String, String) =
            if let collectedAt = reservation.collectedAt {
                ("Picked up", "\(TimeText.shortDate(collectedAt, calendar: calendar)) at \(time(collectedAt))")
            } else {
                ("Pickup", PickupDayFormatter.full(reservation.snapshot.pickupWindow, now: now, calendar: calendar))
            }
        var rows = [("Order", "\(reservation.quantity) × \(reservation.snapshot.bagName)"), when]
        if reservation.rewardID != nil {
            rows.append(("Reward", "\(WalkRewardLadder.discountPercent)% off one bag: −\(reservation.discount.usd)"))
        }
        rows.append(("Total", reservation.total.usd))
        // The earned card already shows a credited walk; the row only explains walks that earned nothing.
        if walkEarned == nil, let walkResultText { rows.append(("Walk", walkResultText)) }
        return rows
    }

    private func time(_ date: Date) -> String { TimeText.time(date, calendar: calendar) }
}

/// Opens the rating sheet with the stars already tapped.
public struct RateRequest: Identifiable, Hashable, Sendable {
    public var id: UUID { reservationID }
    public let reservationID: UUID
    public let stars: Int
}
