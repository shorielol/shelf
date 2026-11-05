import AppKit
import ShelfCore
import SwiftUI

/// A small dock of apps, folders and links. Icons swell under the pointer like the real one.
struct LauncherWidget: View {
    let context: WidgetContext
    @State private var items: [LaunchItem] = []
    @State private var hoverX: CGFloat?
    @State private var hopping: String?

    static let defaultItems = "Safari, Notes, Music, ~/Downloads"
    private static let maxItems = 8

    private var source: String { context.string("items", Self.defaultItems) }

    var body: some View {
        WidgetCard(padding: Theme.Space.s) {
            Group {
                if items.isEmpty {
                    WidgetPlaceholder(symbol: "square.grid.2x2", title: "Add apps or folders", detail: context.isWide ? "List them in settings, separated by commas." : nil)
                } else if context.isWide {
                    dock
                } else {
                    grid
                }
            }
        }
        .task(id: source) { items = LaunchItem.resolve(source, limit: Self.maxItems) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Launcher")
    }

    // MARK: Medium: a dock row with magnification

    private var dock: some View {
        GeometryReader { proxy in
            let count = CGFloat(items.count)
            let spacing: CGFloat = 6
            let icon = min(58, (proxy.size.width - 24 - spacing * (count - 1)) / count)
            let rowWidth = icon * count + spacing * (count - 1)
            let originX = (proxy.size.width - rowWidth) / 2
            ZStack(alignment: .bottom) {
                shelf(width: rowWidth + 20)
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let center = originX + CGFloat(index) * (icon + spacing) + icon / 2
                        tile(item, size: icon, scale: magnification(center: center, icon: icon), showsName: isHovered(center: center, icon: icon))
                    }
                }
                .padding(.bottom, 14)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hoverX = point.x
                case .ended: hoverX = nil
                }
            }
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: hoverX)
        }
    }

    private func shelf(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.white.opacity(0.16)).frame(height: 1)
            LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom).frame(height: 8)
        }
        .frame(width: width)
        .padding(.bottom, 4)
        .accessibilityHidden(true)
    }

    /// Cosine falloff around the pointer, like the Dock: up to 1.45x right under it.
    private func magnification(center: CGFloat, icon: CGFloat) -> CGFloat {
        guard let hoverX else { return 1 }
        let reach = icon * 1.8
        let distance = abs(hoverX - center)
        guard distance < reach else { return 1 }
        return 1 + 0.45 * (cos(distance / reach * .pi) + 1) / 2
    }

    private func isHovered(center: CGFloat, icon: CGFloat) -> Bool {
        guard let hoverX else { return false }
        return abs(hoverX - center) < icon / 2
    }

    // MARK: Small: a 2x2 grid

    private var grid: some View {
        let icon = (context.unit - 16 - 24) / 2
        return Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(Array(stride(from: 0, to: min(items.count, 4), by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(items[start..<min(start + 2, items.count)]) { item in
                        GridTile(item: item, size: icon, isHopping: hopping == item.id) { open(item) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tile(_ item: LaunchItem, size: CGFloat, scale: CGFloat, showsName: Bool) -> some View {
        Button { open(item) } label: {
            LaunchIcon(item: item)
                .frame(width: size, height: size)
                .scaleEffect(scale, anchor: .bottom)
                .offset(y: hopping == item.id ? -size * 0.28 : 0)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if showsName {
                Text(item.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .glassCapsule()
                    .offset(y: -size * (scale - 1) - 24)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(scale)
        .accessibilityLabel(item.accessibilityLabel)
        .help(item.name)
    }

    private func open(_ item: LaunchItem) {
        guard let url = item.url else { return }
        NSWorkspace.shared.open(url)
        Sounds.shared.play(.tick, volume: 0.4)
        withAnimation(.spring(response: 0.18, dampingFraction: 0.6)) { hopping = item.id }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { hopping = nil }
        }
    }
}

private struct GridTile: View {
    let item: LaunchItem
    let size: CGFloat
    let isHopping: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            LaunchIcon(item: item)
                .frame(width: size, height: size)
                .scaleEffect(isHovering ? 1.12 : 1)
                .offset(y: isHopping ? -size * 0.16 : 0)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) { isHovering = hovering } }
        .accessibilityLabel(item.accessibilityLabel)
        .help(item.name)
    }
}

private struct LaunchIcon: View {
    let item: LaunchItem

    var body: some View {
        if let icon = item.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .overlay(Image(systemName: "questionmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textTertiary))
                .padding(4)
        }
    }
}

/// One launcher entry, resolved from what the user typed.
struct LaunchItem: Identifiable {
    let id: String
    let name: String
    let url: URL?
    let icon: NSImage?

    var accessibilityLabel: String { url == nil ? "\(name), not found" : "Open \(name)" }

    static func resolve(_ source: String, limit: Int) -> [LaunchItem] {
        let entries = source.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return entries.prefix(limit).enumerated().map { index, entry in item(for: entry, id: "\(index):\(entry)") }
    }

    private static func item(for entry: String, id: String) -> LaunchItem {
        let workspace = NSWorkspace.shared
        if entry.lowercased().hasPrefix("https://"), let url = URL(string: entry), url.host() != nil {
            let browser = workspace.urlForApplication(toOpen: url)
            return LaunchItem(id: id, name: url.host() ?? entry, url: url, icon: browser.map { workspace.icon(forFile: $0.path) })
        }
        if entry.hasPrefix("/") || entry.hasPrefix("~") {
            let path = (entry as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { return missing(entry, id: id) }
            let url = URL(fileURLWithPath: path)
            return LaunchItem(id: id, name: FileManager.default.displayName(atPath: path), url: url, icon: workspace.icon(forFile: path))
        }
        guard let app = application(named: entry) else { return missing(entry, id: id) }
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        return LaunchItem(id: id, name: name, url: app, icon: workspace.icon(forFile: app.path))
    }

    private static func missing(_ entry: String, id: String) -> LaunchItem {
        LaunchItem(id: id, name: entry, url: nil, icon: nil)
    }

    private static let searchFolders = [
        "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications", ("~/Applications" as NSString).expandingTildeInPath,
    ]

    /// A bundle id, an app name, or as a last resort Apple's own bundle id for that name.
    private static func application(named entry: String) -> URL? {
        let workspace = NSWorkspace.shared
        if entry.contains("."), !entry.contains(" "), let url = workspace.urlForApplication(withBundleIdentifier: entry) {
            return url
        }
        let file = entry.hasSuffix(".app") ? entry : entry + ".app"
        for folder in searchFolders {
            let path = (folder as NSString).appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        let compact = entry.replacingOccurrences(of: " ", with: "")
        return workspace.urlForApplication(withBundleIdentifier: "com.apple.\(compact)")
    }
}
