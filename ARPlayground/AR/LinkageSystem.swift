import RealityKit
import UIKit
import simd

/// Linkages / constraints between two placed objects, attached **face-to-face**
/// at the exact points the user tapped on each object.
///
/// RealityKit's built-in joints API is narrow and version-sensitive, so instead
/// we enforce each link as a **distance constraint** solved every frame: a PD
/// controller pulls the two attachment points back to their rest separation.
/// Per-link `stiffness`/`damping` set the feel — from a rigid strut (no
/// elasticity) to a stretchy spring. A rest length of 0 makes the two faces meet
/// (the objects "join"). A thin glowing rod is drawn between the faces.
@MainActor
final class LinkageSystem {

    @MainActor
    private final class Link {
        let a: ModelEntity
        let b: ModelEntity
        /// Attachment points in each body's local space (the tapped faces).
        let localA: SIMD3<Float>
        let localB: SIMD3<Float>
        let restLength: Float
        let stiffness: Float
        let damping: Float
        let maxForce: Float
        let rod: ModelEntity
        var prevA: SIMD3<Float>
        var prevB: SIMD3<Float>

        init(a: ModelEntity, b: ModelEntity,
             localA: SIMD3<Float>, localB: SIMD3<Float>,
             restLength: Float, stiffness: Float, damping: Float, maxForce: Float,
             rod: ModelEntity) {
            self.a = a
            self.b = b
            self.localA = localA
            self.localB = localB
            self.restLength = max(restLength, 0)
            self.stiffness = stiffness
            self.damping = damping
            self.maxForce = maxForce
            self.rod = rod
            self.prevA = a.convert(position: localA, to: nil)
            self.prevB = b.convert(position: localB, to: nil)
        }
    }

    private let root: Entity
    private var links: [Link] = []

    private let rodRadius: Float = 0.006

    init(root: Entity) {
        self.root = root
    }

    var count: Int { links.count }

    /// Create a face-to-face link. `localA`/`localB` are the tapped points in
    /// each body's local space; `restLength` is the target separation between
    /// them (0 = join the faces). Returns false if it's the same object or the
    /// pair is already linked.
    @discardableResult
    func link(_ a: ModelEntity, _ b: ModelEntity,
              localA: SIMD3<Float>, localB: SIMD3<Float>,
              restLength: Float, stiffness: Float, damping: Float, maxForce: Float) -> Bool {
        guard a !== b else { return false }
        if links.contains(where: { ($0.a === a && $0.b === b) || ($0.a === b && $0.b === a) }) {
            return false
        }
        let rod = makeRod()
        root.addChild(rod)
        links.append(Link(a: a, b: b, localA: localA, localB: localB,
                          restLength: restLength, stiffness: stiffness,
                          damping: damping, maxForce: maxForce, rod: rod))
        return true
    }

    /// Remove every link touching `body`. Returns how many were removed.
    @discardableResult
    func unlink(_ body: ModelEntity) -> Int {
        let before = links.count
        links.removeAll { link in
            if link.a === body || link.b === body {
                link.rod.removeFromParent()
                return true
            }
            return false
        }
        return before - links.count
    }

    /// Drop any links that referenced a now-removed object (called after erase).
    func pruneLinks(removed body: ModelEntity) {
        unlink(body)
    }

    func clear() {
        for link in links { link.rod.removeFromParent() }
        links.removeAll()
    }

    /// Solve every constraint and update the connector rods. `dt` is clamped by
    /// the caller.
    func update(deltaTime dt: Float) {
        guard !links.isEmpty, dt > 0 else { return }

        for link in links {
            // Live world positions of the two attachment points.
            let pa = link.a.convert(position: link.localA, to: nil)
            let pb = link.b.convert(position: link.localB, to: nil)

            let delta = pb - pa
            let dist = simd_length(delta)
            let dir = dist > 1e-4 ? delta / dist : SIMD3<Float>(0, 1, 0)

            // Estimate point velocities from motion since last frame (don't rely
            // on PhysicsMotionComponent being populated).
            let velA = (pa - link.prevA) / dt
            let velB = (pb - link.prevB) / dt
            link.prevA = pa
            link.prevB = pb

            let stretch = dist - link.restLength
            let relativeVel = simd_dot(velB - velA, dir)
            var magnitude = link.stiffness * stretch + link.damping * relativeVel
            magnitude = max(-link.maxForce, min(link.maxForce, magnitude))
            let force = dir * magnitude

            // Pull A toward B and B toward A. Only dynamic bodies respond;
            // static / kinematic ones act as anchors.
            applyForce(force, to: link.a)
            applyForce(-force, to: link.b)

            updateRod(link.rod, from: pa, to: pb, length: dist)
        }
    }

    // MARK: Helpers

    private func applyForce(_ force: SIMD3<Float>, to body: ModelEntity) {
        guard body.components[PhysicsBodyComponent.self]?.mode == .dynamic else { return }
        body.addForce(force, relativeTo: nil)
    }

    private func makeRod() -> ModelEntity {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .black)
        mat.emissiveColor = .init(color: UIColor(red: 0.62, green: 0.55, blue: 0.95, alpha: 1))
        mat.emissiveIntensity = 1.6
        mat.roughness = 1.0
        mat.metallic = 0.0
        // Unit-height cylinder along +Y; we scale Y to the live distance.
        let rod = ModelEntity(mesh: .generateCylinder(height: 1, radius: rodRadius), materials: [mat])
        rod.name = "linkage.rod"
        return rod
    }

    private func updateRod(_ rod: ModelEntity, from a: SIMD3<Float>, to b: SIMD3<Float>, length: Float) {
        rod.position = (a + b) * 0.5
        rod.scale = SIMD3<Float>(1, max(length, 0.001), 1)
        // Hide the rod when the faces are essentially joined.
        rod.isEnabled = length > 0.02
        let dir = length > 1e-4 ? (b - a) / length : SIMD3<Float>(0, 1, 0)
        rod.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: dir)
    }
}
