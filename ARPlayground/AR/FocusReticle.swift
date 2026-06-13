import RealityKit
import ARKit
import UIKit

/// A soft "focus pad" that tracks the real surface under the screen centre, so
/// the user always knows the app has locked onto a surface and roughly where
/// content will land. A lightweight take on Apple's FocusSquare.
///
/// It carries no collision/physics, so it never interferes with placement
/// raycasts, object hit-testing or the physics solver.
@MainActor
final class FocusReticle {

    /// Add this to a world-anchored root; its transform is driven each frame.
    let root = Entity()
    private var visible = false

    init() {
        let accent = UIColor(red: 0.62, green: 0.55, blue: 0.95, alpha: 1)

        // Outer glow pad lying flat on the surface.
        var padMat = PhysicallyBasedMaterial()
        padMat.baseColor = .init(tint: .black)
        padMat.emissiveColor = .init(color: accent)
        padMat.emissiveIntensity = 1.2
        padMat.roughness = 1.0
        padMat.metallic = 0.0
        padMat.blending = .transparent(opacity: 0.22)
        let pad = ModelEntity(mesh: .generatePlane(width: 0.13, depth: 0.13, cornerRadius: 0.065),
                              materials: [padMat])

        // Bright centre dot marking the exact point.
        var dotMat = PhysicallyBasedMaterial()
        dotMat.baseColor = .init(tint: .black)
        dotMat.emissiveColor = .init(color: accent)
        dotMat.emissiveIntensity = 2.2
        dotMat.roughness = 1.0
        dotMat.metallic = 0.0
        dotMat.blending = .transparent(opacity: 0.95)
        let dot = ModelEntity(mesh: .generatePlane(width: 0.022, depth: 0.022, cornerRadius: 0.011),
                              materials: [dotMat])
        dot.position.y = 0.001 // float just above the pad to avoid z-fighting

        root.addChild(pad)
        root.addChild(dot)
        root.isEnabled = false
    }

    /// Raycast from screen centre and snap to the surface. Returns whether a
    /// surface was found.
    @discardableResult
    func update(in arView: ARView) -> Bool {
        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        guard let hit = arView.raycast(from: center,
                                       allowing: .estimatedPlane,
                                       alignment: .any).first else {
            hide()
            return false
        }
        root.transform = Transform(matrix: hit.worldTransform)
        if !visible { root.isEnabled = true; visible = true }
        return true
    }

    func hide() {
        if visible { root.isEnabled = false; visible = false }
    }
}
