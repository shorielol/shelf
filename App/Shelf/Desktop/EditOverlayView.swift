import ShelfCore
import SwiftUI

/// Edit mode backdrop: a dimmed dot grid, a floating toolbar, and the gallery on the main display.
struct EditOverlayView: View {
    let isMain: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .overlay { DotGrid(step: model.snapToGrid ? 24 : 0) }
                .ignoresSafeArea()
                .onTapGesture { model.showingGallery = false }
                .transition(.opacity)

            if isMain {
                toolbar
                    .padding(.top, 54)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isMain && model.showingGallery {
                GalleryView()
                    .frame(maxWidth: 920, maxHeight: 560)
                    .padding(.top, 120)
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(Theme.Motion.lively, value: model.showingGallery)
    }

    private var toolbar: some View {
        @Bindable var model = model
        return GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.showingGallery.toggle()
                } label: {
                    Label("Add Widget", systemImage: "plus")
                        .font(Theme.Typeface.title(13))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassCapsule(tint: Theme.ember, interactive: true)

                Toggle(isOn: $model.snapToGrid) {
                    Label("Snap", systemImage: "square.grid.3x3")
                        .font(Theme.Typeface.title(13))
                }
                .toggleStyle(.button)
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassCapsule(interactive: true)

                Button {
                    model.isEditing = false
                } label: {
                    Text("Done")
                        .font(Theme.Typeface.title(13))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .glassCapsule(interactive: true)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct DotGrid: View {
    let step: CGFloat

    var body: some View {
        Canvas { context, size in
            guard step > 0 else { return }
            var path = Path()
            for x in stride(from: step, to: size.width, by: step) {
                for y in stride(from: step, to: size.height, by: step) {
                    path.addEllipse(in: CGRect(x: x - 0.75, y: y - 0.75, width: 1.5, height: 1.5))
                }
            }
            context.fill(path, with: .color(.white.opacity(0.22)))
        }
        .allowsHitTesting(false)
    }
}
