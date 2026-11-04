import AppKit
import SwiftUI

/// A few colours pulled from the album art; they tint glass, labels and the LCD.
nonisolated struct ArtworkPalette: Equatable, Sendable {
    var primary: Color
    var secondary: Color
    var accent: Color
    var isDark: Bool

    static let fallback = ArtworkPalette(primary: Theme.graphiteRaised, secondary: Theme.graphite, accent: Theme.ember, isDark: true)

    var mesh: [Color] {
        [primary, secondary, accent, secondary, primary, accent, accent, primary, secondary]
    }

    /// Downsamples to 24x24 and buckets the pixels; runs off the main actor.
    @concurrent
    static func extract(from image: NSImage) async -> ArtworkPalette {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .fallback }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .fallback }

        var buckets: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        var luminance = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            luminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
            let key = Int(r * 5) * 36 + Int(g * 5) * 6 + Int(b * 5)
            let entry = buckets[key, default: (0, 0, 0, 0)]
            buckets[key] = (entry.count + 1, entry.r + r, entry.g + g, entry.b + b)
        }
        let ranked = buckets.values.sorted { $0.count > $1.count }.map { e in
            (r: e.r / Double(e.count), g: e.g / Double(e.count), b: e.b / Double(e.count))
        }
        func color(_ c: (r: Double, g: Double, b: Double)) -> Color { Color(red: c.r, green: c.g, blue: c.b) }
        func saturation(_ c: (r: Double, g: Double, b: Double)) -> Double { (max(c.r, c.g, c.b) - min(c.r, c.g, c.b)) }
        guard let first = ranked.first else { return .fallback }
        let second = ranked.dropFirst().first ?? first
        let accent = ranked.prefix(8).max { saturation($0) < saturation($1) } ?? second
        return ArtworkPalette(primary: color(first), secondary: color(second), accent: color(accent),
                              isDark: luminance / Double(side * side) < 0.5)
    }
}
