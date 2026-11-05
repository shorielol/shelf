import AppKit
import EventKit
import Observation
import os
import SwiftUI

/// An incomplete reminder copied out of EventKit.
nonisolated struct ReminderItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let due: Date?
    let listTitle: String
    let color: Color
    let isFlagged: Bool
}

/// Incomplete reminders, kept fresh from the shared event store.
@Observable
final class RemindersStore {
    static let shared = RemindersStore()

    private(set) var access = EventKitAccess(EKEventStore.authorizationStatus(for: .reminder))
    private(set) var items: [ReminderItem] = []
    private(set) var listTitles: [String] = []
    private(set) var hasLoaded = false

    @ObservationIgnored private var eventStore: EKEventStore { CalendarStore.shared.eventStore }
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private static let logger = Logger(subsystem: "app.shelf", category: "reminders")

    private init() {}

    func activate() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    func requestAccess() {
        if access == .denied {
            PrivacySettings.open("Privacy_Reminders")
            return
        }
        Task {
            do {
                _ = try await eventStore.requestFullAccessToReminders()
            } catch {
                Self.logger.error("Reminders access request failed: \(error.localizedDescription, privacy: .public)")
            }
            reload()
        }
    }

    func reload() {
        access = EventKitAccess(EKEventStore.authorizationStatus(for: .reminder))
        guard access == .granted else {
            items = []
            return
        }
        listTitles = eventStore.calendars(for: .reminder).map(\.title).sorted()
        generation += 1
        let token = generation
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        Self.fetch(from: eventStore, matching: predicate) { [weak self] snapshot in
            Task { @MainActor in
                guard let self, token == self.generation else { return }
                self.items = snapshot.sorted(by: Self.order)
                self.hasLoaded = true
            }
        }
    }

    /// EventKit calls back on its own queue, so the snapshot is taken there, away from the main actor.
    private nonisolated static func fetch(from store: EKEventStore, matching predicate: NSPredicate,
                                          completion: @escaping @Sendable ([ReminderItem]) -> Void) {
        store.fetchReminders(matching: predicate) { reminders in
            completion((reminders ?? []).map(snapshot))
        }
    }

    /// Marks a reminder done and writes it back to EventKit.
    func complete(_ id: String) {
        guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            Self.logger.error("Couldn't complete reminder: \(error.localizedDescription, privacy: .public)")
            reload()
        }
    }

    // MARK: Snapshot

    private nonisolated static func snapshot(_ reminder: EKReminder) -> ReminderItem {
        let due = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
        let color = reminder.calendar.flatMap { NSColor(cgColor: $0.cgColor) }.map { Color(nsColor: $0) } ?? Color.orange
        let title = reminder.title ?? ""
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: title.isEmpty ? "Untitled" : title,
            due: due,
            listTitle: reminder.calendar?.title ?? "",
            color: color,
            isFlagged: reminder.priority == 1
        )
    }

    /// Dated reminders first, soonest first; undated ones after, by title.
    private nonisolated static func order(_ lhs: ReminderItem, _ rhs: ReminderItem) -> Bool {
        switch (lhs.due, rhs.due) {
        case let (left?, right?): left < right
        case (.some, nil): true
        case (nil, .some): false
        case (nil, nil): lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
