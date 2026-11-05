import ShelfCore
import SwiftUI

/// A lava lamp: brass cap and base, a tapered glass vessel, and the `lavaLamp` shader inside it.
/// Tap to switch it off; the wax settles and the glow goes out.
struct LavaLampWidget: View {
    let context: WidgetContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    enum Palette: String, CaseIterable {
        case ember, moss, rose, honey
        var label: String {
            switch self {
            case .ember: "Ember on cream"
            case .moss: "Moss on brass"
            case .rose: "Rose on graphite"
            case .honey: "Honey on ember"
            }
        }
        /// Wax colour, then the liquid it floats in.
        var wax: Color {
            switch self {
            case .ember: Theme.ember
            case .moss: Theme.moss
            case .rose: Color(red: 0.89, green: 0.47, blue: 0.52)
            case .honey: Theme.brass
            }
        }
        var liquid: Color {
            switch self {
            case .ember: Theme.cream
            case .moss: Theme.brass
            case .rose: Color(white: 0.62)
            case .honey: Theme.ember
            }
        }
    }

    private var palette: Palette { Palette(rawValue: context.string("palette", "ember")) ?? .ember }
    private var isOn: Bool { context.bool("on", true) }
    /// A resting moment that reads well when frozen, offset per lamp so two lamps never match.
    private var restTime: Double { 40 + AmbientMotion.seed(from: context.id) * 300 }

    var body: some View {
        let lampHeight = context.size.height * 0.96
        let lampWidth = min(context.size.width * 0.9, lampHeight * 0.46)
        ZStack {
            glow(width: lampWidth)
            lamp(width: lampWidth, height: lampHeight)
        }
        .frame(width: context.size.width, height: context.size.height)
        .contentShape(.rect)
        .onTapGesture {
            Sounds.shared.play(.clack, volume: 0.5)
            context.update("on", .bool(!isOn))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Lava lamp")
        .accessibilityValue(isOn ? "On, \(palette.label)" : "Off")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isOn ? "Switches the lamp off" : "Switches the lamp on")
    }

    /// Warm light thrown on the wall behind the lamp.
    private func glow(width: CGFloat) -> some View {
        Ellipse()
            .fill(RadialGradient(colors: [palette.wax.opacity(0.42), palette.wax.opacity(0)], center: .center, startRadius: 0, endRadius: width * 0.95))
            .frame(width: width * 2.0, height: context.size.height * 0.9)
            .opacity(isOn ? 1 : 0)
            .animation(.easeInOut(duration: 1.2), value: isOn)
            .allowsHitTesting(false)
    }

    private func lamp(width: CGFloat, height: CGFloat) -> some View {
        let capHeight = height * 0.14
        let glassHeight = height * 0.56
        let baseHeight = height * 0.30
        return VStack(spacing: 0) {
            LampCap()
                .fill(brassGradient)
                .overlay(LampCap().stroke(.black.opacity(0.25), lineWidth: 0.5))
                .frame(width: width * 0.42, height: capHeight)
            vessel(width: width * 0.80, height: glassHeight)
            LampBase()
                .fill(brassGradient)
                .overlay(alignment: .top) {
                    // Light leaking down onto the collar.
                    LampBase()
                        .fill(LinearGradient(colors: [palette.wax.opacity(isOn ? 0.55 : 0), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)))
                        .blendMode(.plusLighter)
                }
                .overlay(LampBase().stroke(.black.opacity(0.25), lineWidth: 0.5))
                .frame(width: width, height: baseHeight)
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 5)
    }

    private func vessel(width: CGFloat, height: CGFloat) -> some View {
        let glass = LampGlass(topRatio: 0.5)
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || !isOn)) { timeline in
            let t = reduceMotion || !isOn ? restTime : restTime + timeline.date.timeIntervalSince(start)
            Rectangle()
                .fill(.black)
                .colorEffect(ShaderLibrary.lavaLamp(.float2(width, height), .float(Float(t)), .color(palette.wax), .color(palette.liquid)))
        }
        .frame(width: width, height: height)
        .saturation(isOn ? 1 : 0.35)
        .brightness(isOn ? 0 : -0.22)
        .animation(.easeInOut(duration: 0.9), value: isOn)
        .clipShape(glass)
        .overlay {
            // Glass: a cool edge, one long highlight on the left and a fainter one on the right.
            ZStack {
                glass.stroke(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.12)], startPoint: .leading, endPoint: .trailing), lineWidth: 1)
                glass.fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0), location: 0.06),
                    .init(color: .white.opacity(0.30), location: 0.16),
                    .init(color: .white.opacity(0), location: 0.28),
                    .init(color: .white.opacity(0), location: 0.80),
                    .init(color: .white.opacity(0.10), location: 0.88),
                    .init(color: .white.opacity(0), location: 0.95),
                ], startPoint: .leading, endPoint: .trailing))
            }
            .allowsHitTesting(false)
        }
    }

    private var brassGradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: Color(red: 0.42, green: 0.30, blue: 0.15), location: 0),
            .init(color: Theme.brass, location: 0.28),
            .init(color: Color(red: 0.98, green: 0.86, blue: 0.62), location: 0.40),
            .init(color: Theme.brass, location: 0.55),
            .init(color: Color(red: 0.36, green: 0.25, blue: 0.12), location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }
}

/// Small truncated cone with a rounded crown.
nonisolated private struct LampCap: Shape {
    func path(in rect: CGRect) -> Path {
        let topInset = rect.width * 0.24
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + topInset, y: rect.minY + rect.height * 0.18))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - topInset, y: rect.minY + rect.height * 0.18),
                          control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.12))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The vessel: narrow at the cap, swelling gently to the collar.
nonisolated private struct LampGlass: Shape {
    var topRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let topHalf = rect.width * topRatio / 2
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - topHalf, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + topHalf, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY + rect.height * 0.55))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX - topHalf, y: rect.minY),
                          control: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY + rect.height * 0.55))
        path.closeSubpath()
        return path
    }
}

/// The base: a collar that pinches to a waist, then flares to the foot.
nonisolated private struct LampBase: Shape {
    func path(in rect: CGRect) -> Path {
        let collar = rect.width * 0.80 / 2
        let waist = rect.width * 0.56 / 2
        let waistY = rect.minY + rect.height * 0.36
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - collar, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + collar, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX + waist, y: waistY), control: CGPoint(x: rect.midX + collar * 0.98, y: rect.minY + rect.height * 0.24))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.06), control: CGPoint(x: rect.midX + waist * 0.92, y: rect.maxY - rect.height * 0.12))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.06), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX - waist, y: waistY), control: CGPoint(x: rect.midX - waist * 0.92, y: rect.maxY - rect.height * 0.12))
        path.addQuadCurve(to: CGPoint(x: rect.midX - collar, y: rect.minY), control: CGPoint(x: rect.midX - collar * 0.98, y: rect.minY + rect.height * 0.24))
        path.closeSubpath()
        return path
    }
}
