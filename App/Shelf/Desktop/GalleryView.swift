import ShelfCore
import SwiftUI

/// Searchable widget gallery with live previews. Click a tile to drop it on the desktop.
struct GalleryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var category: WidgetCategory? = .music
    @State private var hovered: String?

    private var results: [WidgetDescriptor] {
        let base = category.map(WidgetCatalog.widgets(in:)) ?? WidgetCatalog.all
        guard !query.isEmpty else { return base }
        return WidgetCatalog.all.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Widgets")
                    .font(Theme.Typeface.display(30))
                    .displayTracking(30)
                Spacer()
                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(width: 220)
                    .glassCapsule()
            }
            HStack(spacing: 8) {
                ForEach(WidgetCategory.allCases) { item in
                    Button {
                        withAnimation(Theme.Motion.standard) { category = item; query = "" }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(Theme.Typeface.title(12))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(category == item ? Color.white : Theme.textSecondary)
                    .glassCapsule(tint: category == item ? Theme.ember : nil, interactive: true)
                }
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 196), spacing: Theme.Space.m)], spacing: Theme.Space.l) {
                    ForEach(results) { descriptor in
                        tile(descriptor)
                    }
                }
                .padding(.vertical, Theme.Space.s)
            }
            .scrollIndicators(.never)
        }
        .padding(Theme.Space.l)
        .foregroundStyle(Theme.textPrimary)
        .glass(cornerRadius: 30)
    }

    private func tile(_ descriptor: WidgetDescriptor) -> some View {
        let isHovered = hovered == descriptor.kind
        return Button {
            model.add(kind: descriptor.kind)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                preview(descriptor)
                    .frame(width: 180, height: 120)
                    .scaleEffect(isHovered ? 1.04 : 1)
                    .shadow(color: .black.opacity(isHovered ? 0.35 : 0.2), radius: isHovered ? 14 : 6, y: 4)
                Text(descriptor.name).font(Theme.Typeface.title(13))
                Text(descriptor.summary)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(width: 180)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? descriptor.kind : (hovered == descriptor.kind ? nil : hovered) }
        .animation(Theme.Motion.lively, value: isHovered)
        .accessibilityLabel("Add \(descriptor.name)")
        .accessibilityHint(descriptor.summary)
    }

    /// A live, scaled-down render of the widget at its default size.
    private func preview(_ descriptor: WidgetDescriptor) -> some View {
        let side = descriptor.defaultSize.side
        let size = CGSize(width: side.width, height: side.height)
        let scale = min(180 / size.width, 120 / size.height)
        let context = WidgetContext(id: UUID(), config: descriptor.defaultConfig, size: size, isEditing: false) { _, _ in }
        return descriptor.make(context)
            .frame(width: size.width, height: size.height)
            .clipShape(.rect(cornerRadius: descriptor.isFreeform ? 0 : Theme.Radius.widget, style: .continuous))
            .allowsHitTesting(false)
            .scaleEffect(scale)
            .frame(width: size.width * scale, height: size.height * scale)
    }
}
