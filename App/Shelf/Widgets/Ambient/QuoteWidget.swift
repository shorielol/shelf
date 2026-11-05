import ShelfCore
import SwiftUI

/// One quote a day, set in New York with a hanging ember quotation mark. Tap for another.
struct QuoteWidget: View {
    let context: WidgetContext
    /// A tapped-in quote, remembered only for the day it was picked on.
    @State private var shuffled: (day: Int, index: Int)?

    private var isSmall: Bool { context.size.width < 250 }
    private var isLarge: Bool { context.size.height > 300 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 3600)) { timeline in
            let day = Self.dayNumber(timeline.date)
            let candidates = candidateIndices
            let index = shuffled.flatMap { $0.day == day ? $0.index : nil } ?? candidates[Self.dayOfYear(timeline.date) % candidates.count]
            let quote = PublicDomainQuotes.all[index]
            WidgetCard(padding: 0) {
                card(quote)
                    .id(index)
                    .transition(.opacity.combined(with: .offset(y: 3)))
            }
            .contentShape(.rect)
            .onTapGesture { shuffle(from: index, day: day, candidates: candidates) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Quote of the day")
            .accessibilityValue("\(quote.text) \(quote.author), \(quote.source)")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Shows another quote")
        }
        .frame(width: context.size.width, height: context.size.height)
    }

    private func card(_ quote: PublicDomainQuote) -> some View {
        let size = fontSize(for: quote)
        return VStack(alignment: .leading, spacing: isSmall ? Theme.Space.s : Theme.Space.m - 4) {
            Text(quote.text)
                .font(Theme.Typeface.display(size, weight: .regular))
                .lineSpacing(size * 0.12)
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(alignment: .topLeading) {
                    // Hangs in the margin so the first letter of the text lines up with everything else.
                    Text("\u{201C}")
                        .font(Theme.Typeface.display(size * 2.3, weight: .bold))
                        .foregroundStyle(Theme.ember)
                        .offset(x: -size * 0.78, y: -size * 0.62)
                        .accessibilityHidden(true)
                }
            attribution(quote)
        }
        .padding(.leading, Theme.Space.m + size * 0.55)
        .padding(.trailing, Theme.Space.m)
        .padding(.top, Theme.Space.m + size * 0.2)
        .padding(.bottom, Theme.Space.m - 2)
    }

    private func attribution(_ quote: PublicDomainQuote) -> some View {
        HStack(spacing: 6) {
            Capsule().fill(Theme.ember).frame(width: 10, height: 1.5)
            Eyebrow(text: quote.author, color: Theme.textSecondary)
                .layoutPriority(1)
            if !isSmall {
                Text(quote.source)
                    .font(Theme.Typeface.display(11, weight: .regular).italic())
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Scales the type to the length of the quote and the room available.
    private func fontSize(for quote: PublicDomainQuote) -> CGFloat {
        let base: CGFloat = isLarge ? 26 : (isSmall ? 15 : 18)
        let comfortable: CGFloat = isLarge ? 110 : (isSmall ? 55 : 90)
        let scale = min(1, sqrt(comfortable / CGFloat(max(1, quote.text.count))))
        return max(isSmall ? 11 : 12, (base * scale).rounded())
    }

    /// A small widget only gets quotes short enough to stay readable.
    private var candidateIndices: [Int] {
        let limit = isSmall ? 72 : (isLarge ? .max : 150)
        let fitting = PublicDomainQuotes.all.indices.filter { PublicDomainQuotes.all[$0].text.count <= limit }
        return fitting.isEmpty ? Array(PublicDomainQuotes.all.indices) : fitting
    }

    private func shuffle(from current: Int, day: Int, candidates: [Int]) {
        let others = candidates.filter { $0 != current }
        guard let next = others.randomElement() else { return }
        Sounds.shared.play(.tick, volume: 0.4)
        withAnimation(.easeInOut(duration: 0.35)) { shuffled = (day, next) }
    }

    private static func dayOfYear(_ date: Date) -> Int {
        Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1
    }

    private static func dayNumber(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.year], from: date)
        return (parts.year ?? 0) * 1000 + dayOfYear(date)
    }
}
