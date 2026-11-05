import ShelfCore
import SwiftUI

extension WidgetCatalog {
    static let infoWidgets: [WidgetDescriptor] = [
        WidgetDescriptor(
            kind: "weather", name: "Weather", summary: "The sky where you are, with the next few hours and days.",
            symbol: "cloud.sun", category: .info, sizes: [.small, .medium, .large], defaultSize: .small,
            defaultConfig: ["city": .string(""), "unit": .string(Locale.current.measurementSystem == .us ? "f" : "c")],
            permissions: [.location],
            options: [
                .text(key: "city", label: "City", placeholder: "Current location"),
                .choice(key: "unit", label: "Units", options: [("c", "Celsius"), ("f", "Fahrenheit")]),
            ],
            make: { AnyView(WeatherWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "sunmoon", name: "Sun & Moon", summary: "Where the sun is on today's arc, and what the moon is doing tonight.",
            symbol: "sun.horizon", category: .info, sizes: [.small, .medium, .large], defaultSize: .medium,
            defaultConfig: ["city": .string("")],
            permissions: [.location],
            options: [.text(key: "city", label: "City", placeholder: "Current location")],
            make: { AnyView(SunMoonWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "system", name: "System Monitor", summary: "CPU, memory and disk at a glance, with recent history.",
            symbol: "cpu", category: .info, sizes: [.small, .medium, .large], defaultSize: .small,
            make: { AnyView(SystemWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "battery", name: "Battery", summary: "Charge level, time left and how your battery is ageing.",
            symbol: "battery.75percent", category: .info, sizes: [.small, .medium], defaultSize: .small,
            make: { AnyView(BatteryWidget(context: $0)) }
        ),
        WidgetDescriptor(
            kind: "network", name: "Network", summary: "Download and upload speeds as they happen.",
            symbol: "arrow.up.arrow.down", category: .info, sizes: [.small, .medium], defaultSize: .small,
            make: { AnyView(NetworkWidget(context: $0)) }
        ),
    ]
}
