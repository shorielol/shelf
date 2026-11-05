import ShelfCore
import SwiftUI

/// Incomplete reminders with check circles that really complete them. Tap again within a moment to undo.
struct RemindersWidget: View {
    let context: WidgetContext
    @State private var store = RemindersStore.shared
    @State private var completing: [String: Task<Void, Never>] = [:]

    private static let rowHeight: CGFloat = 32
    private static let commitDelay: Duration = .milliseconds(900)

    private var listName: String { context.string("list", "").trimmingCharacters(in: .whitespaces) }

    var body: some View {
        WidgetCard {
            switch store.access {
            case .granted: content
            case .notDetermined, .denied:
                WidgetPlaceholder(
                    symbol: "checklist",
                    title: "Your reminders, ticked off here",
                    detail: store.access == .denied ? "Turn on Shelf in Privacy & Security." : nil,
                    action: (store.access == .denied ? "Open Settings" : "Allow Reminders", { store.requestAccess() })
                )
            }
        }
        .onAppear { store.activate() }
    }

    @ViewBuilder
    private var content: some View {
        if !listName.isEmpty, store.hasLoaded, !store.listTitles.contains(where: { $0.caseInsensitiveCompare(listName) == .orderedSame }) {
            WidgetPlaceholder(symbol: "list.bullet", title: "No list called “\(listName)”", detail: "Check the name in settings.")
        } else {
            let items = visibleItems
            let limit = max(1, Int((context.size.height - 56) / Self.rowHeight))
            VStack(alignment: .leading, spacing: 0) {
                header(count: items.count)
                    .padding(.bottom, Theme.Space.xs)
                if items.isEmpty && store.hasLoaded {
                    allDone
                } else {
                    ForEach(items.prefix(limit)) { item in
                        ReminderRow(item: item, isDone: completing[item.id] != nil, showsList: listName.isEmpty) { toggle(item) }
                            .frame(height: Self.rowHeight)
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .offset(x: 16))))
                    }
                    if items.count > limit {
                        Text("\(items.count - limit) more")
                            .font(Theme.Typeface.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.leading, 32)
                    }
                }
                Spacer(minLength: 0)
            }
            .animation(Theme.Motion.standard, value: items.map(\.id))
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: store.items) { _, current in
                let live = Set(current.map(\.id))
                completing = completing.filter { live.contains($0.key) }
            }
        }
    }

    private var visibleItems: [ReminderItem] {
        guard !listName.isEmpty else { return store.items }
        return store.items.filter { $0.listTitle.caseInsensitiveCompare(listName) == .orderedSame }
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(listName.isEmpty ? "Reminders" : listName)
                .font(Theme.Typeface.display(17))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(count)")
                .font(Theme.Typeface.numeral(17))
                .foregroundStyle(Theme.ember)
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(listName.isEmpty ? "Reminders" : listName), \(count) to do")
    }

    private var allDone: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.moss)
            Text("All done.")
                .font(Theme.Typeface.display(16, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func toggle(_ item: ReminderItem) {
        if let pending = completing[item.id] {
            pending.cancel()
            completing[item.id] = nil
            return
        }
        Sounds.shared.play(.pop, volume: 0.3)
        let store = store
        completing[item.id] = Task {
            try? await Task.sleep(for: Self.commitDelay)
            guard !Task.isCancelled else { return }
            store.complete(item.id)
        }
    }
}

private struct ReminderRow: View {
    let item: ReminderItem
    let isDone: Bool
    let showsList: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Button(action: toggle) {
                CheckCircle(isOn: isDone, color: item.color)
                    .frame(width: 24, height: 24)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDone ? "Undo complete \(item.title)" : "Complete \(item.title)")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(Theme.Typeface.title(12.5))
                    .foregroundStyle(isDone ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(isDone, color: Theme.textTertiary)
                    .lineLimit(1)
                if let caption {
                    Text(caption.text)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(caption.urgent && !isDone ? Theme.ember : Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if item.isFlagged {
                Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(Theme.brass).accessibilityLabel("Flagged")
            }
        }
        .animation(Theme.Motion.standard, value: isDone)
    }

    private var caption: (text: String, urgent: Bool)? {
        let list = showsList ? item.listTitle : nil
        guard let due = item.due else { return list.map { ($0, false) } }
        let calendar = Calendar.current
        let now = Date()
        let hasTime = calendar.component(.hour, from: due) != 0 || calendar.component(.minute, from: due) != 0
        let when: String
        let urgent: Bool
        if calendar.isDateInToday(due) {
            when = hasTime ? "Today \(EventTime.clock(due))" : "Today"
            urgent = true
        } else if due < now {
            when = "Overdue"
            urgent = true
        } else if calendar.isDateInTomorrow(due) {
            when = "Tomorrow"
            urgent = false
        } else {
            when = due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            urgent = false
        }
        return ([when, list].compactMap { $0 }.joined(separator: " · "), urgent)
    }
}

/// A ring that fills, draws a tick and throws off a soft burst when checked.
private struct CheckCircle: View {
    let isOn: Bool
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isOn ? color : Theme.textTertiary, lineWidth: 1.5)
                .frame(width: 18, height: 18)
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .scaleEffect(isOn ? 1 : 0.2)
                .opacity(isOn ? 1 : 0)
                .animation(Theme.Motion.lively, value: isOn)
            Checkmark()
                .trim(from: 0, to: isOn ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 9, height: 8)
                .animation(.easeOut(duration: 0.22).delay(isOn ? 0.08 : 0), value: isOn)
            if !reduceMotion {
                Circle()
                    .stroke(color, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .keyframeAnimator(initialValue: Burst(), trigger: isOn) { ring, burst in
                        ring.scaleEffect(burst.scale).opacity(burst.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            LinearKeyframe(1, duration: 0.01)
                            CubicKeyframe(1.9, duration: 0.45)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(isOn ? 0.8 : 0, duration: 0.01)
                            CubicKeyframe(0, duration: 0.45)
                        }
                    }
                    .allowsHitTesting(false)
            }
        }
    }

    private struct Burst {
        var scale: CGFloat = 1
        var opacity: Double = 0
    }
}

nonisolated struct Checkmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
