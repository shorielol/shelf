import ShelfCore
import SwiftUI

/// A paper note you can type on. Shows light Markdown when you're not editing.
/// The bottom-right corner is folded over and lifts a little when you hover.
struct StickyWidget: View {
    let context: WidgetContext
    @State private var draft = ""
    @State private var saveTask: Task<Void, Never>?
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private static let saveDelay: Duration = .milliseconds(500)

    enum Paper: String, CaseIterable {
        case butter, peach, sage, sky, graphite

        var label: String { rawValue.capitalized }

        var colors: [Color] {
            switch self {
            case .butter: [Color(red: 0.98, green: 0.92, blue: 0.64), Color(red: 0.95, green: 0.86, blue: 0.54)]
            case .peach: [Color(red: 0.98, green: 0.83, blue: 0.72), Color(red: 0.95, green: 0.75, blue: 0.63)]
            case .sage: [Color(red: 0.83, green: 0.88, blue: 0.75), Color(red: 0.75, green: 0.82, blue: 0.67)]
            case .sky: [Color(red: 0.80, green: 0.88, blue: 0.94), Color(red: 0.70, green: 0.81, blue: 0.90)]
            case .graphite: [Color(red: 0.23, green: 0.22, blue: 0.21), Color(red: 0.16, green: 0.155, blue: 0.15)]
            }
        }

        var ink: Color {
            self == .graphite ? Theme.cream.opacity(0.92) : Color(red: 0.23, green: 0.19, blue: 0.15)
        }
    }

    private var paper: Paper { Paper(rawValue: context.string("paper", "butter")) ?? .butter }
    private var stored: String { context.string("text", "") }
    private var fold: CGFloat { (isHovering ? 0.2 : 0.14) * min(context.unit, 200) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            PaperSheet(paper: paper, fold: fold)
            editor
                .padding(.horizontal, Theme.Space.m - 5)
                .padding(.top, Theme.Space.m - 2)
                .padding(.bottom, fold * 0.8)
        }
        .rotationEffect(.degrees(tilt))
        .scaleEffect(tilt == 0 ? 1 : 0.965)
        .onHover { hovering in withAnimation(Theme.Motion.lift) { isHovering = hovering } }
        .onAppear { draft = stored }
        .onChange(of: stored) { _, value in if !isFocused, value != draft { draft = value } }
        .onChange(of: draft) { _, _ in scheduleSave() }
        .onChange(of: isFocused) { _, focused in if !focused { flush() } }
        .onDisappear { flush() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sticky note")
    }

    // MARK: Text

    private var font: Font { Theme.Typeface.display(context.unit < 200 ? 14 : 16, weight: .regular) }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $draft)
                .font(font)
                .foregroundStyle(paper.ink)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .textEditorStyle(.plain)
                .tint(Theme.ember)
                .focused($isFocused)
                .opacity(isFocused ? 1 : 0)
                .accessibilityLabel("Note text")
            if !isFocused {
                rendered
                    .padding(.horizontal, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .contentShape(.rect)
                    .onTapGesture { isFocused = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Edits the note")
            }
        }
    }

    @ViewBuilder
    private var rendered: some View {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text("Write something…").font(font).foregroundStyle(paper.ink.opacity(0.4))
        } else {
            Text(StickyMarkdown.render(draft))
                .font(font)
                .foregroundStyle(paper.ink)
                .lineSpacing(2)
        }
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        guard draft != stored else { return }
        let text = draft
        let update = context.update
        saveTask = Task {
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            update("text", .string(text))
        }
    }

    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        if draft != stored { context.update("text", .string(draft)) }
    }

    // MARK: Tilt

    /// A small, stable lean per note, so a row of them doesn't look stamped out.
    private var tilt: Double {
        guard context.bool("tilt", true) else { return 0 }
        let bytes = context.id.uuid
        let seed = Double(bytes.0) / 255
        return (seed - 0.5) * 3.2
    }
}

/// Bold, italic and "- " bullets, line by line.
enum StickyMarkdown {
    static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        var result = AttributedString()
        let lines = text.components(separatedBy: "\n")
        for (index, raw) in lines.enumerated() {
            var line = raw
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "•  " + line.dropFirst(2)
            }
            result += (try? AttributedString(markdown: line, options: options)) ?? AttributedString(line)
            if index < lines.count - 1 { result += AttributedString("\n") }
        }
        return result
    }
}

/// The paper itself: tinted stock, faint grain, and a folded corner.
private struct PaperSheet: View {
    let paper: StickyWidget.Paper
    let fold: CGFloat

    var body: some View {
        let sheet = FoldedPaper(fold: fold, radius: 6)
        ZStack {
            sheet
                .fill(LinearGradient(colors: paper.colors, startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.28), radius: 9, x: 0, y: 5)
            PaperGrain(ink: paper.ink).clipShape(sheet)
            // Light catching the top edge.
            sheet
                .fill(LinearGradient(colors: [.white.opacity(paper == .graphite ? 0.06 : 0.22), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.3)))
            CornerFlap(fold: fold)
                .fill(LinearGradient(colors: [paper.colors[1].mix(with: .black, by: 0.12), paper.colors[0].mix(with: .white, by: 0.25)],
                                     startPoint: .bottomTrailing, endPoint: .topLeading))
                .shadow(color: .black.opacity(0.25), radius: 2.5, x: -1.5, y: -1.5)
        }
        .accessibilityHidden(true)
    }
}

/// A rounded sheet with its bottom-right corner cut on the diagonal.
nonisolated struct FoldedPaper: Shape {
    var fold: CGFloat
    var radius: CGFloat

    var animatableData: CGFloat {
        get { fold }
        set { fold = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
        path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// The folded-over triangle, lying on the front of the sheet.
nonisolated struct CornerFlap: Shape {
    var fold: CGFloat

    var animatableData: CGFloat {
        get { fold }
        set { fold = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - fold))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - fold, y: rect.maxY - fold),
                          control: CGPoint(x: rect.maxX - fold * 0.45, y: rect.maxY - fold * 1.08))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - fold, y: rect.maxY),
                          control: CGPoint(x: rect.maxX - fold * 1.08, y: rect.maxY - fold * 0.45))
        path.closeSubpath()
        return path
    }
}

/// Fixed-seed fibres and specks. Only redraws when the paper colour changes.
private struct PaperGrain: View, Equatable {
    let ink: Color

    var body: some View {
        Canvas { context, size in
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double(state >> 33) / Double(1 << 31)
            }
            for _ in 0..<160 {
                let x = next() * size.width, y = next() * size.height
                let length = 3 + next() * 9, angle = next() * .pi
                var fibre = Path()
                fibre.move(to: CGPoint(x: x, y: y))
                fibre.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
                context.stroke(fibre, with: .color(ink.opacity(0.025 + next() * 0.03)), lineWidth: 0.5)
            }
            for _ in 0..<220 {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 0.8, height: 0.8)
                context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(0.05)))
            }
        }
        .allowsHitTesting(false)
    }
}
