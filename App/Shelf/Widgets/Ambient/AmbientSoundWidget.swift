import ShelfCore
import SwiftUI

/// Generated rain, fire and noise. One big play button, a row of sound chips, a volume slider,
/// and a level meter that only moves while sound is coming out.
struct AmbientSoundWidget: View {
    let context: WidgetContext
    /// Slider value while dragging; written to config once the drag ends.
    @State private var dragVolume: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let engine = AmbientSoundEngine.shared

    private var sound: AmbientSound { AmbientSound(rawValue: context.string("sound", AmbientSound.rain.rawValue)) ?? .rain }
    private var volume: Double { context.double("volume", 0.5) }
    private var isPlaying: Bool { engine.isPlaying && engine.owner == context.id }

    var body: some View {
        WidgetCard(tint: isPlaying ? Theme.ember.opacity(0.6) : nil, padding: Theme.Space.m - 2) {
            if context.isWide { wide } else { compact }
        }
        .animation(Theme.Motion.standard, value: isPlaying)
        .onDisappear { if isPlaying { engine.pause() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ambient sound, \(sound.label)")
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .center) {
                Eyebrow(text: sound.label, color: isPlaying ? Theme.ember : Theme.textSecondary)
                    .contentTransition(.opacity)
                Spacer(minLength: 4)
                LevelMeter(isPlaying: isPlaying, bars: 6, reduceMotion: reduceMotion)
                    .frame(width: 34, height: 14)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                playButton(diameter: 52)
                Spacer()
            }
            Spacer(minLength: 0)
            chips(showsLabels: false)
            volumeSlider(compact: true)
        }
    }

    private var wide: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(spacing: Theme.Space.s) {
                playButton(diameter: 72)
                LevelMeter(isPlaying: isPlaying, bars: 9, reduceMotion: reduceMotion)
                    .frame(width: 64, height: 18)
            }
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Eyebrow(text: "Ambient sound", color: isPlaying ? Theme.ember : Theme.textSecondary)
                Text(title(for: sound))
                    .font(Theme.Typeface.display(22))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
                Spacer(minLength: 0)
                chips(showsLabels: true)
                volumeSlider(compact: false)
            }
        }
    }

    private func title(for sound: AmbientSound) -> String {
        switch sound {
        case .rain: "Rain"
        case .fireplace: "Fireplace"
        default: "\(sound.label) noise"
        }
    }

    // MARK: Controls

    private func playButton(diameter: CGFloat) -> some View {
        Button {
            if isPlaying { engine.pause() } else { engine.play(sound, volume: volume, owner: context.id) }
        } label: {
            ZStack {
                Circle()
                    .fill(isPlaying ? AnyShapeStyle(Theme.ember.gradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                Circle().strokeBorder(.white.opacity(isPlaying ? 0.3 : 0.16), lineWidth: 1)
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: diameter * 0.34, weight: .semibold))
                    .foregroundStyle(isPlaying ? Theme.graphite : Theme.textPrimary)
                    .offset(x: isPlaying ? 0 : diameter * 0.03)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: Theme.ember.opacity(isPlaying ? 0.45 : 0), radius: 10)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(isPlaying ? "Pause \(sound.label)" : "Play \(sound.label)")
    }

    private func chips(showsLabels: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(AmbientSound.allCases) { option in
                let selected = option == sound
                Button {
                    context.update("sound", .string(option.rawValue))
                    if isPlaying { engine.setSound(option) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: option.symbol).font(.system(size: 11, weight: .semibold))
                        if showsLabels && selected {
                            Text(option.label).font(Theme.Typeface.caption).lineLimit(1)
                        }
                    }
                    .foregroundStyle(selected ? Theme.graphite : Theme.textSecondary)
                    .padding(.horizontal, showsLabels && selected ? 10 : 0)
                    .frame(minWidth: 24, minHeight: 24)
                    .frame(maxWidth: showsLabels ? nil : .infinity)
                    .background(Capsule().fill(selected ? AnyShapeStyle(Theme.cream) : AnyShapeStyle(Color.white.opacity(0.08))))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .animation(Theme.Motion.lively, value: sound)
    }

    private func volumeSlider(compact: Bool) -> some View {
        HStack(spacing: 6) {
            if !compact {
                Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
            }
            Slider(value: Binding(get: { dragVolume ?? volume }, set: { value in
                dragVolume = value
                if isPlaying { engine.setVolume(value) }
            }), in: 0...1) { editing in
                guard !editing, let dragVolume else { return }
                context.update("volume", .number(dragVolume))
                self.dragVolume = nil
            }
            .controlSize(.mini)
            .tint(Theme.ember)
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int(volume * 100)) percent")
            if !compact {
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

/// A few bars driven by the engine's RMS level, sampled at 20 fps only while playing.
private struct LevelMeter: View {
    let isPlaying: Bool
    let bars: Int
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isPlaying || reduceMotion)) { timeline in
            let level = isPlaying ? Double(AmbientSoundEngine.shared.level) : 0
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let gap: CGFloat = 2
                let width = (proxy.size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
                HStack(alignment: .center, spacing: gap) {
                    ForEach(0..<bars, id: \.self) { i in
                        Capsule()
                            .fill(isPlaying ? Theme.ember : Theme.textTertiary)
                            .frame(width: width, height: barHeight(i, level: level, t: t, max: proxy.size.height))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isPlaying)
        .accessibilityHidden(true)
    }

    /// Each bar rides the shared level with its own slow wobble, so the meter never moves in lockstep.
    private func barHeight(_ i: Int, level: Double, t: Double, max: CGFloat) -> CGFloat {
        guard isPlaying else { return 3 }
        let seed = AmbientMotion.seeded(i, salt: 4)
        let wobble = reduceMotion ? 0.7 : 0.55 + 0.45 * abs(AmbientMotion.wave(t, period: 0.6 + seed * 0.9, phase: seed))
        return 3 + (max - 3) * CGFloat(min(1, level * wobble * (0.7 + seed * 0.5)))
    }
}
