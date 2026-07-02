// MeetingNotificationService.swift
// TranscriptStudio
// com.buildmind.ThoughtVault
//
// Schedules macOS Notification Center alerts for upcoming calendar meetings.
// When the user taps "Start opname", posts a Notification.Name to trigger recording.

import Foundation
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "com.buildmind.ThoughtVault", category: "MeetingNotifications")

extension Notification.Name {
    static let meetingRecordRequested = Notification.Name("meetingRecordRequested")
    static let videoCallDetected = Notification.Name("videoCallDetected")
}

final class MeetingNotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {

    static let shared = MeetingNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let categoryId = "MEETING_ALERT"
    private let recordActionId = "RECORD_ACTION"
    private let dismissActionId = "DISMISS_ACTION"
    private var scheduledEventIds: Set<String> = []

    private override init() {
        super.init()
    }

    // MARK: - Setup

    func setup() {
        center.delegate = self

        let recordAction = UNNotificationAction(
            identifier: recordActionId,
            title: "Start opname",
            options: [.foreground]
        )
        let dismissAction = UNNotificationAction(
            identifier: dismissActionId,
            title: "Negeren",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [recordAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestPermission() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification permission granted: \(granted)")
        } catch {
            logger.error("Notification permission failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Schedule

    func scheduleIfNeeded(for meeting: CalendarEvent) async {
        guard !scheduledEventIds.contains(meeting.id) else { return }
        scheduledEventIds.insert(meeting.id)

        let content = UNMutableNotificationContent()
        content.title = meeting.title
        content.body = "Begint om \(meeting.formattedTime) \u{00b7} \(meeting.platform.rawValue)"
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = ["eventId": meeting.id]

        let triggerDate = meeting.date.addingTimeInterval(-5 * 60)
        let timeInterval = triggerDate.timeIntervalSinceNow

        let trigger: UNNotificationTrigger?
        if timeInterval <= 0 {
            // Already within 5 minutes — send immediately
            trigger = nil
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
        }

        let request = UNNotificationRequest(
            identifier: "meeting-\(meeting.id)",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            logger.info("Scheduled notification for '\(meeting.title)' at \(triggerDate)")
        } catch {
            logger.error("Failed to schedule notification: \(error.localizedDescription)")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Show notification banner even when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound]
    }

    // Handle notification actions
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionId = response.actionIdentifier

        if actionId == recordActionId || actionId == UNNotificationDefaultActionIdentifier {
            // User tapped "Start opname" or tapped the notification itself
            await MainActor.run {
                NotificationCenter.default.post(name: .meetingRecordRequested, object: nil)
            }
        }
    }
}
