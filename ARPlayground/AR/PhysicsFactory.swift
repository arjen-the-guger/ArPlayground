import RealityKit

/// Adds collision + rigid-body physics to entities. Because the AR session
/// enables `SceneUnderstanding` physics, the scanned real-world mesh becomes a
/// *static collider* — so these dynamic bodies land on real tables, floors and
/// walls, not on invisible planes.
@MainActor
enum PhysicsFactory {

    /// Make an entity a dynamic rigid body that obeys gravity and collides with
    /// the world. Collision shapes are derived from the visual mesh.
    static func makeDynamic(_ entity: Entity,
                            material: PhysicsMaterialResource,
                            mass: Float = 1.0) {
        ensureCollision(entity)
        var body = PhysicsBodyComponent(
            shapes: entity.collision?.shapes ?? [.generateBox(size: [0.1, 0.1, 0.1])],
            mass: mass,
            material: material,
            mode: .dynamic
        )
        body.isContinuousCollisionDetectionEnabled = true
        entity.components.set(body)
        entity.components.set(PhysicsMotionComponent())
    }

    /// Make a static, immovable collider (e.g. a placed object with physics off).
    static func makeStatic(_ entity: Entity, material: PhysicsMaterialResource) {
        ensureCollision(entity)
        let body = PhysicsBodyComponent(
            shapes: entity.collision?.shapes ?? [.generateBox(size: [0.1, 0.1, 0.1])],
            mass: 1.0,
            material: material,
            mode: .static
        )
        entity.components.set(body)
    }

    /// Apply an impulse (used by the "Fling" tool).
    static func push(_ entity: Entity, impulse: SIMD3<Float>) {
        guard var motion = entity.components[PhysicsMotionComponent.self] else {
            entity.components.set(PhysicsMotionComponent(linearVelocity: impulse))
            return
        }
        motion.linearVelocity += impulse
        entity.components.set(motion)
    }

    private static func ensureCollision(_ entity: Entity) {
        guard entity.components[CollisionComponent.self] == nil else { return }
        if let model = entity as? ModelEntity {
            // Accurate shapes derived from the rendered mesh.
            model.generateCollisionShapes(recursive: true)
        } else {
            // Imported hierarchy: approximate with a box from its visual bounds.
            let bounds = entity.visualBounds(relativeTo: entity)
            let extents = max(bounds.extents, SIMD3<Float>(repeating: 0.01))
            let shape = ShapeResource.generateBox(size: extents)
                .offsetBy(translation: bounds.center)
            entity.components.set(CollisionComponent(shapes: [shape]))
        }
    }
}

private extension Entity {
    @MainActor var collision: CollisionComponent? { components[CollisionComponent.self] }
}
