import ShelfCore
import SwiftUI

extension WidgetCatalog {
    static let timeWidgets: [WidgetDescriptor] = [
        WidgetDescriptor(
            kind: "flipclock", name: "Flip Clock", summary: "Split-flap cards that fold over on a hinge when the minute turns.",
            symbol: "clock.badge", category: .time, sizes: [.small, .medium, .large], defaultSize: .medium,
            defaultConfig: ["finish": .string("graphite"), "24h": .bool(false), "seconds": .bool(false), "sound": .bool(false)],
            options: [
                .choice(key: "finish", label: "Cards", options: FlipClockWidget.Finish.allCases.map { ($0.rawValue, $0.label) }),
                .toggle(key: "24h", label: "24-hour time"),
                .toggle(key: "seconds", label: "Show seconds"),
                .toggle(key: "sound", label: "Clack on the minute"),
            ],
            make: { AnyView(FlipClockWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "analogclock", name: "Analog Clock", summary: "A wall clock with a clean, station or Bauhaus face.",
            symbol: "clock", category: .time, sizes: [.small, .large], defaultSize: .small,
            defaultConfig: ["face": .string("minimal"), "seconds": .bool(true)],
            options: [
                .choice(key: "face", label: "Face", options: AnalogClockWidget.Face.allCases.map { ($0.rawValue, $0.label) }),
                .toggle(key: "seconds", label: "Seconds hand"),
            ],
            make: { AnyView(AnalogClockWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "worldclock", name: "World Clocks", summary: "Times in other cities, with where the sun is for each.",
            symbol: "globe", category: .time, sizes: [.small, .medium, .large], defaultSize: .medium,
            defaultConfig: ["zones": .string(WorldClockWidget.defaultZones)],
            options: [.text(key: "zones", label: "Cities", placeholder: "Tokyo, Europe/Paris, NYC")],
            make: { AnyView(WorldClockWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "wordclock", name: "Word Clock", summary: "The time spelled out in letters, to the nearest five minutes.",
            symbol: "textformat.abc", category: .time, sizes: [.small, .large], defaultSize: .small,
            defaultConfig: ["glow": .string("cream")],
            options: [.choice(key: "glow", label: "Letters", options: [("cream", "Warm white"), ("ember", "Ember")])],
            make: { AnyView(WordClockWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "countdown", name: "Countdown", summary: "Days left until something you're looking forward to.",
            symbol: "calendar.badge.clock", category: .time, sizes: [.small, .medium], defaultSize: .small,
            defaultConfig: ["title": .string("Launch"), "style": .string("ring")],
            options: [
                .text(key: "title", label: "Event", placeholder: "Launch"),
                .date(key: "target", label: "Date"),
                .choice(key: "style", label: "Style", options: CountdownWidget.Style.allCases.map { ($0.rawValue, $0.label) }),
            ],
            make: { AnyView(CountdownWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "focustimer", name: "Focus Timer", summary: "Work and break rounds, or a plain stopwatch.",
            symbol: "timer", category: .time, sizes: [.small, .medium], defaultSize: .small,
            defaultConfig: ["mode": .string("timer"), "work": .number(25), "break": .number(5)],
            options: [
                .choice(key: "mode", label: "Mode", options: [("timer", "Focus timer"), ("stopwatch", "Stopwatch")]),
                .number(key: "work", label: "Focus minutes", range: 5...90, step: 5),
                .number(key: "break", label: "Break minutes", range: 1...30, step: 1),
            ],
            make: { AnyView(FocusTimerWidget(context: $0)) }
        ),
    ]
}
