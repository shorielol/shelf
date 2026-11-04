import EventKit
import ShelfCore
import SwiftUI

/// The welcome sequence. Scenes advance on their own the first time through; arrows and Return also work.
struct OnboardingView: View {
    let finish: (StarterLayout?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: Scene = .arrival

    enum Scene: Int, CaseIterable {
        case arrival, drop, needle, permissions, layout
    }

    var body: some View {
        ZStack {
            Theme.graphite.ignoresSafeArea()
            TopographicBackground(tintA: Theme.ember, tintB: Theme.brass, density: 8, opacity: 0.42)
                .ignoresSafeArea()
            Group {
                switch scene {
                case .arrival: ArrivalScene { advance() }
                case .drop: DropScene { advance() }
                case .needle: NeedleScene { advance() }
                case .permissions: PermissionsScene { advance() }
                case .layout: LayoutScene(finish: finish)
                }
            }
            .transition(reduceMotion ? .opacity : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .id(scene)
            pageDots
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 22)
        }
        .foregroundStyle(Theme.textPrimary)
        .frame(width: 1040, height: 680)
        .animation(reduceMotion ? .easeOut(duration: 0.25) : .spring(response: 0.6, dampingFraction: 0.88), value: scene)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.rightArrow) { advance(); return .handled }
        .onKeyPress(.leftArrow) { back(); return .handled }
        .onKeyPress(.escape) { finish(nil); return .handled }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(Scene.allCases, id: \.self) { item in
                Capsule()
                    .fill(item == scene ? Theme.ember : Color.white.opacity(0.25))
                    .frame(width: item == scene ? 22 : 6, height: 6)
            }
        }
        .animation(Theme.Motion.lively, value: scene)
        .accessibilityElement()
        .accessibilityLabel("Step \(scene.rawValue + 1) of \(Scene.allCases.count)")
    }

    private func advance() {
        guard let next = Scene(rawValue: scene.rawValue + 1) else { return }
        scene = next
    }

    private func back() {
        guard let previous = Scene(rawValue: scene.rawValue - 1) else { return }
        scene = previous
    }
}

/// Contour lines drifting under everything.
struct TopographicBackground: View {
    var tintA: Color
    var tintB: Color
    var density: Float = 9
    var opacity: Double = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = Float(timeline.date.timeIntervalSince(start))
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.black)
                    .colorEffect(ShaderLibrary.topographicFlow(.float2(proxy.size), .float(time), .color(tintA), .color(tintB), .float(density)))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A primary call to action on glass.
struct OnboardingButton: View {
    let title: String
    var tint: Color? = Theme.ember
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typeface.title(14))
                .padding(.horizontal, 22)
                .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
        .glassCapsule(tint: tint, interactive: true)
        .keyboardShortcut(.defaultAction)
    }
}

// MARK: - 1. Arrival

private struct ArrivalScene: View {
    let next: () -> Void
    @State private var revealed = false
    @State private var shelfDrawn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let word = Array("Shelf")

