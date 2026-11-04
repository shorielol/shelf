import SwiftUI

/// Liquid Glass surface that falls back to a solid raised fill under Reduce Transparency.
struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Theme.graphiteRaised, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1))
        } else {
            content.glassEffect(glass, in: shape)
        }
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.35)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    func glass(cornerRadius: CGFloat = Theme.Radius.widget, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), tint: tint, interactive: interactive))
    }

    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: Capsule(style: .continuous), tint: tint, interactive: interactive))
    }

    func glassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: Circle(), tint: tint, interactive: interactive))
    }
}
