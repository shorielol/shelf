import ShelfCore
import SwiftUI

extension WidgetCatalog {
    static let productivityWidgets: [WidgetDescriptor] = [
        WidgetDescriptor(
            kind: "calendar", name: "Calendar", summary: "Today's date and what's on, with the month at large size.",
            symbol: "calendar", category: .productivity, sizes: [.small, .medium, .large], defaultSize: .large,
            permissions: [.calendar],
            make: { AnyView(CalendarWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "upnext", name: "Up Next", summary: "Your next event, counting down, with a Join button for calls.",
            symbol: "clock.badge", category: .productivity, sizes: [.small, .medium], defaultSize: .medium,
            permissions: [.calendar],
            make: { AnyView(UpNextWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "reminders", name: "Reminders", summary: "Open reminders you can tick off right from the desktop.",
            symbol: "checklist", category: .productivity, sizes: [.medium, .large], defaultSize: .large,
            defaultConfig: ["list": .string("")],
            permissions: [.reminders],
            options: [.text(key: "list", label: "List", placeholder: "All lists")],
            make: { AnyView(RemindersWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "sticky", name: "Sticky Note", summary: "A paper note for whatever's on your mind. Supports bold, italics and bullets.",
            symbol: "note.text", category: .productivity, sizes: [.small, .medium, .large], defaultSize: .small,
            defaultConfig: [
                "paper": .string("butter"),
                "tilt": .bool(true),
                "text": .string("**Today**\n- Reply to Sam\n- Pick up film\n_one thing at a time_"),
            ],
            options: [
                .choice(key: "paper", label: "Paper", options: StickyWidget.Paper.allCases.map { ($0.rawValue, $0.label) }),
                .toggle(key: "tilt", label: "Slight tilt"),
            ],
            isFreeform: true,
            make: { AnyView(StickyWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "habits", name: "Habit Grid", summary: "Up to three habits, one square a day. Keep the streak going.",
            symbol: "square.grid.3x3.fill", category: .productivity, sizes: [.medium, .large], defaultSize: .medium,
            defaultConfig: ["habits": .string("Read, Move, Write")],
            options: [.text(key: "habits", label: "Habits", placeholder: "Read, Move, Write")],
            make: { AnyView(HabitsWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "dayprogress", name: "Day Progress", summary: "How much of the day, week, month and year is behind you.",
            symbol: "chart.bar.fill", category: .productivity, sizes: [.small, .medium], defaultSize: .small,
            make: { AnyView(DayProgressWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "launcher", name: "Launcher", summary: "A little dock for the apps, folders and links you open most.",
            symbol: "square.grid.2x2", category: .productivity, sizes: [.small, .medium], defaultSize: .medium,
            defaultConfig: ["items": .string(LauncherWidget.defaultItems)],
            options: [.text(key: "items", label: "Items", placeholder: "Safari, Notes, ~/Downloads, https://…")],
            make: { AnyView(LauncherWidget(context: $0)) }
        ),
    ]
}
