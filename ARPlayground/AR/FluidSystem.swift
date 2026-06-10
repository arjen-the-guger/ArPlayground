import RealityKit
import UIKit
import simd
import QuartzCore

/// Particle-based fluid. Real liquids in RealityKit have no built-in SPH solver,
/// so we model water as a stream of many small **dynamic droplets** that obey
/// gravity and collide with the scanned real world — they pour off real edges,
/// pool on real surfaces and splash realistically. Droplets are pooled and
/// recycled to keep performance steady.
@MainActor
final class FluidSystem {

    struct Source {
        var position: SIMD3<Float>
        var direction: SIMD3<Float>   // initial jet direction (world space)
        var id = UUID()
    }

    private let root: Entity
    private var sources: [Source] = []
    private var droplets: [(entity: ModelEntity, bornAt: TimeInterval)] = []

    private let maxDroplets = 600
    private let dropletLifetime: TimeInterval = 8
    private var emissionAccumulator: Float = 0
    private let dropletsPerSecond: Float = 90
    private let dropletRadius: Float = 0.012

    private let dropletMaterial: RealityKit.Material = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.35, green: 0.62, blue: 0.95, alpha: 1))
        m.roughness = 0.05
        m.metallic = 0.0
        m.clearcoat = 1.0
        m.blending = .transparent(opacity: 0.7)
        return m
    }()

    private let dropletPhysics = PhysicsMaterialResource.generate(friction: 0.05, restitution: 0.2)

    init(root: Entity) {
        self.root = root
    }

    func addSource(at position: SIMD3<Float>, direction: SIMD3<Float>) {
        sources.append(Source(position: position, direction: simd_normalize(direction)))
    }

    func clear() {
        for d in droplets { d.entity.removeFromParent() }
        droplets.removeAll()
        sources.removeAll()
        emissionAccumulator = 0
    }

    var hasSources: Bool { !sources.isEmpty }

    /// Called every frame from the scene update subscription.
    func update(deltaTime: Float, now: TimeInterval) {
        guard !sources.isEmpty else { return }

        emissionAccumulator += dropletsPerSecond * deltaTime * Float(sources.count)
        while emissionAccumulator >= 1 {
            emissionAccumulator -= 1
            emitOne()
        }

        // Recycle expired droplets.
        droplets.removeAll { entry in
            if now - entry.bornAt > dropletLifetime {
                entry.entity.removeFromParent()
                return true
            }
            return false
        }
    }

    private func emitOne() {
        guard let source = sources.randomElement() else { return }

        // Hard cap: reuse the oldest droplet instead of growing unbounded.
        if droplets.count >= maxDroplets {
            let oldest = droplets.removeFirst()
            oldest.entity.removeFromParent()
        }

        let mesh = MeshResource.generateSphere(radius: dropletRadius)
        let drop = ModelEntity(mesh: mesh, materials: [dropletMaterial])
        drop.position = source.position + randomJitter(0.01)

        let shape = ShapeResource.generateSphere(radius: dropletRadius)
        drop.components.set(CollisionComponent(shapes: [shape]))

        var body = PhysicsBodyComponent(
            shapes: [shape],
            mass: 0.02,
            material: dropletPhysics,
            mode: .dynamic
        )
        body.isContinuousCollisionDetectionEnabled = true
        drop.components.set(body)

        // Give the jet some speed + spread so it sprays rather than dribbles.
        let jet = source.direction * 1.6 + randomJitter(0.5)
        drop.components.set(PhysicsMotionComponent(linearVelocity: jet))

        root.addChild(drop)
        droplets.append((drop, CACurrentMediaTime()))
    }

    private func randomJitter(_ magnitude: Float) -> SIMD3<Float> {
        SIMD3(Float.random(in: -magnitude...magnitude),
              Float.random(in: -magnitude...magnitude),
              Float.random(in: -magnitude...magnitude))
    }
}
