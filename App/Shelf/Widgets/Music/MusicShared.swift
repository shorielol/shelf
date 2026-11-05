import AppKit
import ShelfCore
import SwiftUI

/// Album art, or a quiet record-sleeve placeholder.
struct ArtworkView: View {
    let image: NSImage?
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Theme.graphiteRaised, Theme.graphite], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Previous / play-pause / next.
struct TransportControls: View {
    @Environment(AppModel.self) private var model
    var size: CGFloat = 15
    var spacing: CGFloat = 18

    var body: some View {
        let nowPlaying = model.nowPlaying
        HStack(spacing: spacing) {
            button("backward.fill", label: "Previous track") { nowPlaying.previous() }
            button(nowPlaying.isPlaying ? "pause.fill" : "play.fill", label: nowPlaying.isPlaying ? "Pause" : "Play", scale: 1.35) { nowPlaying.playPause() }
                .contentTransition(.symbolEffect(.replace))
            button("forward.fill", label: "Next track") { nowPlaying.next() }
        }
        .disabled(nowPlaying.track == nil)
    }

    private func button(_ symbol: String, label: String, scale: CGFloat = 1, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * scale, weight: .semibold))
                .frame(width: size * scale * 1.9, height: size * scale * 1.9)
                .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

/// Scales down on press, springs back.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Theme.Motion.press, value: configuration.isPressed)
    }
}

/// Progress bar with elapsed and remaining time; drag to seek.
struct Scrubber: View {
    @Environment(AppModel.self) private var model
    var tint: Color = .white
    var showsTimes = true
    @State private var dragProgress: Double?

    var body: some View {
        let nowPlaying = model.nowPlaying
        TimelineView(.animation(minimumInterval: 0.25, paused: !nowPlaying.isPlaying || dragProgress != nil)) { timeline in
            let clock = nowPlaying.clock
            let progress = dragProgress ?? clock.progress(at: timeline.date)
            let duration = clock.duration ?? 0
            VStack(spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tint.opacity(0.22))
                        Capsule().fill(tint).frame(width: max(4, proxy.size.width * progress))
                    }
                    .frame(height: dragProgress == nil ? 4 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        dragProgress = min(1, max(0, value.location.x / proxy.size.width))
                    }.onEnded { _ in
                        if let dragProgress { nowPlaying.seek(to: dragProgress * duration) }
                        dragProgress = nil
                    })
                }
                .frame(height: 12)
                .animation(Theme.Motion.press, value: dragProgress == nil)
                if showsTimes {
                    HStack {
                        Text(Self.format(progress * duration))
                        Spacer()
                        Text("-" + Self.format(max(0, duration - progress * duration)))
                    }
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(tint.opacity(0.6))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Self.format(nowPlaying.clock.position(at: Date())))
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Lights a lyric line up to the singer's position. Each laid-out line is drawn twice (dimmed, then lit
/// and clipped at the highlight) rather than glyph by glyph, which matters for complex scripts.
nonisolated struct KaraokeRenderer: TextRenderer, Animatable {
    var progress: Double
    var dimOpacity: Double = 0.38

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let counts = layout.map { line in line.reduce(0) { $0 + $1.count } }
        var remaining = progress * Double(counts.reduce(0, +))
        for (line, count) in zip(layout, counts) {
            let lit = min(Double(count), max(0, remaining))
            remaining -= Double(count)
            if lit >= Double(count) {
                context.draw(line)
                continue
            }
            var dim = context
            dim.opacity = dimOpacity
            dim.draw(line)
            guard lit > 0 else { continue }
            let bounds = line.typographicBounds.rect
            var lightened = context
            lightened.clip(to: Path(CGRect(x: bounds.minX - 2, y: bounds.minY - 6,
                                           width: Self.cutoff(in: line, lit: lit) - bounds.minX + 2, height: bounds.height + 12)))
            lightened.draw(line)
        }
    }

    /// x position `lit` glyphs into the line, interpolating inside the glyph at the edge.
    private static func cutoff(in line: Text.Layout.Line, lit: Double) -> CGFloat {
        var index = 0.0
        var x = line.typographicBounds.rect.minX
        for run in line {
            for slice in run {
                let rect = slice.typographicBounds.rect
                if index + 1 > lit { return rect.minX + rect.width * CGFloat(lit - index) }
                x = rect.maxX
                index += 1
            }
        }
        return x
    }
}

/// Character-weighted progress through a line, from per-word progress.
enum LyricProgress {
    static func characters(of line: LyricLine, wordProgress: [Double]) -> Double {
        let lengths = line.words.map { Double($0.text.count) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return 0 }
        return zip(lengths, wordProgress).reduce(0) { $0 + $1.0 * $1.1 } / total
    }
}

/// Watches system stats while visible.
struct WatchesSystemStats: ViewModifier {
    @Environment(AppModel.self) private var model
    func body(content: Content) -> some View {
        content
            .onAppear { model.system.watch() }
            .onDisappear { model.system.unwatch() }
    }
}

extension View {
    func watchesSystemStats() -> some View { modifier(WatchesSystemStats()) }
}

/// Shared "nothing is playing" state for music widgets.
struct NothingPlaying: View {
    var compact = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.system(size: compact ? 16 : 22, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if !compact {
                Text("Play something in Music or Spotify")
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
