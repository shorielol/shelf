import ShelfCore
import SwiftUI

/// Synced lyrics: the current line lit word by word, neighbours fading out above and below.
struct LyricsWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model

    var body: some View {
        let nowPlaying = model.nowPlaying
        let palette = nowPlaying.palette
        ZStack {
            MeshGradient(width: 3, height: 3, points: ClickWheelWidget.meshPoints, colors: palette.mesh)
                .overlay(Color.black.opacity(0.38))
                .animation(.easeInOut(duration: 1.2), value: palette)
            content
                .padding(.horizontal, Theme.Space.m)
                .padding(.vertical, Theme.Space.s)
            if let track = nowPlaying.track, context.size.height >= 300 {
                header(track)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(Theme.Space.m)
            }
        }
        .glass(cornerRadius: Theme.Radius.widget, tint: palette.primary)
    }

    @ViewBuilder
    private var content: some View {
        switch (model.nowPlaying.track, model.lyrics.state) {
        case (nil, _):
            NothingPlaying(compact: context.size.height < 120)
        case (_, .loading), (_, .idle):
            ProgressView().controlSize(.small).tint(.white)
        case (_, .missing):
            WidgetPlaceholder(symbol: "text.page.slash", title: "No lyrics for this one")
        case (_, .loaded(let lyrics)):
            switch lyrics.kind {
            case .instrumental:
                WidgetPlaceholder(symbol: "music.note", title: "Instrumental")
            case .plain:
                ScrollView {
                    Text(lyrics.source)
                        .font(Theme.Typeface.display(15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Space.l)
                }
                .scrollIndicators(.never)
            case .synced:
                LyricsColumn(
                    foreground: .white,
                    font: Theme.Typeface.display(max(15, min(26, context.unit * 0.1)), weight: .semibold),
                    focusScale: 1.0,
                    visibleLines: context.size.height < 200 ? 3 : 5
                )
                .padding(.top, context.size.height >= 300 ? 44 : 0)
            }
        }
    }

    private func header(_ track: Track) -> some View {
        HStack(spacing: 10) {
            ArtworkView(image: model.nowPlaying.artwork, cornerRadius: 6).frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(Theme.Typeface.title(12)).lineLimit(1)
                Text(track.artist).font(Theme.Typeface.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
            Spacer()
        }
        .foregroundStyle(.white)
    }
}

/// A vertically scrolling stack of lyric lines centred on the active one.
/// The column itself only re-evaluates four times a second (enough to move to the next line); just the
/// line being sung animates its word wipe, so the blurred neighbours aren't redrawn every frame.
struct LyricsColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var foreground: Color
    var font: Font
    var focusScale: CGFloat
    var visibleLines: Int

    var body: some View {
        let nowPlaying = model.nowPlaying
        let lyrics = model.lyrics
        TimelineView(.periodic(from: .now, by: nowPlaying.isPlaying ? 0.5 : 3600)) { timeline in
            let time = lyrics.time(for: nowPlaying.clock.position(at: timeline.date))
            let lines = lyrics.timeline.lines
            let active = lyrics.timeline.lineIndex(at: time) ?? -1
            let radius = visibleLines / 2
            let range = max(0, active - radius)...max(0, min(lines.count - 1, max(active, 0) + radius))
            VStack(spacing: 10) {
                if !lines.isEmpty {
                    ForEach(lines[range]) { line in
                        lineView(line, active: active)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18), .init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.86), value: active)
        }
    }

    @ViewBuilder
    private func lineView(_ line: LyricLine, active: Int) -> some View {
        let distance = abs(line.id - active)
        let isActive = line.id == active
        Group {
            if line.isBreak {
                Image(systemName: "ellipsis").symbolEffect(.variableColor.iterative, isActive: isActive)
            } else if isActive {
                SungLine(line: line, font: font)
            } else {
                Text(line.text)
            }
        }
        .font(font)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(foreground)
        .opacity(isActive ? 1 : max(0.12, 0.5 - Double(distance) * 0.12))
        .scaleEffect(isActive ? focusScale : 0.94)
        .blur(radius: isActive ? 0 : min(2.5, Double(distance) * 0.8))
        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
        .accessibilityHidden(!isActive)
    }
}

/// The line being sung. Its own 15 fps timeline drives the word wipe and nothing else.
private struct SungLine: View {
    @Environment(AppModel.self) private var model
    let line: LyricLine
    let font: Font

    var body: some View {
        let nowPlaying = model.nowPlaying
        let lyrics = model.lyrics
        TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: !nowPlaying.isPlaying)) { timeline in
            let time = lyrics.time(for: nowPlaying.clock.position(at: timeline.date))
            let progress = LyricProgress.characters(of: line, wordProgress: lyrics.timeline.wordProgress(line: line.id, at: time))
            Text(line.text)
                .font(font)
                .textRenderer(KaraokeRenderer(progress: progress, dimOpacity: 0.4))
        }
    }
}
