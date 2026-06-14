import RealityKit
import UIKit

/// Builds physically-based materials. With `environmentTexturing = .automatic`
/// on the AR session, metallic / smooth materials automatically pick up
/// image-based reflections of the real room.
enum MaterialFactory {

    static func make(_ kind: SurfaceMaterial) -> RealityKit.Material {
        switch kind {
        case .matte:
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(red: 0.62, green: 0.55, blue: 0.95, alpha: 1))
            m.roughness = 0.9
            m.metallic = 0.0
            return m

        case .metal:
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(white: 0.9, alpha: 1))
            m.roughness = 0.12
            m.metallic = 1.0
            return m

        case .glass:
            // RealityKit exposes no true refraction/IOR parameter, and AR
            // passthrough can't be sampled behind content — so we sell "glass"
            // with high transmission plus a mirror-smooth clearcoat that catches
            // the live room reflections (via `environmentTexturing = .automatic`).
            // That gives the bright Fresnel edges + see-through body that read as
            // refraction, even though light isn't physically bent.
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(red: 0.90, green: 0.96, blue: 1.0, alpha: 1)) // faint cool glass tint
            m.roughness = 0.0           // mirror-sharp so reflections distort like a lens
            m.metallic = 0.0
            m.blending = .transparent(opacity: 0.15) // mostly see-through
            m.clearcoat = 1.0           // glossy surface coat = strong edge reflections
            m.clearcoatRoughness = 0.02
            return m

        case .rubber:
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
            m.roughness = 0.7
            m.metallic = 0.0
            return m
        }
    }

    /// A material for paint strokes: the chosen colour, finished with the chosen
    /// surface's look (matte / metal / glass / rubber).
    static func paint(_ color: UIColor, kind: SurfaceMaterial) -> RealityKit.Material {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        switch kind {
        case .metal:
            m.metallic = 1.0
            m.roughness = 0.2
        case .glass:
            m.metallic = 0.0
            m.roughness = 0.0
            m.blending = .transparent(opacity: 0.45)
            m.clearcoat = 1.0
            m.clearcoatRoughness = 0.05
        case .rubber:
            m.metallic = 0.0
            m.roughness = 0.85
        case .matte:
            m.metallic = 0.0
            m.roughness = 0.8
            m.emissiveColor = .init(color: color)
            m.emissiveIntensity = 0.25   // a touch of glow so lines pop in AR
        }
        return m
    }

    /// Physical surface friction / bounce characteristics per material.
    static func physics(_ kind: SurfaceMaterial, restitution: Float) -> PhysicsMaterialResource {
        switch kind {
        case .rubber: return .generate(friction: 0.9, restitution: max(restitution, 0.7))
        case .metal:  return .generate(friction: 0.4, restitution: restitution * 0.6)
        case .glass:  return .generate(friction: 0.2, restitution: restitution)
        case .matte:  return .generate(friction: 0.6, restitution: restitution)
        }
    }
}
