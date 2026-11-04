import AppKit
import ShelfCore
import SwiftUI

/// A pocket music player with a click wheel. Spin the wheel for volume (one detent per 15°),
/// press MENU to change screens, the sides to skip, the bottom or centre to play and pause.
struct ClickWheelWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model
    @State private var screen: Screen = .nowPlaying
    @State private var wheelAngle: Double?
    @State private var accumulated: Double = 0
    @State private var volumeFlash: Date?
    @State private var pressed: WheelZone?

    enum Screen: Int, CaseIterable {
        case nowPlaying, lyrics, cover
        var title: String { ["Now Playing", "Lyrics", "Cover"][rawValue] }
    }

    enum WheelZone { case menu, next, previous, play, center }

    struct Skin {
        let body: [Color]
        let wheel: Color
        let wheelInk: Color
        let center: Color
        let bezel: Color
    }

    private var skin: Skin {
        switch context.string("skin", "frost") {
        case "graphite": Skin(body: [Color(white: 0.24), Color(white: 0.12)], wheel: Color(white: 0.17), wheelInk: Color(white: 0.75), center: Color(white: 0.22), bezel: .black)
        case "cherry": Skin(body: [Color(red: 0.86, green: 0.16, blue: 0.2), Color(red: 0.62, green: 0.07, blue: 0.12)], wheel: Color(white: 0.96), wheelInk: Color(white: 0.55), center: Color(red: 0.8, green: 0.12, blue: 0.17), bezel: Color(white: 0.08))
        case "mint": Skin(body: [Color(red: 0.73, green: 0.92, blue: 0.84), Color(red: 0.55, green: 0.8, blue: 0.7)], wheel: Color(white: 0.98), wheelInk: Color(white: 0.55), center: Color(red: 0.66, green: 0.88, blue: 0.79), bezel: Color(white: 0.12))
        default: Skin(body: [Color(white: 0.98), Color(white: 0.86)], wheel: Color(white: 0.97), wheelInk: Color(white: 0.6), center: Color(white: 0.9), bezel: Color(white: 0.1))
        }
    }

    var body: some View {
        let height = context.size.height
        let width = min(context.size.width, height * 0.61)
        let device = CGSize(width: width, height: width / 0.61)
        VStack(spacing: device.height * 0.055) {
            lcd(width: device.width * 0.86, height: device.height * 0.38)
            wheel(diameter: device.width * 0.74)
        }
        .padding(.top, device.height * 0.06)
        .frame(width: device.width, height: device.height, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: device.width * 0.13, style: .continuous)
                .fill(LinearGradient(colors: skin.body, startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: device.width * 0.13, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .black.opacity(0.15)], startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                )
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        }
        .frame(width: context.size.width, height: context.size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Click wheel player")
    }

    // MARK: Screen

    private func lcd(width: CGFloat, height: CGFloat) -> some View {
        let nowPlaying = model.nowPlaying
        let palette = nowPlaying.palette
        return ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.93, green: 0.95, blue: 0.97), Color(red: 0.8, green: 0.84, blue: 0.88)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 0) {
                statusBar(height: height * 0.12)
                Group {
                    if nowPlaying.track == nil {
                        VStack(spacing: 4) {
                            Image(systemName: "music.note").font(.system(size: height * 0.12))
                            Text("No Music").font(Theme.Typeface.pixel(height * 0.075))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        switch screen {
                        case .nowPlaying: nowPlayingScreen(height: height)
                        case .lyrics: lyricsScreen(height: height)
                        case .cover: coverScreen(height: height, palette: palette)
                        }
                    }
                }
                .transition(.push(from: .trailing))
            }
            .foregroundStyle(Color(white: 0.1))
            if let flash = volumeFlash, Date().timeIntervalSince(flash) < 1.2 {
                volumeOverlay(width: width).padding(.top, height * 0.6)
            }
        }
        .frame(width: width, height: height)
        .clipShape(.rect(cornerRadius: 4))
        .colorEffect(ShaderLibrary.lcdPixels(.float2(width, height), .float(2)))
        .padding(3)
        .background(skin.bezel, in: .rect(cornerRadius: 6))
        .animation(.easeInOut(duration: 0.25), value: screen)
    }

    private func statusBar(height: CGFloat) -> some View {
        HStack {
            Image(systemName: model.nowPlaying.isPlaying ? "play.fill" : "pause.fill")
            Spacer()
            Text(screen.title)
            Spacer()
            Image(systemName: "battery.75percent")
        }
        .font(Theme.Typeface.pixel(height * 0.62))
        .padding(.horizontal, 6)
        .frame(height: height)
        .background(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.8)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.55)).frame(height: 0.5) }
    }

    private func nowPlayingScreen(height: CGFloat) -> some View {
        let nowPlaying = model.nowPlaying
        let track = nowPlaying.track
        return VStack(spacing: height * 0.04) {
            HStack(spacing: 8) {
                ArtworkView(image: nowPlaying.artwork, cornerRadius: 2)
                    .frame(width: height * 0.42, height: height * 0.42)
                    .rotation3DEffect(.degrees(14), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 2, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track?.title ?? "").font(Theme.Typeface.pixel(height * 0.075)).lineLimit(2)
                    Text(track?.artist ?? "").font(Theme.Typeface.pixel(height * 0.065)).opacity(0.7).lineLimit(1)
                    Text(track?.album ?? "").font(Theme.Typeface.pixel(height * 0.065)).opacity(0.55).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.top, height * 0.05)
            Scrubber(tint: Color(red: 0.2, green: 0.45, blue: 0.9), showsTimes: true)
                .padding(.horizontal, 10)
            LyricLineStrip(foreground: Color(white: 0.1), font: Theme.Typeface.pixel(height * 0.06))
                .frame(height: height * 0.12)
                .padding(.horizontal, 6)
        }
    }

    private func lyricsScreen(height: CGFloat) -> some View {
        LyricsColumn(foreground: Color(white: 0.08), font: Theme.Typeface.pixel(height * 0.07), focusScale: 1.12, visibleLines: 5)
            .padding(.horizontal, 8)
    }

    private func coverScreen(height: CGFloat, palette: ArtworkPalette) -> some View {
        ZStack {
            MeshGradient(width: 3, height: 3, points: Self.meshPoints, colors: palette.mesh)
            ArtworkView(image: model.nowPlaying.artwork, cornerRadius: 3)
                .frame(width: height * 0.62, height: height * 0.62)
                .shadow(color: .black.opacity(0.35), radius: 6, y: 4)
                .overlay(alignment: .bottom) {
                    ArtworkView(image: model.nowPlaying.artwork, cornerRadius: 3)
                        .scaleEffect(y: -1)
                        .mask(LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .center))
                        .offset(y: height * 0.63)
                }
        }
    }

    static let meshPoints: [SIMD2<Float>] = [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.55, 0.45], [1, 0.5], [0, 1], [0.5, 1], [1, 1]]

    private func volumeOverlay(width: CGFloat) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill")
            ProgressView(value: Double(model.nowPlaying.volume), total: 100).tint(Color(red: 0.2, green: 0.45, blue: 0.9))
            Image(systemName: "speaker.wave.3.fill")
        }
        .font(.system(size: 9))
        .padding(8)
        .frame(width: width * 0.86)
        .background(Color(white: 0.95).opacity(0.95), in: .rect(cornerRadius: 4))
        .transition(.opacity)
    }

    // MARK: Wheel

    private func wheel(diameter: CGFloat) -> some View {
        let label = Font.system(size: diameter * 0.075, weight: .bold).width(.expanded)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [skin.wheel, skin.wheel.opacity(0.92)], center: .top, startRadius: 0, endRadius: diameter))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            Group {
                Text("MENU").font(label).offset(y: -diameter * 0.37)
                Image(systemName: "forward.end.alt.fill").offset(x: diameter * 0.37)
                Image(systemName: "backward.end.alt.fill").offset(x: -diameter * 0.37)
                Image(systemName: "playpause.fill").offset(y: diameter * 0.37)
            }
            .font(.system(size: diameter * 0.08))
            .foregroundStyle(skin.wheelInk)
            Circle()
                .fill(LinearGradient(colors: [skin.center.opacity(0.95), skin.center], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
                .frame(width: diameter * 0.38, height: diameter * 0.38)
                .scaleEffect(pressed == .center ? 0.95 : 1)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(wheelGesture(diameter: diameter))
        .animation(Theme.Motion.press, value: pressed)
        .accessibilityElement()
        .accessibilityLabel("Click wheel")
        .accessibilityHint("Turn to change volume")
        .accessibilityAdjustableAction { direction in
            model.nowPlaying.setVolume(model.nowPlaying.volume + (direction == .increment ? 6 : -6))
        }
        .accessibilityAction(named: "Play or pause") { model.nowPlaying.playPause() }
        .accessibilityAction(named: "Next track") { model.nowPlaying.next() }
        .accessibilityAction(named: "Previous track") { model.nowPlaying.previous() }
        .accessibilityAction(named: "Menu") { cycleScreen() }
    }

    private static let detent = 15.0

    private func wheelGesture(diameter: CGFloat) -> some Gesture {
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        return DragGesture(minimumDistance: 0)
            .onChanged { value in
                let distance = hypot(value.location.x - center.x, value.location.y - center.y)
                if pressed == nil { pressed = zone(of: value.startLocation, center: center, diameter: diameter) }
                guard distance > diameter * 0.2 else { return }
                let angle = atan2(value.location.y - center.y, value.location.x - center.x) * 180 / .pi
                if let last = wheelAngle {
                    var delta = angle - last
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }
                    accumulated += delta
                    while abs(accumulated) >= Self.detent {
                        let step = accumulated > 0 ? 1 : -1
                        accumulated -= Double(step) * Self.detent
                        tick(step)
                    }
                }
                wheelAngle = angle
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height)
                if moved < 4, let zone = pressed { press(zone) }
                wheelAngle = nil
                accumulated = 0
                pressed = nil
            }
    }

    private func zone(of point: CGPoint, center: CGPoint, diameter: CGFloat) -> WheelZone {
        let dx = point.x - center.x, dy = point.y - center.y
        if hypot(dx, dy) < diameter * 0.19 { return .center }
        if abs(dy) > abs(dx) { return dy < 0 ? .menu : .play }
        return dx > 0 ? .next : .previous
    }

    private func press(_ zone: WheelZone) {
        Sounds.shared.play(.tick, volume: 0.7)
        switch zone {
        case .menu: cycleScreen()
        case .next: model.nowPlaying.next()
        case .previous: model.nowPlaying.previous()
        case .play, .center: model.nowPlaying.playPause()
        }
    }

    private func cycleScreen() {
        screen = Screen(rawValue: (screen.rawValue + 1) % Screen.allCases.count) ?? .nowPlaying
    }

    private func tick(_ step: Int) {
        Sounds.shared.play(.tick, volume: 0.45)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        model.nowPlaying.setVolume(model.nowPlaying.volume + step * 3)
        volumeFlash = Date()
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            if let flash = volumeFlash, Date().timeIntervalSince(flash) >= 1.2 { volumeFlash = nil }
        }
    }
}
