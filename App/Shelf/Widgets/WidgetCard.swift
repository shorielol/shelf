import SwiftUI

/// The standard widget surface: Liquid Glass at the system widget corner radius.
struct WidgetCard<Content: View>: View {
    var tint: Color?
    var padding: CGFloat = Theme.Space.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glass(cornerRadius: Theme.Radius.widget, tint: tint)
    }
}

/// Small caps label used as a widget eyebrow.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.textSecondary

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typeface.eyebrow)
            .tracking(0.6)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

/// Shown by widgets that need a permission or data they don't have yet.
struct WidgetPlaceholder: View {
    let symbol: String
    let title: String
    var detail: String?
    var action: (label: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .symbolEffect(.pulse, options: .repeating.speed(0.4))
            Text(title)
                .font(Theme.Typeface.title(13))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            if let action {
                Button(action.label, action: action.run)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
