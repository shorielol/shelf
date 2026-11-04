import ShelfCore
import SwiftUI

/// Top-down record player. The platter angle comes from playback position, the tonearm tracks progress,
/// and pausing spins the record down instead of stopping dead.
struct TurntableWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var armDrag: Double?
    @State private var wasPlaying = false

    private var finish: Finish { Finish(rawValue: context.string("finish", "walnut")) ?? .walnut }
    private var rpm: Double { context.string("speed", "33") == "45" ? 45 : 100.0 / 3.0 }
    private var showsLyrics: Bool { context.bool("lyrics", true) && context.size.height >= 300 }

    enum Finish: String, CaseIterable {
        case walnut, smoke, chalk
        var label: String { ["walnut": "Walnut", "smoke": "Smoked Acrylic", "chalk": "Matte White"][rawValue]! }
    }

    var body: some View {
        let nowPlaying = model.nowPlaying
        let side = min(context.size.width, context.size.height)
        GeometryReader { proxy in
            let size = proxy.size
            let recordDiameter = min(size.height * (showsLyrics ? 0.66 : 0.82), size.width * 0.74)
            let recordCenter = CGPoint(x: size.width * 0.42, y: (showsLyrics ? size.height * 0.40 : size.height * 0.5))
            let pivot = CGPoint(x: size.width * 0.86, y: size.height * 0.16)
            ZStack {
                plinth(size: size)
                platterMat(diameter: recordDiameter * 1.04).position(recordCenter)
                record(diameter: recordDiameter)
                    .position(recordCenter)
                TimelineView(.animation(minimumInterval: 0.5, paused: !nowPlaying.isPlaying || armDrag != nil)) { timeline in
                    tonearm(pivot: pivot, recordCenter: recordCenter, recordRadius: recordDiameter / 2, size: size,
                            progress: armDrag ?? nowPlaying.clock.progress(at: timeline.date))
                }
                controls(size: size)
                if showsLyrics { lyricStrip(size: size) }
            }
        }
        .onChange(of: nowPlaying.isPlaying) { _, playing in
            if playing { Sounds.shared.play(.needle, volume: 0.6) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(nowPlaying.track.map { "Turntable, \($0.title) by \($0.artist)" } ?? "Turntable, nothing playing")
        .environment(\.colorScheme, finish == .chalk ? .light : .dark)
        .frame(width: context.size.width, height: context.size.height)
        .id(side > 0)
    }

    // MARK: Platter motion

    private static let spinDown: Double = 1.4  // seconds to coast to a stop

    private func isSpinningDown(_ now: Date) -> Bool {
        let clock = model.nowPlaying.clock
        return !clock.isPlaying && clock.anchor != .distantPast && now.timeIntervalSince(clock.anchor) < Self.spinDown
    }

    /// Playing: tied to position. Paused: coasts with constant deceleration from the pause moment.
    private func platterAngle(at date: Date) -> Double {
        let clock = model.nowPlaying.clock
        let base = clock.platterDegrees(at: date, rpm: rpm)
        guard !clock.isPlaying, clock.anchor != .distantPast else { return base }
        let t = min(Self.spinDown, max(0, date.timeIntervalSince(clock.anchor)))
        let omega = rpm / 60 * 360
        return base + omega * t - 0.5 * (omega / Self.spinDown) * t * t
    }

    // MARK: Parts

    private func plinth(size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: size.height * 0.07, style: .continuous)
        return shape
            .fill(finishGradient)
            .overlay {
                if finish == .walnut {
                    Canvas { context, canvasSize in
                        for i in 0..<34 {
                            let y = Double(i) / 34 * canvasSize.height
                            var path = Path()
                            path.move(to: CGPoint(x: 0, y: y))
                            for x in stride(from: 0.0, through: canvasSize.width, by: 12) {
                                path.addLine(to: CGPoint(x: x, y: y + sin(x / 37 + Double(i) * 1.7) * 3 + sin(x / 11 + Double(i)) * 0.8))
                            }
                            context.stroke(path, with: .color(.black.opacity(0.08 + 0.05 * sin(Double(i) * 2.3))), lineWidth: 1)
                        }
                    }
                    .clipShape(shape)
                }
            }
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                // Dust-cover reflection.
                LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center)
                    .clipShape(shape)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    private var finishGradient: LinearGradient {
        switch finish {
        case .walnut: LinearGradient(colors: [Color(red: 0.42, green: 0.26, blue: 0.16), Color(red: 0.27, green: 0.16, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .smoke: LinearGradient(colors: [Color(white: 0.16).opacity(0.92), Color(white: 0.06).opacity(0.96)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .chalk: LinearGradient(colors: [Color(white: 0.96), Color(white: 0.86)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func platterMat(diameter: CGFloat) -> some View {
        Circle()
            .fill(Color(white: 0.12))
            .overlay(Circle().strokeBorder(Color(white: 0.55).opacity(0.6), lineWidth: diameter * 0.012))
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
    }

    /// The grooves and sheen are static (the light doesn't move), so only the label re-renders while spinning.
    private func record(diameter: CGFloat) -> some View {
        let nowPlaying = model.nowPlaying
        return ZStack {
            Rectangle()
                .fill(.black)
                .colorEffect(ShaderLibrary.vinylRecord(.float2(diameter, diameter), .color(nowPlaying.palette.accent)))
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || (!nowPlaying.isPlaying && !isSpinningDown(Date())))) { timeline in
                ArtworkView(image: nowPlaying.artwork, cornerRadius: 0)
                    .frame(width: diameter * 0.36, height: diameter * 0.36)
                    .clipShape(Circle())
                    .overlay(Circle().fill(Color(white: 0.85)).frame(width: diameter * 0.022))
                    .rotationEffect(.degrees(platterAngle(at: timeline.date)))
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }

    private func tonearm(pivot: CGPoint, recordCenter: CGPoint, recordRadius: CGFloat, size: CGSize, progress: Double) -> some View {
        let nowPlaying = model.nowPlaying
        let armLength = hypot(pivot.x - recordCenter.x, pivot.y - recordCenter.y) * 0.98
        let restAngle = -6.0
        // Angles where the stylus meets the outer and inner grooves.
        let outer = angleToReach(radius: recordRadius * 0.94, pivot: pivot, center: recordCenter, length: armLength)
        let inner = angleToReach(radius: recordRadius * 0.42, pivot: pivot, center: recordCenter, length: armLength)
        let engaged = nowPlaying.isPlaying || armDrag != nil
        let angle = engaged ? outer + (inner - outer) * min(1, max(0, progress)) : restAngle
        let tint = finish == .chalk ? Color(white: 0.35) : Theme.brass

        return ZStack(alignment: .top) {
            Capsule()
                .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
                .frame(width: max(3, size.height * 0.018), height: armLength)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.15))
                .frame(width: size.height * 0.05, height: size.height * 0.075)
                .offset(y: armLength - size.height * 0.04)
                .gesture(DragGesture(coordinateSpace: .named("turntable")).onChanged { value in
                    let a = atan2(value.location.x - pivot.x, value.location.y - pivot.y) * 180 / .pi
                    armDrag = min(1, max(0, (-a - outer) / (inner - outer)))
                }.onEnded { _ in
                    if let armDrag, let duration = nowPlaying.clock.duration { nowPlaying.seek(to: armDrag * duration) }
                    armDrag = nil
                })
        }
        .frame(height: armLength, alignment: .top)
        .rotationEffect(.degrees(angle), anchor: .top)
        .position(x: pivot.x, y: pivot.y + armLength / 2)
        .overlay {
            Circle()
                .fill(RadialGradient(colors: [tint, tint.opacity(0.5)], center: .topLeading, startRadius: 1, endRadius: size.height * 0.06))
                .frame(width: size.height * 0.09, height: size.height * 0.09)
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                .position(pivot)
        }
        .coordinateSpace(.named("turntable"))
        .animation(armDrag == nil ? .spring(response: 0.9, dampingFraction: 0.82) : nil, value: engaged)
        .accessibilityHidden(true)
    }

    /// Arm rotation (degrees, clockwise from straight down) that puts the stylus at a given distance from the spindle.
    private func angleToReach(radius: CGFloat, pivot: CGPoint, center: CGPoint, length: CGFloat) -> Double {
        let dx = center.x - pivot.x, dy = center.y - pivot.y
        let distance = hypot(dx, dy)
        let toCenter = atan2(dx, dy)
        let cosOffset = (length * length + distance * distance - radius * radius) / (2 * length * distance)
        let offset = acos(min(1, max(-1, cosOffset)))
        return -(toCenter + offset) * 180 / .pi
    }

    private func controls(size: CGSize) -> some View {
        let nowPlaying = model.nowPlaying
        let ink: Color = finish == .chalk ? .black.opacity(0.75) : .white.opacity(0.9)
        return VStack(alignment: .trailing, spacing: 6) {
            if let track = nowPlaying.track, size.width > 260, !showsLyrics {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(track.title).font(Theme.Typeface.display(13)).lineLimit(1)
                    Text(track.artist).font(Theme.Typeface.caption).opacity(0.7).lineLimit(1)
                }
                .frame(maxWidth: size.width * 0.3, alignment: .trailing)
            }
            TransportControls(size: max(9, size.height * 0.032), spacing: 4)
            Text(rpm == 45 ? "45" : "33⅓")
                .font(.system(size: 9, weight: .bold).width(.expanded))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(Capsule().strokeBorder(ink.opacity(0.4)))
                .onTapGesture { context.update("speed", .string(rpm == 45 ? "33" : "45")) }
                .accessibilityLabel("Speed \(rpm == 45 ? "45" : "33 and a third") RPM")
                .accessibilityAddTraits(.isButton)
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(size.height * 0.05)
    }

    private func lyricStrip(size: CGSize) -> some View {
        LyricLineStrip(foreground: finish == .chalk ? .black : .white)
            .frame(height: size.height * 0.16)
            .padding(.leading, size.width * 0.05)
            .padding(.trailing, size.width * 0.32)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, size.height * 0.04)
    }
}

/// One karaoke line, used by the turntable and the click wheel.
struct LyricLineStrip: View {
    @Environment(AppModel.self) private var model
    var foreground: Color = .white
    var font: Font = Theme.Typeface.display(15, weight: .medium)

    var body: some View {
        let nowPlaying = model.nowPlaying
        let lyrics = model.lyrics
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !nowPlaying.isPlaying)) { timeline in
            let time = lyrics.time(for: nowPlaying.clock.position(at: timeline.date))
            let lines = lyrics.timeline
            let index = lines.lineIndex(at: time)
            ZStack {
                if let index, !lines.lines[index].isBreak {
                    let line = lines.lines[index]
                    Text(line.text)
                        .font(font)
                        .foregroundStyle(foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .textRenderer(KaraokeRenderer(progress: LyricProgress.characters(of: line, wordProgress: lines.wordProgress(line: index, at: time))))
                        .id(line.id)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(foreground.opacity(0.4))
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: index)
        }
        .accessibilityLabel("Lyrics")
    }
}
