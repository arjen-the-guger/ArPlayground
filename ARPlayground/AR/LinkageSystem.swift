import RealityKit
import UIKit
import simd

/// Linkages / constraints between two placed objects.
///
/// RealityKit's built-in joints API is narrow and version-sensitive, so instead
/// we enforce each link as a stiff, critically-damped **distance constraint**
/// solved every frame: a PD controller pulls the two bodies back to their rest
/// separation. Linking to a static body turns the other into a pendulum; linking
/// two dynamic bodies makes a rigid-ish strut. A thin glowing rod is drawn
/// between them and follows along.
@MainActor
final class LinkageSystem {

    @MainActor
    private final class Link {
        let a: ModelEntity
        let b: ModelEntity
        let restLength: Float
        let rod: ModelEntity
        var prevA: SIMD3<Float>
        var prevB: SIMD3<Float>

        init(a: ModelEntity, b: ModelEntity, restLength: Float, rod: ModelEntity) {
            self.a = a
            self.b = b
            self.restLength = max(restLength, 0.03)
            self.rod = rod
            self.prevA = a.position(relativeTo: nil)
            self.prevB = b.position(relativeTo: nil)
        }
    }

    private let root: Entity
    private var links: [Link] = []

    // PD gains tuned for stability at ~60 Hz with our ~1 kg bodies.
    private let stiffness: Float = 140
    private let damping: Float = 14
    private let maxForce: Float = 120

    private let rodRadius: Float = 0.006

    init(root: Entity) {
        self.root = root
    }

    var count: Int { links.count }

    /// Create a link between two distinct objects. Returns false if they're the
    /// same object or already linked.
    @discardableResult
    func link(_ a: ModelEntity, _ b: ModelEntity) -> Bool {
        guard a !== b else { return false }
        if links.contains(where: { ($0.a === a && $0.b === b) || ($0.a === b && $0.b === a) }) {
            return false
        }
        let pa = a.position(relativeTo: nil)
        let pb = b.position(relativeTo: nil)
        let rod = makeRod()
        root.addChild(rod)
        links.append(Link(a: a, b: b, restLength: simd_distance(pa, pb), rod: rod))
        return true
    }

    /// Drop any links that referenced a now-removed object (called after erase).
    func pruneLinks(removed body: ModelEntity) {
        links.removeAll { link in
            if link.a === body || link.b === body {
                link.rod.removeFromParent()
                return true
            }
            return false
        }
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
            let pa = link.a.position(relativeTo: nil)
            let pb = link.b.position(relativeTo: nil)

            let delta = pb - pa
            let dist = simd_length(delta)
            let dir = dist > 1e-4 ? delta / dist : SIMD3<Float>(0, 1, 0)

            // Estimate velocities from motion since last frame (don't rely on
            // PhysicsMotionComponent being populated).
            let velA = (pa - link.prevA) / dt
            let velB = (pb - link.prevB) / dt
            link.prevA = pa
            link.prevB = pb

            let stretch = dist - link.restLength
            let relativeVel = simd_dot(velB - velA, dir)
            var magnitude = stiffness * stretch + damping * relativeVel
            magnitude = max(-maxForce, min(maxForce, magnitude))
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
        let dir = length > 1e-4 ? (b - a) / length : SIMD3<Float>(0, 1, 0)
        rod.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: dir)
    }
}
