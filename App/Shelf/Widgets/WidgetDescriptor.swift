import ShelfCore
import SwiftUI

enum WidgetCategory: String, CaseIterable, Identifiable {
    case music, time, info, productivity, ambient
    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: "Music"
        case .time: "Time"
        case .info: "Info"
        case .productivity: "Productivity"
        case .ambient: "Ambient"
        }
    }

    var symbol: String {
        switch self {
        case .music: "music.note"
        case .time: "clock"
        case .info: "gauge.with.dots.needle.33percent"
        case .productivity: "checklist"
        case .ambient: "sparkles"
        }
    }
}

enum WidgetPermission: String, Hashable {
    case automation, calendar, reminders, location, photos
}

/// A setting a widget exposes; the inspector renders these generically.
enum WidgetOption {
    case choice(key: String, label: String, options: [(value: String, label: String)])
    case toggle(key: String, label: String)
    case text(key: String, label: String, placeholder: String)
    case number(key: String, label: String, range: ClosedRange<Double>, step: Double)
    case date(key: String, label: String)
}

/// What a widget view gets: its config, its size, and whether the wall is in edit mode.
struct WidgetContext {
    let id: UUID
    let config: WidgetConfig
    let size: CGSize
    let isEditing: Bool
    let update: (String, ConfigValue) -> Void

    func string(_ key: String, _ fallback: String) -> String { config.string(key, default: fallback) ?? fallback }
    func double(_ key: String, _ fallback: Double) -> Double { config.double(key, default: fallback) ?? fallback }
    func bool(_ key: String, _ fallback: Bool) -> Bool { config.bool(key, default: fallback) ?? fallback }

    /// Smallest side, for scaling type and artwork.
    var unit: CGFloat { min(size.width, size.height) }
    var isWide: Bool { size.width > size.height * 1.4 }
    var isTall: Bool { size.height > size.width * 1.3 }
}

struct WidgetDescriptor: Identifiable {
    let kind: String
    let name: String
    let summary: String
    let symbol: String
    let category: WidgetCategory
    var sizes: [WidgetSize] = [.small, .medium, .large]
    var defaultSize: WidgetSize = .small
    var defaultConfig: WidgetConfig = [:]
    var permissions: Set<WidgetPermission> = []
    var options: [WidgetOption] = []
    /// Draws its own body (turntable, click wheel) instead of sitting on a glass card.
    var isFreeform = false
    let make: (WidgetContext) -> AnyView

    var id: String { kind }
}
