import ShelfCore
import SwiftUI

/// Hosts one widget inside its panel: the card, its shadow, and edit-mode chrome.
struct WidgetContainer: View {
    let id: UUID
    let host: DesktopHost
    @Environment(AppModel.self) private var model
    @State private var showingSettings = false
    @State private var isDragging = false
    @State private var wiggle = false

    var body: some View {
        if let instance = model.instance(id), let descriptor = WidgetCatalog.descriptor(for: instance.kind) {
            GeometryReader { proxy in
                let size = CGSize(width: max(0, proxy.size.width - WidgetPanel.inset * 2),
                                  height: max(0, proxy.size.height - WidgetPanel.inset * 2))
                let context = WidgetContext(id: id, config: instance.config, size: size, isEditing: model.isEditing) { key, value in
                    model.updateConfig(id, key: key, value: value)
                }
                descriptor.make(context)
                    .frame(width: size.width, height: size.height)
                    .clipShape(.rect(cornerRadius: descriptor.isFreeform ? 0 : Theme.Radius.widget, style: .continuous))
                    .shadow(color: .black.opacity(isDragging ? 0.45 : 0.28), radius: isDragging ? 18 : 10, y: isDragging ? 10 : 5)
                    .scaleEffect(isDragging ? 1.03 : 1)
                    .rotationEffect(.degrees(model.isEditing && !isDragging && wiggle ? 0.6 : 0))
                    .allowsHitTesting(!model.isEditing)
                    .overlay { if model.isEditing { editLayer(instance, descriptor: descriptor, size: size) } }
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .animation(Theme.Motion.lift, value: isDragging)
                    .contextMenu { menu(instance, descriptor: descriptor) }
            }
            .onChange(of: model.isEditing, initial: true) { _, editing in
                withAnimation(editing ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true) : .default) {
                    wiggle = editing
                }
            }
            .popover(isPresented: $showingSettings) {
                WidgetInspector(id: id, descriptor: descriptor).environment(model)
            }
        }
    }

    @ViewBuilder
    private func editLayer(_ instance: WidgetInstance, descriptor: WidgetDescriptor, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.Radius.widget, style: .continuous)
                .fill(Color.white.opacity(0.001))
                .strokeBorder(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { _ in
                            if !isDragging { isDragging = true; host.beginInteraction(id) }
                            host.drag(id)
                        }
                        .onEnded { _ in
                            isDragging = false
                            host.endInteraction(id)
                        }
                )

            HStack(spacing: 6) {
                chromeButton("minus", label: "Remove \(descriptor.name)", tint: Theme.ember) { model.remove(id) }
                if !descriptor.options.isEmpty {
                    chromeButton("slider.horizontal.3", label: "\(descriptor.name) settings") { showingSettings = true }
                }
            }
            .offset(x: -10, y: -10)

            chromeButton("arrow.down.right", label: "Resize") {}
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { _ in
                            if !isDragging { isDragging = true; host.beginInteraction(id) }
                            host.resize(id)
                        }
                        .onEnded { _ in
                            isDragging = false
                            host.endInteraction(id)
                        }
                )
                .position(x: size.width - 4, y: size.height - 4)
        }
    }

    private func chromeButton(_ symbol: String, label: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glassCircle(tint: tint, interactive: true)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func menu(_ instance: WidgetInstance, descriptor: WidgetDescriptor) -> some View {
        Text(descriptor.name)
        if descriptor.sizes.count > 1 {
            Menu("Size") {
                ForEach(descriptor.sizes, id: \.self) { size in
                    Button(size.label) { model.resize(id, to: size) }
                }
            }
        }
        if !descriptor.options.isEmpty {
            Button("Settings…") { showingSettings = true }
        }
        Button(instance.isLocked ? "Unlock Position" : "Lock Position") { model.toggleLock(id) }
        Divider()
        Button(model.isEditing ? "Done Editing" : "Edit Widgets") { model.isEditing.toggle() }
        Button("Remove Widget", role: .destructive) { model.remove(id) }
    }
}
