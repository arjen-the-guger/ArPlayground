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
            // Real transparency + refraction reads beautifully against passthrough.
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(white: 1.0, alpha: 1))
            m.roughness = 0.05
            m.metallic = 0.0
            m.blending = .transparent(opacity: 0.25)
            m.clearcoat = 1.0
            m.clearcoatRoughness = 0.05
            return m

        case .rubber:
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: UIColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
            m.roughness = 0.7
            m.metallic = 0.0
            return m
        }
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
