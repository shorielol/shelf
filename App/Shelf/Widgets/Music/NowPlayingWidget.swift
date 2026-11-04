import ShelfCore
import SwiftUI

/// Compact art card on a mesh gradient pulled from the album colours.
struct NowPlayingWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model

    var body: some View {
        let nowPlaying = model.nowPlaying
        ZStack {
            MeshGradient(width: 3, height: 3, points: ClickWheelWidget.meshPoints, colors: nowPlaying.palette.mesh)
                .overlay(Color.black.opacity(0.25))
                .animation(.easeInOut(duration: 1.2), value: nowPlaying.palette)
            if let track = nowPlaying.track {
                if context.isWide { wide(track) } else { square(track) }
            } else {
                NothingPlaying(compact: context.size.height < 150)
            }
        }
        .foregroundStyle(.white)
        .glass(cornerRadius: Theme.Radius.widget, tint: nowPlaying.palette.primary)
    }

    private func square(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(image: model.nowPlaying.artwork, cornerRadius: 10)
                .frame(width: context.unit * 0.42, height: context.unit * 0.42)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            Spacer(minLength: 0)
            Text(track.title).font(Theme.Typeface.title(14)).lineLimit(1)
            Text(track.artist).font(Theme.Typeface.caption).opacity(0.7).lineLimit(1)
            if context.size.height > 220 {
                Scrubber(showsTimes: false)
                TransportControls(size: 14).frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if context.size.height <= 220 {
                Button { model.nowPlaying.playPause() } label: {
                    Image(systemName: model.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 32, height: 32)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .glassCircle(interactive: true)
                .padding(Theme.Space.m)
                .accessibilityLabel(model.nowPlaying.isPlaying ? "Pause" : "Play")
            }
        }
    }

    private func wide(_ track: Track) -> some View {
        HStack(spacing: Theme.Space.m) {
            ArtworkView(image: model.nowPlaying.artwork, cornerRadius: 12)
                .frame(width: context.size.height - 32, height: context.size.height - 32)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: model.nowPlaying.source?.displayName ?? "", color: .white.opacity(0.6))
                Text(track.title).font(Theme.Typeface.display(17)).lineLimit(1)
                Text(track.artist).font(Theme.Typeface.caption).opacity(0.7).lineLimit(1)
                Spacer(minLength: 0)
                Scrubber(showsTimes: true)
                TransportControls(size: 13, spacing: 8).frame(maxWidth: .infinity)
            }
        }
        .padding(Theme.Space.m)
    }
}
