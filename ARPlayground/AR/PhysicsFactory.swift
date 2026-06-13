import RealityKit

/// Adds collision + rigid-body physics to entities. Bodies join the scene's
/// *default* physics simulation — the same one that contains the LiDAR mesh
/// colliders and our detected-plane colliders — so they land on real tables,
/// floors and walls. (Never give content its own `PhysicsSimulationComponent`:
/// that isolates it from the real-world colliders.)
@MainActor
enum PhysicsFactory {

    /// Make a dynamic rigid body that obeys gravity and collides with the world.
    static func makeDynamic(_ body: ModelEntity,
                            material: PhysicsMaterialResource,
                            mass: Float = 1.0) {
        let shapes = collisionShapes(for: body)
        var component = PhysicsBodyComponent(shapes: shapes,
                                             mass: mass,
                                             material: material,
                                             mode: .dynamic)
        component.isContinuousCollisionDetectionEnabled = true
        body.components.set(component)
    }

    /// Make a static, immovable collider (a placed object with physics off).
    static func makeStatic(_ body: ModelEntity, material: PhysicsMaterialResource) {
        let shapes = collisionShapes(for: body)
        body.components.set(PhysicsBodyComponent(shapes: shapes,
                                                 mass: 1.0,
                                                 material: material,
                                                 mode: .static))
    }

    /// Shove a dynamic body (used by the "Fling" tool).
    static func push(_ body: ModelEntity, impulse: SIMD3<Float>) {
        body.applyLinearImpulse(impulse, relativeTo: nil)
    }

    /// Returns the body's collision shapes, creating them if needed. Entities
    /// with their own mesh get accurate generated shapes; mesh-less containers
    /// (imported hierarchies) get a box fitted to their visual bounds.
    private static func collisionShapes(for body: ModelEntity) -> [ShapeResource] {
        if let existing = body.components[CollisionComponent.self], !existing.shapes.isEmpty {
            return existing.shapes
        }
        if body.model != nil {
            body.generateCollisionShapes(recursive: false)
            if let generated = body.components[CollisionComponent.self], !generated.shapes.isEmpty {
                return generated.shapes
            }
        }
        let bounds = body.visualBounds(relativeTo: body)
        let extents = max(bounds.extents, SIMD3<Float>(repeating: 0.02))
        let shape = ShapeResource.generateBox(size: extents).offsetBy(translation: bounds.center)
        body.components.set(CollisionComponent(shapes: [shape]))
        return [shape]
    }
}
