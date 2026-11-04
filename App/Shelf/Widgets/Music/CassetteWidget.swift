import ShelfCore
import SwiftUI

/// A cassette whose tape moves from one reel to the other as the track plays. Tape runs at a constant
/// speed, so the fuller reel turns slower: angle = (2v/b)(√(r₀² + bt) − r₀) for a linearly growing pack area.
struct CassetteWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model

    private var shellColor: Color {
        switch context.string("shell", "smoke") {
        case "clear": Color(white: 0.92).opacity(0.55)
        case "orange": Color(red: 0.95, green: 0.48, blue: 0.2)
        default: Color(white: 0.12).opacity(0.9)
        }
    }

    var body: some View {
        let nowPlaying = model.nowPlaying
        let size = context.size
        let w = min(size.width, size.height * 1.58)
        let h = w / 1.58
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !nowPlaying.isPlaying)) { timeline in
            let clock = nowPlaying.clock
            let position = clock.position(at: timeline.date)
            let duration = max(clock.duration ?? 240, 1)
            let progress = min(1, position / duration)
            ZStack {
                RoundedRectangle(cornerRadius: h * 0.07, style: .continuous)
                    .fill(shellColor)
                    .overlay(RoundedRectangle(cornerRadius: h * 0.07, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))
                label(width: w * 0.86, height: h * 0.6)
                    .offset(y: -h * 0.1)
                HStack(spacing: w * 0.2) {
                    reel(radius: h * 0.17, pack: pack(1 - progress, h), angle: reelAngle(time: position, duration: duration, unwinding: true, h: h))
                    reel(radius: h * 0.17, pack: pack(progress, h), angle: reelAngle(time: position, duration: duration, unwinding: false, h: h))
                }
                .background(RoundedRectangle(cornerRadius: h * 0.09, style: .continuous).fill(Color.black.opacity(0.55)).frame(width: w * 0.62, height: h * 0.38))
                .offset(y: h * 0.05)
                Trapezoid()
                    .fill(Color.black.opacity(0.35))
                    .frame(width: w * 0.56, height: h * 0.2)
                    .offset(y: h * 0.4)
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Circle().fill(Color.black.opacity(0.5)).frame(width: h * 0.05).offset(x: side * w * 0.43, y: h * 0.4)
                }
            }
            .frame(width: w, height: h)
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        }
        .frame(width: size.width, height: size.height)
        .onTapGesture { nowPlaying.playPause() }
        .accessibilityElement()
        .accessibilityLabel(nowPlaying.track.map { "Cassette, \($0.title)" } ?? "Cassette, nothing playing")
        .accessibilityAddTraits(.isButton)
    }

    private func pack(_ fraction: Double, _ h: CGFloat) -> CGFloat {
        let minR = h * 0.065, maxR = h * 0.155
        return sqrt(minR * minR + (maxR * maxR - minR * minR) * fraction)
    }

    private func reelAngle(time: Double, duration: Double, unwinding: Bool, h: CGFloat) -> Double {
        let minR = Double(h) * 0.065, maxR = Double(h) * 0.155
        let b = (maxR * maxR - minR * minR) / duration
        let v = 2 * .pi * maxR / 2.2  // tape speed: a full reel turns about every 2.2 s
        let t = min(time, duration)
        let radians = unwinding
            ? (2 * v / b) * (maxR - sqrt(max(0, maxR * maxR - b * t)))
            : (2 * v / b) * (sqrt(minR * minR + b * t) - minR)
        return radians * 180 / .pi
    }

    private func label(width: CGFloat, height: CGFloat) -> some View {
        let track = model.nowPlaying.track
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(Text(track?.title ?? "Mixtape").font(.custom("Noteworthy-Bold", size: height * 0.17)))   \(Text(track?.artist ?? "Side A").font(.custom("Noteworthy-Light", size: height * 0.12)).foregroundStyle(.secondary))")
                .lineLimit(1)
            Spacer()
        }
        .foregroundStyle(Color(red: 0.12, green: 0.14, blue: 0.3))
        .padding(.horizontal, width * 0.06)
        .padding(.top, height * 0.06)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Color(red: 0.98, green: 0.95, blue: 0.86), Color(red: 0.95, green: 0.9, blue: 0.78)], startPoint: .top, endPoint: .bottom),
            in: .rect(cornerRadius: 4)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.ember.opacity(0.85)).frame(height: height * 0.05).padding(.top, height * 0.3)
        }
    }

    private func reel(radius: CGFloat, pack: CGFloat, angle: Double) -> some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.65)).frame(width: radius * 2.2)
            Circle().fill(Color(red: 0.24, green: 0.16, blue: 0.12)).frame(width: pack * 2)
            ZStack {
                Circle().fill(Color(white: 0.92)).frame(width: radius * 0.72)
                ForEach(0..<6) { i in
                    Capsule().fill(Color(white: 0.3)).frame(width: radius * 0.08, height: radius * 0.22)
                        .offset(y: -radius * 0.22).rotationEffect(.degrees(Double(i) * 60))
                }
            }
            .rotationEffect(.degrees(angle))
        }
    }
}

nonisolated private struct Trapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
