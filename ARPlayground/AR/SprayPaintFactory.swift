import RealityKit
import UIKit

/// Builds spray-paint "dabs": flat soft-edged circular decals that stick to a
/// real surface. The further the surface is from the camera, the larger and
/// **blurrier** the dab (a wider, softer alpha falloff); the closer it is, the
/// smaller and crisper — mimicking how a real spray cone spreads with distance.
///
/// The soft circle lives in the alpha channel of a runtime-generated radial
/// gradient texture; the colour is applied as a tint, so textures can be cached
/// purely by their blur level and reused across every colour.
@MainActor
enum SprayPaintFactory {

    /// Cache of gradient textures keyed by a quantized blur bucket.
    private static var textureCache: [Int: TextureResource] = [:]

    /// A circular dab sized + blurred for `distance` (camera→surface metres),
    /// tinted `color`. Lay it on the surface (its +Y is the surface normal).
    static func dab(color: UIColor, distance: Float) -> ModelEntity {
        let d = max(0.15, min(distance, 3.0))
        // Softness 0 (crisp) … ~0.9 (very blurry), growing with distance.
        let softness = min(max((d - 0.25) / 2.0, 0.06), 0.9)

        var mat = UnlitMaterial(color: color)
        if let tex = texture(softness: softness) {
            mat.color = .init(tint: color, texture: .init(tex))
        }
        mat.blending = .transparent(opacity: 1.0)

        let size = 0.04 + d * 0.05   // farther → bigger splat
        let plane = ModelEntity(mesh: .generatePlane(width: size, depth: size), materials: [mat])
        plane.name = "spray.dab"
        return plane
    }

    // MARK: Texture

    private static func texture(softness: Float) -> TextureResource? {
        let bucket = Int((softness * 10).rounded())
        if let cached = textureCache[bucket] { return cached }

        let dim = 128
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim), format: format)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let center = CGPoint(x: dim / 2, y: dim / 2)
            let maxRadius = CGFloat(dim) / 2

            // Opaque core out to `coreStop`, then a fade to transparent at the
            // edge. Crisp dabs stay opaque almost to the rim; blurry dabs fade
            // from near the centre.
            let coreStop = CGFloat(max(0, min(0.95, 1 - softness)))
            let colors = [UIColor.white.cgColor,
                          UIColor.white.cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let locations: [CGFloat] = [0, coreStop, 1]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: locations) {
                cg.drawRadialGradient(gradient,
                                      startCenter: center, startRadius: 0,
                                      endCenter: center, endRadius: maxRadius,
                                      options: [])
            }
        }

        guard let cgImage = image.cgImage,
              let tex = try? TextureResource.generate(from: cgImage,
                                                      options: .init(semantic: .color)) else {
            return nil
        }
        textureCache[bucket] = tex
        return tex
    }
}
