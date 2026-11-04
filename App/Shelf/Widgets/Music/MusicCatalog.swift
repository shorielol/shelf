import ShelfCore
import SwiftUI

extension WidgetCatalog {
    static let musicWidgets: [WidgetDescriptor] = [
        WidgetDescriptor(
            kind: "turntable", name: "Turntable", summary: "A record player that spins with your music. Drag the tonearm to seek.",
            symbol: "opticaldisc", category: .music, sizes: [.medium, .large, .extraLarge], defaultSize: .large,
            defaultConfig: ["finish": .string("walnut"), "speed": .string("33"), "lyrics": .bool(true)],
            permissions: [.automation],
            options: [
                .choice(key: "finish", label: "Finish", options: TurntableWidget.Finish.allCases.map { ($0.rawValue, $0.label) }),
                .choice(key: "speed", label: "Speed", options: [("33", "33⅓ RPM"), ("45", "45 RPM")]),
                .toggle(key: "lyrics", label: "Show lyrics"),
            ],
            isFreeform: true,
            make: { AnyView(TurntableWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "clickwheel", name: "Click Wheel", summary: "A pocket player with a wheel you can actually spin.",
            symbol: "ipod", category: .music, sizes: [.small, .large], defaultSize: .large,
            defaultConfig: ["skin": .string("frost")],
            permissions: [.automation],
            options: [.choice(key: "skin", label: "Finish", options: [("frost", "Frost"), ("graphite", "Graphite"), ("cherry", "Cherry"), ("mint", "Mint")])],
            isFreeform: true,
            make: { AnyView(ClickWheelWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "lyrics", name: "Lyrics", summary: "Synced lyrics for Music and Spotify, lit word by word.",
            symbol: "quote.bubble", category: .music, sizes: [.medium, .large, .extraLarge], defaultSize: .large,
            permissions: [.automation],
            make: { AnyView(LyricsWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "cassette", name: "Cassette", summary: "Tape moves reel to reel as the song plays.",
            symbol: "recordingtape", category: .music, sizes: [.small, .medium], defaultSize: .medium,
            defaultConfig: ["shell": .string("smoke")],
            permissions: [.automation],
            options: [.choice(key: "shell", label: "Shell", options: [("smoke", "Smoke"), ("clear", "Clear"), ("orange", "Orange")])],
            isFreeform: true,
            make: { AnyView(CassetteWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "nowplaying", name: "Now Playing", summary: "Artwork, controls and a scrubber on the album's colours.",
            symbol: "play.square.stack", category: .music, sizes: [.small, .medium, .large], defaultSize: .medium,
            permissions: [.automation],
            make: { AnyView(NowPlayingWidget(context: $0)) }
        ),
    ]
}
