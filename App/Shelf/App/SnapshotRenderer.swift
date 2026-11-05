import AppKit
import ShelfCore
import SwiftUI

/// `Shelf --snapshot <dir>` renders every widget offscreen to PNG and quits. Used for README images and
/// for checking layouts without putting anything on the desktop.
enum SnapshotRenderer {
    static func directory(from arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func run(into directory: URL, model: AppModel) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for descriptor in WidgetCatalog.all {
            for size in descriptor.sizes {
                render(descriptor, size: size, model: model, to: directory.appending(path: "\(descriptor.kind)-\(size.rawValue).png"))
            }
        }
        render(gallery: model, to: directory.appending(path: "gallery.png"))
    }

    private static func render(_ descriptor: WidgetDescriptor, size: WidgetSize, model: AppModel, to url: URL) {
        let side = CGSize(width: size.side.width, height: size.side.height)
        let context = WidgetContext(id: UUID(), config: descriptor.defaultConfig, size: side, isEditing: false) { _, _ in }
        let view = descriptor.make(context)
            .frame(width: side.width, height: side.height)
            .clipShape(.rect(cornerRadius: descriptor.isFreeform ? 0 : Theme.Radius.widget, style: .continuous))
            .padding(28)
            .background(Backdrop())
            .environment(model)
            .environment(\.colorScheme, .dark)
            .environment(\.rendersOffscreen, true)
        write(view, to: url)
    }

    private static func render(gallery model: AppModel, to url: URL) {
        let columns = Array(repeating: GridItem(.fixed(240), spacing: 24), count: 5)
        let view = LazyVGrid(columns: columns, spacing: 24) {
            ForEach(galleryWidgets) { descriptor in
                let side = descriptor.defaultSize.side
                let scale = min(240 / side.width, 200 / side.height)
                descriptor.make(WidgetContext(id: UUID(), config: descriptor.defaultConfig, size: CGSize(width: side.width, height: side.height), isEditing: false) { _, _ in })
                    .frame(width: side.width, height: side.height)
                    .clipShape(.rect(cornerRadius: descriptor.isFreeform ? 0 : Theme.Radius.widget, style: .continuous))
                    .scaleEffect(scale)
                    .frame(width: 240, height: 200)
            }
        }
        .padding(40)
        .background(Backdrop())
        .environment(model)
        .environment(\.colorScheme, .dark)
        .environment(\.rendersOffscreen, true)
        write(view, to: url)
    }

    /// `SHELF_GALLERY_KINDS=a,b` limits the gallery image to those widgets.
    private static var galleryWidgets: [WidgetDescriptor] {
        guard let filter = ProcessInfo.processInfo.environment["SHELF_GALLERY_KINDS"] else { return WidgetCatalog.all }
        let kinds = Set(filter.split(separator: ",").map(String.init))
        return WidgetCatalog.all.filter { kinds.contains($0.kind) }
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        // App icons can push the render into a wide-gamut format; convert to sRGB so the PNG reads correctly everywhere.
        guard let image = renderer.cgImage,
              let srgb = NSBitmapImageRep(cgImage: image).converting(to: .sRGB, renderingIntent: .default),
              let png = srgb.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}

/// A warm, wallpaper-like backdrop so glass has something to sit on in snapshots.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.22), Color(red: 0.12, green: 0.11, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Theme.ember.opacity(0.35), .clear], center: .topTrailing, startRadius: 10, endRadius: 600)
        }
    }
}