    var body: some View {
        VStack(spacing: 28) {
            HStack(spacing: 0) {
                ForEach(Array(word.enumerated()), id: \.offset) { index, letter in
                    RefractedLetter(letter: String(letter), revealed: revealed)
                        .animation(.spring(response: 0.7, dampingFraction: 0.7).delay(reduceMotion ? 0 : Double(index) * 0.09), value: revealed)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Shelf")
            .accessibilityAddTraits(.isHeader)
            Capsule()
                .fill(LinearGradient(colors: [.clear, Theme.brass.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: shelfDrawn ? 520 : 0, height: 2)
                .shadow(color: Theme.brass.opacity(0.7), radius: 8)
                .animation(.easeOut(duration: 0.9).delay(0.55), value: shelfDrawn)
            Text("Widgets for your desktop, with a pulse.")
                .font(Theme.Typeface.display(20, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                .opacity(shelfDrawn ? 1 : 0)
                .offset(y: shelfDrawn ? 0 : 8)
                .animation(.easeOut(duration: 0.6).delay(1.1), value: shelfDrawn)
            OnboardingButton(title: "Begin", action: next)
                .opacity(shelfDrawn ? 1 : 0)
                .animation(.easeOut(duration: 0.5).delay(1.6), value: shelfDrawn)
        }
        .onAppear {
            revealed = true
            shelfDrawn = true
        }
    }
}

/// One letter that settles out of a chromatic split, like light finding focus through glass.
private struct RefractedLetter: View {
    let letter: String
    let revealed: Bool

    var body: some View {
        let split: CGFloat = revealed ? 1.6 : 14
        ZStack {
            glyph.foregroundStyle(Theme.ember.opacity(0.85)).offset(x: -split)
            glyph.foregroundStyle(Theme.brass.opacity(0.85)).offset(x: split, y: split * 0.3)
            glyph.foregroundStyle(.white)
        }
        .compositingGroup()
        .blur(radius: revealed ? 0 : 14)
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 36)
    }

    private var glyph: some View {
        Text(letter)
            .font(Theme.Typeface.display(112, weight: .bold))
            .tracking(-3)
            .blendMode(.plusLighter)
    }
}

// MARK: - 2. The drop

private struct DropScene: View {
    let next: () -> Void
    @State private var sim: DropSim?
    @State private var landed: Set<Int> = []
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// (kind, preview size) dropped onto the shelf, left to right.
    private let items: [(kind: String, size: CGSize)] = [
        ("clickwheel", CGSize(width: 120, height: 196)),
        ("turntable", CGSize(width: 214, height: 196)),
        ("lyrics", CGSize(width: 180, height: 196)),
        ("flipclock", CGSize(width: 196, height: 92)),
        ("weather", CGSize(width: 110, height: 110)),
    ]
    private let shelfY: CGFloat = 470

    var body: some View {
        let available = items.filter { WidgetCatalog.descriptor(for: $0.kind) != nil }
        VStack(spacing: 0) {
            Text("Real widgets. On your desktop.")
                .font(Theme.Typeface.display(38))
                .displayTracking(38)
                .padding(.top, 70)
            Text("They sit just above your icons and below every window, on every Space.")
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)
            Spacer()
        }
        .overlay {
            TimelineView(.animation(paused: reduceMotion || (sim?.isSettled ?? false))) { timeline in
                Canvas { _, _ in } symbols: { EmptyView() }
                    .onChange(of: timeline.date) { old, new in step(dt: new.timeIntervalSince(old), count: available.count) }
                ZStack(alignment: .topLeading) {
                    shelf
                    ForEach(Array(available.enumerated()), id: \.offset) { index, item in
                        preview(item.kind, size: item.size)
                            .frame(width: item.size.width, height: item.size.height)
                            .rotationEffect(.radians(body(index)?.rotation ?? 0), anchor: .bottom)
                            .position(x: xPosition(index, available: available), y: (body(index)?.y ?? shelfY) - item.size.height / 2)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            OnboardingButton(title: "Continue", action: next)
                .padding(.bottom, 64)
                .opacity((sim?.isSettled ?? false) || reduceMotion ? 1 : 0.0)
                .animation(.easeOut(duration: 0.4), value: sim?.isSettled ?? false)
        }
        .onAppear {
            let bodies = available.indices.map { index in
                DropBody(y: -260 - Double(index) * 40, floor: shelfY, rotation: (index.isMultiple(of: 2) ? 1 : -1) * 0.18, delay: 0.25 + Double(index) * 0.16)
            }
            var initial = DropSim(bodies: bodies, gravity: 3400, restitution: 0.32)
            if reduceMotion { for _ in 0..<600 { initial.step(dt: 1.0 / 60) } }
            sim = initial
        }
    }

    private func body(_ index: Int) -> DropBody? {
        guard let sim, sim.bodies.indices.contains(index) else { return nil }
        return sim.bodies[index]
    }

    private func step(dt: Double, count: Int) {
        guard var current = sim, dt > 0 else { return }
        current.step(dt: min(dt, 1.0 / 30))
        for (index, body) in current.bodies.enumerated() where body.landed && !landed.contains(index) {
            landed.insert(index)
            Sounds.shared.play(.thud, volume: 0.5)
        }
        sim = current
    }

    private func xPosition(_ index: Int, available: [(kind: String, size: CGSize)]) -> CGFloat {
        let gap: CGFloat = 26
        let total = available.reduce(0) { $0 + $1.size.width } + gap * CGFloat(max(0, available.count - 1))
        var x = (1040 - total) / 2
        for i in 0..<index { x += available[i].size.width + gap }
        return x + available[index].size.width / 2
    }

    private var shelf: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)], startPoint: .top, endPoint: .bottom))
            .frame(width: 900, height: 10)
            .overlay(alignment: .top) { Rectangle().fill(Theme.brass.opacity(0.7)).frame(height: 1) }
            .shadow(color: .black.opacity(0.5), radius: 14, y: 12)
            .position(x: 520, y: shelfY + 5)
    }

    @ViewBuilder
    private func preview(_ kind: String, size: CGSize) -> some View {
        if let descriptor = WidgetCatalog.descriptor(for: kind) {
            let natural = descriptor.defaultSize.side
            let scale = min(size.width / natural.width, size.height / natural.height)
            descriptor.make(WidgetContext(id: UUID(), config: descriptor.defaultConfig, size: CGSize(width: natural.width, height: natural.height), isEditing: false) { _, _ in })
                .frame(width: natural.width, height: natural.height)
                .clipShape(.rect(cornerRadius: descriptor.isFreeform ? 0 : Theme.Radius.widget, style: .continuous))
                .scaleEffect(scale)
                .frame(width: natural.width * scale, height: natural.height * scale)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 8)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 3. Needle drop

private struct NeedleScene: View {
    let next: () -> Void
    @State private var engaged = false
    @State private var lyricProgress = 0.0
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tagline = "Your desktop, with a pulse."

    var body: some View {
        HStack(spacing: 64) {
            DemoTurntable(engaged: engaged, start: start)
                .frame(width: 400, height: 400)
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Synced lyrics", color: Theme.brass)
                Text(tagline)
                    .font(Theme.Typeface.display(44, weight: .semibold))
                    .displayTracking(44)
                    .textRenderer(KaraokeRenderer(progress: lyricProgress, dimOpacity: 0.28))
                    .frame(width: 400, alignment: .leading)
                Text("Music and Spotify, word by word. The record spins at 33⅓ and the tonearm follows the song.")
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 380, alignment: .leading)
                OnboardingButton(title: "Continue", action: next)
                    .padding(.top, 8)
            }
        }
        .onAppear {
            start = Date()
            withAnimation(.spring(response: 1.1, dampingFraction: 0.8).delay(0.4)) { engaged = true }
            Task {
                try? await Task.sleep(for: .milliseconds(1100))
                Sounds.shared.play(.needle, volume: 0.6)
                withAnimation(.linear(duration: reduceMotion ? 0.3 : 2.6)) { lyricProgress = 1 }
            }
        }
    }
}

/// A turntable that needs no music: ember label, spinning once the arm lands.
struct DemoTurntable: View {
    let engaged: Bool
    let start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let record = size.width * 0.74
            let center = CGPoint(x: size.width * 0.44, y: size.height * 0.5)
            ZStack {
                RoundedRectangle(cornerRadius: size.width * 0.07, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.26, blue: 0.16), Color(red: 0.25, green: 0.15, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: size.width * 0.07, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
                TimelineView(.animation(paused: !engaged || reduceMotion)) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(start) - 1.1)
                    ZStack {
                        Rectangle().fill(.black).colorEffect(ShaderLibrary.vinylRecord(.float2(record, record), .color(Theme.ember)))
                        ZStack {
                            Circle().fill(Theme.ember)
                            Text("SHELF").font(.system(size: record * 0.045, weight: .heavy).width(.expanded)).foregroundStyle(Theme.cream).offset(y: -record * 0.06)
                            Text("33⅓").font(.system(size: record * 0.03, weight: .bold)).foregroundStyle(Theme.cream.opacity(0.8)).offset(y: record * 0.07)
                            Circle().fill(Theme.cream).frame(width: record * 0.022)
                        }
                        .frame(width: record * 0.36, height: record * 0.36)
                        .rotationEffect(.degrees(engaged ? elapsed * 200 : 0))
                    }
                    .frame(width: record, height: record)
                    .clipShape(Circle())
                }
                .position(center)
                Capsule()
                    .fill(LinearGradient(colors: [Theme.brass, Theme.brass.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 7, height: size.height * 0.56)
                    .overlay(alignment: .bottom) { RoundedRectangle(cornerRadius: 2).fill(Color(white: 0.15)).frame(width: 18, height: 30) }
                    .rotationEffect(.degrees(engaged ? 26 : 8), anchor: .top)
                    .position(x: size.width * 0.86, y: size.height * 0.15 + size.height * 0.28)
                Circle().fill(Theme.brass).frame(width: 34, height: 34).shadow(radius: 4).position(x: size.width * 0.86, y: size.height * 0.15)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 4. Permissions

private struct PermissionsScene: View {
    let next: () -> Void
    @Environment(AppModel.self) private var model
    @State private var calendarGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                Text("Let the widgets see a little.")
                    .font(Theme.Typeface.display(38))
                    .displayTracking(38)
                Text("Each one is optional. Shelf never sends this anywhere.")
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 18) {
                card(symbol: "music.note", title: "Music & Spotify", detail: "Track, artwork and lyrics for the music widgets. macOS asks the first time a song plays.", granted: model.nowPlaying.track != nil, action: ("Check Now", { model.nowPlaying.refreshNow() }))
                card(symbol: "calendar", title: "Calendar", detail: "Your next events in Calendar and Up Next.", granted: calendarGranted, action: ("Allow", requestCalendar))
                card(symbol: "location", title: "Location", detail: "Local weather and sunrise times. Or type a city later.", granted: model.weather.currentLocation != nil, action: ("Allow", { model.weather.requestLocation() }))
            }
            OnboardingButton(title: "Continue", action: next)
        }
        .padding(.horizontal, 60)
    }

    private func requestCalendar() {
        Task {
            calendarGranted = (try? await EKEventStore().requestFullAccessToEvents()) ?? false
        }
    }

    private func card(symbol: String, title: String, detail: String, granted: Bool, action: (String, () -> Void)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(granted ? Theme.moss : Theme.brass)
                .contentTransition(.symbolEffect(.replace))
            Text(title).font(Theme.Typeface.title(16))
            Text(detail).font(Theme.Typeface.body).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !granted {
                Button(action.0, action: action.1).buttonStyle(.glass)
            } else {
                Text("Ready").font(Theme.Typeface.caption).foregroundStyle(Theme.moss)
            }
        }
        .padding(20)
        .frame(width: 270, height: 230, alignment: .topLeading)
        .glass(cornerRadius: 22)
        .animation(Theme.Motion.lively, value: granted)
    }
}

// MARK: - 5. Starter layout

private struct LayoutScene: View {
    let finish: (StarterLayout?) -> Void
    @State private var choice: StarterLayout = .listening

