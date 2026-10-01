//
//  LiveNotificationScheduler.swift
//  WalkAndTakeKit
//

import Domain
import Foundation
import UserNotifications

public struct LiveNotificationScheduler: NotificationScheduler {
    private var center: UNUserNotificationCenter { .current() }

    public init() {}

    public func requestPermission() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default:
            return false
        }
    }

    public func schedule(_ alerts: [OfferAlert], now: Date) async {
        for alert in NotificationPlan.upcoming(alerts, now: now) {
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: alert.pickupWindow.start.timeIntervalSince(now),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: NotificationPlan.identifier(forOfferID: alert.offerID),
                content: Self.content(for: alert),
                trigger: trigger
            )
            try? await center.add(request)
        }
    }

    public func replaceAll(with alerts: [OfferAlert], now: Date) async {
        let pending = await center.pendingNotificationRequests()
        let drops = pending.map(\.identifier).filter { $0.hasPrefix(NotificationPlan.dropPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: drops)
        await schedule(alerts, now: now)
    }

    public func cancel(offerIDs: [String]) async {
        center.removePendingNotificationRequests(
            withIdentifiers: offerIDs.map(NotificationPlan.identifier(forOfferID:))
        )
    }

    public func cancelAll() async {
        center.removeAllPendingNotificationRequests()
    }

    public func sendPreview(_ alert: OfferAlert, after delay: TimeInterval) async {
        // The trigger needs a positive interval; one second is "now" for a banner.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(
            identifier: NotificationPlan.previewPrefix + UUID().uuidString,
            content: Self.content(for: alert),
            trigger: trigger
        )
        try? await center.add(request)
    }

    public func sendReminder(_ reminder: PickupReminder, after delay: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = NotificationPlan.title(for: reminder)
        content.body = NotificationPlan.body(for: reminder)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: NotificationPlan.reminderPrefix + reminder.reservationID.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        )
        try? await center.add(request)
    }

    private static func content(for alert: OfferAlert) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = NotificationPlan.title(for: alert)
        content.body = NotificationPlan.body(for: alert)
        content.sound = .default
        return content
    }
}

/// Shows alerts as banners even while the app is open.
public final class NotificationBannerDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    override public init() {}

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
