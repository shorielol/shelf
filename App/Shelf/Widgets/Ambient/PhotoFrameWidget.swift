import ShelfCore
import SwiftUI

/// Photos from a folder. Each one drifts in a slow Ken Burns move for as long as it's up,
/// then crossfades to the next. Tap to skip ahead.
struct PhotoFrameWidget: View {
    let context: WidgetContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var urls: [URL] = []
    @State private var phase: LoadPhase = .scanning
    @State private var slide: Slide?
    @State private var cursor = 0
    @State private var scanCount = 0

    private enum LoadPhase { case scanning, empty, ready }

    /// What's on screen, with the moment it arrived so the drift can run from there.
    private struct Slide: Equatable {
        let photo: FramedPhoto
        let shownAt: Date
        let seed: Int
    }

    private struct RotationKey: Equatable {
        let scan: Int
        let count: Int
        let cursor: Int
        let interval: Double
        let pixels: Int
    }

    private var folder: String { context.string("folder", "~/Pictures") }
    private var interval: TimeInterval { max(1, context.double("interval", 5)) * 60 }
    private var isPolaroid: Bool { context.string("frame", "none") == "polaroid" }
    /// Thumbnail size in pixels, bucketed so small resizes don't reload the photo.
    private var pixels: Int { Int((max(context.size.width, context.size.height) * 2 / 128).rounded(.up)) * 128 }

    var body: some View {
        content
            .frame(width: context.size.width, height: context.size.height)
            .task(id: folder) { await scan() }
            .task(id: RotationKey(scan: scanCount, count: urls.count, cursor: cursor, interval: interval, pixels: pixels)) { await rotate() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Photo frame")
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(urls.count > 1 ? .isButton : [])
            .accessibilityHint(urls.count > 1 ? "Shows the next photo" : "")
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .scanning:
            WidgetCard { ProgressView().controlSize(.small) }
        case .empty:
            WidgetCard {
                WidgetPlaceholder(symbol: "photo.on.rectangle.angled", title: "No photos here",
                                  detail: context.size.height > 200 || context.isWide ? "Add JPEG, PNG or HEIC files to \(folder), or pick another folder in settings." : nil)
            }
        case .ready:
            if isPolaroid { polaroid } else { fullBleed }
        }
    }

    // MARK: Loading

    private func scan() async {
        phase = .scanning
        let found = await PhotoLibrary.imageURLs(in: folder)
        guard !Task.isCancelled else { return }
        urls = found
        scanCount += 1
        cursor = 0
        slide = nil
        phase = found.isEmpty ? .empty : .ready
    }

    /// Shows the photo at `cursor`, waits, then moves the cursor on, which restarts this task.
    private func rotate() async {
        guard !urls.isEmpty else { return }
        let url = urls[cursor % urls.count]
        if slide?.photo.url != url || slide?.photo.image.width ?? 0 < pixels / 2 {
            guard let photo = await PhotoLibrary.thumbnail(for: url, maxPixel: pixels), !Task.isCancelled else {
                if !Task.isCancelled, urls.count > 1 { cursor += 1 }
                return
            }
            withAnimation(reduceMotion ? .easeInOut(duration: 0.4) : .easeInOut(duration: 1.6)) {
                slide = Slide(photo: photo, shownAt: Date(), seed: cursor)
            }
        }
        guard urls.count > 1 else { return }
        try? await Task.sleep(for: .seconds(interval))
        guard !Task.isCancelled else { return }
        cursor += 1
    }

    private func advance() {
        guard urls.count > 1 else { return }
        cursor += 1
    }

    // MARK: Styles

    private var fullBleed: some View {
        ZStack {
            Theme.graphite
            slideStack
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.widget, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .contentShape(.rect)
        .onTapGesture(perform: advance)
    }

    private var polaroid: some View {
        let tilt = (AmbientMotion.seed(from: context.id) - 0.5) * 5
        let inset = context.unit * 0.09
        let border = context.unit * 0.05
        let chin = max(22, context.unit * 0.16)
        return WidgetCard(padding: inset) {
            VStack(spacing: 0) {
                slideStack
                    .clipShape(.rect(cornerRadius: 1.5))
                    .overlay(Rectangle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                caption.frame(height: chin)
            }
            .padding([.top, .horizontal], border)
            .background(PaperFill())
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            .rotationEffect(.degrees(tilt))
            .contentShape(.rect)
            .onTapGesture(perform: advance)
        }
    }

    private var caption: some View {
        Text(slide?.photo.date.map { $0.formatted(.dateTime.day().month(.abbreviated).year()) } ?? "")
            .font(Theme.Typeface.display(max(11, context.unit * 0.075), weight: .regular).italic())
            .foregroundStyle(Theme.graphite.opacity(0.62))
            .lineLimit(1)
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The current photo with its drift. The outgoing photo keeps its last frame while it fades.
    private var slideStack: some View {
        GeometryReader { proxy in
            ZStack {
                if let slide {
                    // The pan moves well under a pixel per frame, so 2 fps looks the same as 60.
                    TimelineView(.animation(minimumInterval: 0.5, paused: reduceMotion)) { timeline in
                        drifting(slide, in: proxy.size, at: timeline.date)
                    }
                    .id(slide.photo.url)
                    .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private func drifting(_ slide: Slide, in size: CGSize, at date: Date) -> some View {
        let move = KenBurns(seed: slide.seed)
        let p = reduceMotion ? 0 : min(1, max(0, date.timeIntervalSince(slide.shownAt) / interval))
        let eased = p * p * (3 - 2 * p)
        let scale = move.startScale + (move.endScale - move.startScale) * eased
        let travel = (scale - 1) / 2
        return Image(decorative: slide.photo.image, scale: 2)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .offset(x: size.width * travel * (move.from.x + (move.to.x - move.from.x) * eased),
                    y: size.height * travel * (move.from.y + (move.to.y - move.from.y) * eased))
    }

    private var accessibilityValue: String {
        switch phase {
        case .scanning: "Loading"
        case .empty: "No photos in \(folder)"
        case .ready:
            slide?.photo.date.map { "Photo from \($0.formatted(date: .long, time: .omitted))" } ?? "Photo"
        }
    }
}

/// A slow zoom-and-pan picked from a seed: in or out, from one side toward another.
private struct KenBurns {
    let startScale: Double
    let endScale: Double
    let from: CGPoint
    let to: CGPoint

    init(seed: Int) {
        let r = { (salt: Double) in AmbientMotion.seeded(seed, salt: salt) }
        let zoomIn = r(1) > 0.4
        startScale = zoomIn ? 1.04 : 1.14
        endScale = zoomIn ? 1.14 : 1.04
        from = CGPoint(x: r(2) * 2 - 1, y: r(3) * 2 - 1)
        to = CGPoint(x: -(from.x) * 0.6 + (r(4) - 0.5) * 0.4, y: -(from.y) * 0.6 + (r(5) - 0.5) * 0.4)
    }
}

/// Instant-print paper: warm cream with the faintest tooth.
private struct PaperFill: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Theme.cream, Color(red: 0.92, green: 0.90, blue: 0.85)], startPoint: .top, endPoint: .bottom))
            .overlay(Rectangle().strokeBorder(.white.opacity(0.6), lineWidth: 0.5))
    }
}
