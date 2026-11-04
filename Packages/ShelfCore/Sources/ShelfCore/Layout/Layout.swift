import Foundation

/// A JSON value for per-widget settings, so each widget owns its own config shape.
public enum ConfigValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case strings([String])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .strings(try container.decode([String].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .strings(let value): try container.encode(value)
        }
    }
}

public typealias WidgetConfig = [String: ConfigValue]

extension Dictionary where Key == String, Value == ConfigValue {
    public func string(_ key: String, default fallback: String? = nil) -> String? {
        if case .string(let value)? = self[key] { return value }
        return fallback
    }

    public func double(_ key: String, default fallback: Double? = nil) -> Double? {
        if case .number(let value)? = self[key] { return value }
        return fallback
    }

    public func bool(_ key: String, default fallback: Bool? = nil) -> Bool? {
        if case .bool(let value)? = self[key] { return value }
        return fallback
    }

    public func strings(_ key: String) -> [String] {
        if case .strings(let value)? = self[key] { return value }
        return []
    }
}

public struct WidgetInstance: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var kind: String
    public var frame: Rect
    public var display: DisplayKey
    public var config: WidgetConfig
    public var isLocked: Bool

    public init(id: UUID = UUID(), kind: String, frame: Rect, display: DisplayKey, config: WidgetConfig = [:], isLocked: Bool = false) {
        self.id = id
        self.kind = kind
        self.frame = frame
        self.display = display
        self.config = config
        self.isLocked = isLocked
    }
}

/// Everything on the desktop. Mutations return a new layout.
public struct WallLayout: Codable, Hashable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var widgets: [WidgetInstance]

    public init(widgets: [WidgetInstance] = []) {
        self.version = Self.currentVersion
        self.widgets = widgets
    }

    public func adding(_ widget: WidgetInstance) -> WallLayout {
        WallLayout(widgets: widgets + [widget])
    }

    public func removing(id: UUID) -> WallLayout {
        WallLayout(widgets: widgets.filter { $0.id != id })
    }

    public func updating(id: UUID, _ change: (inout WidgetInstance) -> Void) -> WallLayout {
        WallLayout(widgets: widgets.map { widget in
            guard widget.id == id else { return widget }
            var copy = widget
            change(&copy)
            return copy
        })
    }

    /// Widgets whose display isn't connected are shown on the main display (their saved display is kept).
    public func placement(connected: [DisplayKey], main: DisplayKey) -> [WidgetInstance] {
        let available = Set(connected)
        return widgets.map { widget in
            guard !available.contains(widget.display) else { return widget }
            var moved = widget
            moved.display = main
            return moved
        }
    }
}
