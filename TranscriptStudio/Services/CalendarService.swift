import Foundation
import EventKit
import OSLog

private let logger = Logger(subsystem: "nl.prezent.TranscriptStudio", category: "CalendarService")

// MARK: - MeetingPlatform

enum MeetingPlatform: String, Sendable {
    case teams = "Microsoft Teams"
    case zoom  = "Zoom"
    case meet  = "Google Meet"
    case other = "Overig"

    /// SF Symbol name representing the platform.
    var iconName: String {
        switch self {
        case .teams: return "person.3.fill"
        case .zoom:  return "video.fill"
        case .meet:  return "video.circle.fill"
        case .other: return "calendar"
        }
    }
}

// MARK: - CalendarEvent

struct CalendarEvent: Identifiable, Sendable {
    let id: String
    let title: String
    let date: Date
    let endDate: Date
    let meetingURL: URL?
    let platform: MeetingPlatform
    let calendarTitle: String

    /// True if this event starts within the next `minutes` minutes.
    func startsWithin(minutes: Int) -> Bool {
        let threshold = Date().addingTimeInterval(TimeInterval(minutes * 60))
        return date <= threshold && date >= Date()
    }

    /// Human-readable Dutch start time.
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_NL")
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - CalendarService

/// Integrates with the device calendar to detect upcoming video meetings.
/// Supports local EventKit calendars and, on macOS, Microsoft 365 Exchange calendars.
@Observable
final class CalendarService: @unchecked Sendable {

    static let shared = CalendarService()

    // MARK: - Observable State

    private(set) var hasCalendarAccess: Bool = false
    private(set) var upcomingMeetings: [CalendarEvent] = []

    // MARK: - Private

    private let store = EKEventStore()

    // Meeting URL patterns used to detect video call links in event notes/location
    private static let teamsPattern  = #"https://teams\.microsoft\.com/[^\s"]+"#
    private static let zoomPattern   = #"https://[\w-]*\.?zoom\.us/[^\s"]+"#
    private static let meetPattern   = #"https://meet\.google\.com/[^\s"]+"#

    // MARK: - Init

    private init() {
        // Check existing authorization status without prompting
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14, iOS 17, *) {
            hasCalendarAccess = (status == .fullAccess)
        } else {
            hasCalendarAccess = (status == .authorized)
        }
    }

    // MARK: - Permission

    /// Requests calendar access from the user.
    func requestAccess() async {
        do {
            if #available(macOS 14, iOS 17, *) {
                let granted = try await store.requestFullAccessToEvents()
                await MainActor.run { self.hasCalendarAccess = granted }
                logger.info("CalendarService: full access granted = \(granted)")
            } else {
                let granted = try await store.requestAccess(to: .event)
                await MainActor.run { self.hasCalendarAccess = granted }
                logger.info("CalendarService: access granted = \(granted)")
            }

            if hasCalendarAccess {
                await fetchUpcomingMeetings()
            }
        } catch {
            await MainActor.run { self.hasCalendarAccess = false }
            logger.error("CalendarService: access request failed — \(error.localizedDescription)")
        }
    }

    // MARK: - Fetch Meetings

    /// Fetches upcoming meetings for the next 24 hours that contain a video meeting link.
    func fetchUpcomingMeetings() async {
        guard hasCalendarAccess else { return }

        let now = Date()
        let tomorrow = now.addingTimeInterval(24 * 60 * 60)

        let predicate = store.predicateForEvents(
            withStart: now,
            end: tomorrow,
            calendars: nil
        )

        let events = store.events(matching: predicate)
        logger.info("CalendarService: found \(events.count) events in next 24h")

        let meetings = events.compactMap { parseMeeting(from: $0) }
        let sorted = meetings.sorted { $0.date < $1.date }

        await MainActor.run {
            self.upcomingMeetings = sorted
        }

        logger.info("CalendarService: \(sorted.count) upcoming video meetings detected")
    }

    // MARK: - Parsing

    private func parseMeeting(from event: EKEvent) -> CalendarEvent? {
        // Collect all text fields to search for meeting URLs
        var searchText = ""
        if let notes = event.notes { searchText += notes + " " }
        if let location = event.location { searchText += location + " " }
        searchText += event.title ?? ""

        // Also check URL field if present
        let urlString: String? = event.url?.absoluteString

        let (meetingURL, platform) = detectMeeting(in: searchText, fallbackURLString: urlString)

        // Only include events that have a detectable meeting link
        // OR events with "Teams", "Zoom", "Meet" keywords in the title
        let titleLower = (event.title ?? "").lowercased()
        let isMeetingByTitle = titleLower.contains("teams") ||
                               titleLower.contains("zoom") ||
                               titleLower.contains("google meet") ||
                               titleLower.contains("vergadering") ||
                               titleLower.contains("meeting")

        guard meetingURL != nil || isMeetingByTitle else { return nil }

        return CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Vergadering",
            date: event.startDate,
            endDate: event.endDate,
            meetingURL: meetingURL,
            platform: platform,
            calendarTitle: event.calendar?.title ?? ""
        )
    }

    private func detectMeeting(
        in text: String,
        fallbackURLString: String?
    ) -> (URL?, MeetingPlatform) {
        // Check Teams
        if let url = firstMatch(pattern: Self.teamsPattern, in: text) {
            return (URL(string: url), .teams)
        }
        // Check Zoom
        if let url = firstMatch(pattern: Self.zoomPattern, in: text) {
            return (URL(string: url), .zoom)
        }
        // Check Google Meet
        if let url = firstMatch(pattern: Self.meetPattern, in: text) {
            return (URL(string: url), .meet)
        }

        // Fallback: classify by URL string content
        if let urlString = fallbackURLString {
            let lower = urlString.lowercased()
            if lower.contains("teams.microsoft.com") {
                return (URL(string: urlString), .teams)
            } else if lower.contains("zoom.us") {
                return (URL(string: urlString), .zoom)
            } else if lower.contains("meet.google.com") {
                return (URL(string: urlString), .meet)
            }
        }

        return (nil, .other)
    }

    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else {
            return nil
        }
        return String(text[swiftRange])
    }
}
