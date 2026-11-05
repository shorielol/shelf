import AppKit
import EventKit
import Observation
import os
import SwiftUI

/// A calendar event copied out of EventKit so views never hold on to `EKEvent`.
struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let calendarTitle: String
    let location: String?
    let meetingURL: URL?

    func isHappening(at date: Date) -> Bool { start <= date && date < end }
}

/// Where Shelf stands with an EventKit entity type.
enum EventKitAccess: Equatable {
    case notDetermined, granted, denied

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .fullAccess: self = .granted
        case .notDetermined: self = .notDetermined
        default: self = .denied
        }
    }
}

/// One event store for the whole app. Calendar and Up Next read from it; Reminders shares its `EKEventStore`.
@Observable
final class CalendarStore {
    static let shared = CalendarStore()

    @ObservationIgnored let eventStore = EKEventStore()
    private(set) var access = EventKitAccess(EKEventStore.authorizationStatus(for: .event))
    /// The next 14 days, starting at midnight today, sorted by start.
    private(set) var events: [CalendarEvent] = []

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private static let logger = Logger(subsystem: "app.shelf", category: "calendar")
    private static let window = 14

    private init() {}

    /// Starts listening for changes. Safe to call from every widget's `onAppear`.
    func activate() {
        guard !isActive else { return }
        isActive = true
        let center = NotificationCenter.default
        for name in [Notification.Name.EKEventStoreChanged, .NSCalendarDayChanged] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reload() }
            })
        }
        reload()
    }

    func requestAccess() {
        if access == .denied {
            PrivacySettings.open("Privacy_Calendars")
            return
        }
        Task {
            do {
                _ = try await eventStore.requestFullAccessToEvents()
            } catch {
                Self.logger.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)")
            }
            reload()
        }
    }

    func reload() {
        access = EventKitAccess(EKEventStore.authorizationStatus(for: .event))
        guard access == .granted else {
            events = []
            return
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: Self.window, to: start) else { return }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = eventStore.events(matching: predicate)
            .filter { $0.status != .canceled && !Self.isDeclined($0) }
            .map(Self.snapshot)
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    // MARK: Queries

    func events(on day: Date) -> [CalendarEvent] {
        guard let interval = Calendar.current.dateInterval(of: .day, for: day) else { return [] }
        return events.filter { $0.start < interval.end && $0.end > interval.start }
    }

    /// The event happening now, or the next one to start. All-day events don't count.
    func nextEvent(after date: Date) -> CalendarEvent? {
        events.first { !$0.isAllDay && $0.end > date }
    }

    /// Days in the loaded window that have at least one event, as start-of-day dates.
    func busyDays() -> Set<Date> {
        let calendar = Calendar.current
        var days = Set<Date>()
        for event in events {
            var day = calendar.startOfDay(for: event.start)
            while day < event.end {
                days.insert(day)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }
        return days
    }

    // MARK: Snapshot

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
    }

    private static func snapshot(_ event: EKEvent) -> CalendarEvent {
        let color = event.calendar.flatMap { NSColor(cgColor: $0.cgColor) }.map { Color(nsColor: $0) } ?? Theme.ember
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = event.title ?? ""
        return CalendarEvent(
            id: (event.eventIdentifier ?? UUID().uuidString) + "@\(event.startDate.timeIntervalSince1970)",
            title: title.isEmpty ? "Untitled" : title,
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            color: color,
            calendarTitle: event.calendar?.title ?? "",
            location: location?.isEmpty == false ? location : nil,
            meetingURL: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
        )
    }
}

/// Finds a video-call link in free text.
enum MeetingLink {
    private static let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func find(in fields: [String?]) -> URL? {
        for case let text? in fields where !text.isEmpty {
            if let url = firstMeetingURL(in: text) { return url }
        }
        return nil
    }

    static func isMeeting(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func firstMeetingURL(in text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, range: range) ?? []
        return matches.lazy.compactMap(\.url).first(where: isMeeting)
    }
}

enum PrivacySettings {
    static func open(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Short, human time strings shared by the calendar widgets.
enum EventTime {
    static func clock(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    static func range(_ event: CalendarEvent) -> String {
        event.isAllDay ? "All day" : "\(clock(event.start)) – \(clock(event.end))"
    }

    /// "in 12 min", "in 1 h 5 min", "now", "tomorrow 9:00".
    static func relative(to event: CalendarEvent, from now: Date) -> String {
        if event.isHappening(at: now) { return "now" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes) min" }
        let calendar = Calendar.current
        if minutes < 12 * 60 || calendar.isDate(event.start, inSameDayAs: now) {
            let hours = minutes / 60, rest = minutes % 60
            return rest == 0 ? "in \(hours) h" : "in \(hours) h \(rest) min"
        }
        if calendar.isDateInTomorrow(event.start) { return "tomorrow \(clock(event.start))" }
        return event.start.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

/// The permission prompt both calendar widgets show.
struct CalendarAccessPlaceholder: View {
    let store: CalendarStore
    var compact = false

    var body: some View {
        WidgetPlaceholder(
            symbol: "calendar",
            title: compact ? "Calendar" : "Your day, at a glance",
            detail: store.access == .denied ? "Turn on Shelf in Privacy & Security." : (compact ? nil : "Shelf reads events to show what's next."),
            action: (store.access == .denied ? "Open Settings" : "Allow Calendar", { store.requestAccess() })
        )
    }
}