    var body: some View {
        VStack(spacing: 30) {
            VStack(spacing: 8) {
                Text("Pick a starting point.")
                    .font(Theme.Typeface.display(38))
                    .displayTracking(38)
                Text("Everything can be moved, resized or swapped later. Right-click any widget, or use the menu bar.")
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 18) {
                ForEach(StarterLayout.allCases) { layout in
                    Button { choice = layout } label: { tile(layout) }
                        .buttonStyle(.plain)
                }
            }
            HStack(spacing: 14) {
                Button("Start empty") { finish(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                OnboardingButton(title: "Put it on my desktop") { finish(choice) }
            }
        }
    }

    private func tile(_ layout: StarterLayout) -> some View {
        let selected = layout == choice
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Array(layout.symbols.prefix(5).enumerated()), id: \.offset) { _, symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 34, height: 34)
                        .glass(cornerRadius: 9)
                }
            }
            Text(layout.title).font(Theme.Typeface.title(16))
            Text(layout.summary).font(Theme.Typeface.body).foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .frame(width: 270, height: 170, alignment: .topLeading)
        .glass(cornerRadius: 22, tint: selected ? Theme.ember : nil)
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(selected ? Theme.ember : .clear, lineWidth: 1.5))
        .scaleEffect(selected ? 1.03 : 1)
        .animation(Theme.Motion.lively, value: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
