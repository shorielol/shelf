import Foundation

/// A display, recognised by name and size so it's found again after being unplugged.
public struct DisplayKey: Codable, Hashable, Sendable {
    public let name: String
    public let width: Int
    public let height: Int

    public init(name: String, width: Int, height: Int) {
        self.name = name
        self.width = width
        self.height = height
    }
}

/// Codable rectangle in display-local points, origin at the display's top-left.
public struct Rect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

/// The system widget grid sizes, so Shelf widgets line up with native ones.
public enum WidgetSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large, extraLarge

    public var side: (width: Double, height: Double) {
        switch self {
        case .small: (170, 170)
        case .medium: (364, 170)
        case .large: (364, 382)
        case .extraLarge: (750, 382)
        }
    }

    public var label: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }

    public static func nearest(to size: (width: Double, height: Double), among options: [WidgetSize]) -> WidgetSize? {
        options.min { lhs, rhs in
            distance(lhs.side, size) < distance(rhs.side, size)
        }
    }

    private static func distance(_ a: (width: Double, height: Double), _ b: (width: Double, height: Double)) -> Double {
        let dx = a.width - b.width, dy = a.height - b.height
        return dx * dx + dy * dy
    }
}

/// Snaps frames to a grid and keeps them on screen.
public struct GridSnapper: Sendable {
    public let step: Double
    public let margin: Double
    public let minimumSide: Double

    public init(step: Double = 8, margin: Double = 16, minimumSide: Double = 80) {
        self.step = step
        self.margin = margin
        self.minimumSide = minimumSide
    }

    public func snap(_ rect: Rect, in bounds: Rect) -> Rect {
        // Only the position snaps; sizes stay exact so widgets keep the system widget dimensions.
        let width = max(minimumSide, rect.width)
        let height = max(minimumSide, rect.height)
        let x = bounds.x + round((rect.x - bounds.x) / step) * step
        let y = bounds.y + round((rect.y - bounds.y) / step) * step
        let clampedX = min(max(x, bounds.x + margin), bounds.maxX - margin - width)
        let clampedY = min(max(y, bounds.y + margin), bounds.maxY - margin - height)
        return Rect(x: max(bounds.x, clampedX), y: max(bounds.y, clampedY), width: width, height: height)
    }
}
