import ShelfCore
import SwiftUI

/// A die-cut vinyl sticker: an SF Symbol or an image with a thick white border and a soft shadow.
/// Poke it (or brush past it) and it squashes and springs back with a little twist.
struct StickersWidget: View {
    let context: WidgetContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pokes = 0
    @State private var kick = 0.0
    @State private var lastPoke = Date.distantPast
    @State private var image: CGImage?

    enum Ink: String, CaseIterable {
        case ember, brass, moss, sky, rose, graphite
        var label: String { rawValue.capitalized }
        var color: Color {
            switch self {
            case .ember: Theme.ember
            case .brass: Theme.brass
            case .moss: Theme.moss
            case .sky: Color(red: 0.40, green: 0.62, blue: 0.80)
            case .rose: Color(red: 0.89, green: 0.47, blue: 0.52)
            case .graphite: Theme.graphiteRaised
            }
        }
    }

    private var symbolName: String {
        let name = context.string("symbol", "star.fill").trimmingCharacters(in: .whitespaces)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil ? "star.fill" : name
    }
    private var ink: Ink { Ink(rawValue: context.string("color", "ember")) ?? .ember }
    private var imagePath: String { context.string("image", "").trimmingCharacters(in: .whitespaces) }
    /// Stickers never go on perfectly straight.
    private var restingTilt: Double { (AmbientMotion.seed(from: context.id) - 0.5) * 14 }

    var body: some View {
        sticker
            .keyframeAnimator(initialValue: Squish(), trigger: pokes) { content, squish in
                content
                    .scaleEffect(x: squish.width, y: squish.height, anchor: .bottom)
                    .rotationEffect(.degrees(squish.twist))
            } keyframes: { _ in
                KeyframeTrack(\.height) {
                    CubicKeyframe(0.86, duration: 0.09)
                    SpringKeyframe(1, duration: 0.7, spring: .init(response: 0.32, dampingRatio: 0.42))
                }
                KeyframeTrack(\.width) {
                    CubicKeyframe(1.12, duration: 0.09)
                    SpringKeyframe(1, duration: 0.7, spring: .init(response: 0.32, dampingRatio: 0.42))
                }
                KeyframeTrack(\.twist) {
                    CubicKeyframe(kick, duration: 0.12)
                    SpringKeyframe(0, duration: 0.9, spring: .init(response: 0.45, dampingRatio: 0.38))
                }
            }
            .rotationEffect(.degrees(restingTilt))
            .frame(width: context.size.width, height: context.size.height)
            .contentShape(.rect)
            .onTapGesture { poke(sound: true) }
            .onHover { inside in if inside { poke(sound: false) } }
            .task(id: imagePath) { await loadImage() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(image == nil ? "Sticker, \(symbolName.replacingOccurrences(of: ".", with: " "))" : "Sticker")
            .accessibilityAddTraits(.isButton)
    }

    private var sticker: some View {
        let side = context.unit * 0.64
        return DieCut(outline: max(4, side * 0.07)) {
            art(side: side)
        }
        .shadow(color: .black.opacity(0.32), radius: side * 0.05, y: side * 0.04)
        .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
    }

    @ViewBuilder
    private func art(side: CGFloat) -> some View {
        if let image {
            Image(decorative: image, scale: 2)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: side * 0.82, weight: .bold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(LinearGradient(colors: [ink.color.mix(with: .white, by: 0.18), ink.color], startPoint: .top, endPoint: .bottom))
                .frame(width: side, height: side)
        }
    }

    private func poke(sound: Bool) {
        let now = Date()
        guard !reduceMotion, now.timeIntervalSince(lastPoke) > 0.5 else { return }
        lastPoke = now
        kick = Double.random(in: 5...9) * (Bool.random() ? 1 : -1)
        pokes += 1
        if sound { Sounds.shared.play(.pop, volume: 0.45) }
    }

    private func loadImage() async {
        guard !imagePath.isEmpty else { image = nil; return }
        let url = PhotoLibrary.expand(imagePath)
        image = await PhotoLibrary.thumbnail(for: url, maxPixel: Int(context.unit * 2))?.image
    }

    /// White vinyl backing: the art's silhouette stamped in a ring around itself, flattened once.
    private struct DieCut<Art: View>: View {
        let outline: CGFloat
        @ViewBuilder var art: Art

        var body: some View {
            ZStack {
                ForEach(0..<16, id: \.self) { i in
                    let angle = Double(i) / 16 * 2 * .pi
                    silhouette.offset(x: cos(angle) * outline, y: sin(angle) * outline)
                }
                silhouette
                art
            }
            .padding(outline)
            .drawingGroup()
        }

        private var silhouette: some View { art.brightness(1) }
    }
}

/// Animated values for one poke.
nonisolated private struct Squish {
    var width = 1.0
    var height = 1.0
    var twist = 0.0
}
