import SwiftUI

/// Liquid Glass helpers. On iOS 26+ these use the real `.glassEffect` material;
/// on earlier systems they degrade gracefully to a thin material so the app
/// still builds and runs.
extension View {

    @ViewBuilder
    func liquidGlass<S: Shape>(_ shape: S,
                               tint: Color? = nil,
                               interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            var glass: Glass = .regular
            if let tint { glass = glass.tint(tint) }
            if interactive { glass = glass.interactive() }
            self.glassEffect(glass, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    func liquidGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        liquidGlass(Capsule(), tint: tint, interactive: interactive)
    }
}

/// A container that, on iOS 26, lets adjacent glass elements blend and morph.
/// Falls back to a plain layout otherwise.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension Color {
    static let arAccent = Color(red: 0.62, green: 0.55, blue: 0.95)
}
