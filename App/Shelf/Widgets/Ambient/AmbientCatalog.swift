import ShelfCore
import SwiftUI

extension WidgetCatalog {
    static let ambientWidgets: [WidgetDescriptor] = [
        WidgetDescriptor(
            kind: "photoframe", name: "Photo Frame", summary: "Photos from a folder, drifting slowly and changing every few minutes.",
            symbol: "photo.on.rectangle.angled", category: .ambient, sizes: [.small, .medium, .large], defaultSize: .medium,
            defaultConfig: ["folder": .string("~/Pictures"), "interval": .number(5), "frame": .string("none")],
            options: [
                .text(key: "folder", label: "Folder", placeholder: "~/Pictures"),
                .number(key: "interval", label: "Minutes per photo", range: 1...60, step: 1),
                .choice(key: "frame", label: "Frame", options: [("none", "Full bleed"), ("polaroid", "Instant print")]),
            ],
            make: { AnyView(PhotoFrameWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "lavalamp", name: "Lava Lamp", summary: "Warm wax rising and falling in a glass. Tap it to switch it off.",
            symbol: "lamp.table", category: .ambient, sizes: [.small, .large], defaultSize: .small,
            defaultConfig: ["palette": .string("ember"), "on": .bool(true)],
            options: [
                .choice(key: "palette", label: "Colours", options: LavaLampWidget.Palette.allCases.map { ($0.rawValue, $0.label) }),
            ],
            isFreeform: true,
            make: { AnyView(LavaLampWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "ambient", name: "Ambient Sound", summary: "Rain, fire or soft noise to work to, made on the fly.",
            symbol: "cloud.rain", category: .ambient, sizes: [.small, .medium], defaultSize: .small,
            defaultConfig: ["sound": .string(AmbientSound.rain.rawValue), "volume": .number(0.5)],
            options: [
                .choice(key: "sound", label: "Sound", options: AmbientSound.allCases.map { ($0.rawValue, $0.label) }),
            ],
            make: { AnyView(AmbientSoundWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "quote", name: "Quote of the Day", summary: "A line from an old book, new each morning. Tap for another.",
            symbol: "quote.opening", category: .ambient, sizes: [.small, .medium, .large], defaultSize: .medium,
            make: { AnyView(QuoteWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "stickers", name: "Sticker", summary: "A die-cut sticker for your desktop. Poke it.",
            symbol: "star.square.on.square", category: .ambient, sizes: [.small], defaultSize: .small,
            defaultConfig: ["symbol": .string("star.fill"), "color": .string("ember"), "image": .string("")],
            options: [
                .text(key: "symbol", label: "Symbol", placeholder: "star.fill"),
                .choice(key: "color", label: "Colour", options: StickersWidget.Ink.allCases.map { ($0.rawValue, $0.label) }),
                .text(key: "image", label: "Image file (optional)", placeholder: "~/Pictures/sticker.png"),
            ],
            isFreeform: true,
            make: { AnyView(StickersWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "life", name: "Life", summary: "Conway's Game of Life, quietly glowing away.",
            symbol: "circle.grid.3x3", category: .ambient, sizes: [.small, .medium, .large], defaultSize: .medium,
            make: { AnyView(LifeWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "deskbuddy", name: "Desk Buddy", summary: "A small round friend who watches your cursor and naps at night.",
            symbol: "face.smiling", category: .ambient, sizes: [.small], defaultSize: .small,
            defaultConfig: ["coat": .string("cream")],
            options: [
                .choice(key: "coat", label: "Colour", options: DeskBuddyWidget.Coat.allCases.map { ($0.rawValue, $0.label) }),
            ],
            isFreeform: true,
            make: { AnyView(DeskBuddyWidget(context: $0)) }
        ),
    ]
}
