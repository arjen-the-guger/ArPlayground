import Foundation
import RealityKit
import UIKit

/// Loads built-in primitives and arbitrary imported model files, and—critically—
/// **normalizes their scale** so that an asset authored in centimetres, metres or
/// inches all arrive at a sane, predictable size in the room.
///
/// `@MainActor` because in the iOS 26 SDK `Entity` and its members (`name`,
/// transforms, etc.) are main-actor isolated.
@MainActor
enum ModelLoader {

    /// Target longest-edge size in metres for a freshly placed object.
    /// (e.g. 0.25 → the object's biggest dimension becomes 25 cm.)
    static func normalize(_ entity: Entity, longestEdge target: Float) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let extents = bounds.extents
        let longest = max(extents.x, max(extents.y, extents.z))
        guard longest > 0, longest.isFinite else { return }
        let factor = target / longest
        entity.scale *= SIMD3<Float>(repeating: factor)

        // Re-center on origin so the object pivots/places about its middle.
        let recentered = entity.visualBounds(relativeTo: nil).center
        entity.position -= recentered
    }

    // MARK: Built-in primitives

    /// Build any built-in model. Primitives are a single mesh; mechanical and
    /// throwable kinds are small assemblies (see the dedicated factories).
    static func makeModel(_ kind: ModelKind, size: Float, material: RealityKit.Material) -> ModelEntity {
        switch kind {
        case .sphere, .cube, .cylinder, .cone:
            return makePrimitive(kind, size: size, material: material)
        case .piston:
            return makePiston(size: size, material: material)
        case .bearing:
            return makeBearing(size: size, material: material)
        case .grenade:
            return makeGrenade(size: size)
        case .basketball:
            return makeBasketball(size: size)
        }
    }

    static func makePrimitive(_ kind: ModelKind, size: Float, material: RealityKit.Material) -> ModelEntity {
        let mesh: MeshResource
        switch kind {
        case .cube:
            mesh = .generateBox(size: size, cornerRadius: size * 0.04)
        case .sphere:
            mesh = .generateSphere(radius: size * 0.5)
        case .cylinder:
            mesh = .generateCylinder(height: size, radius: size * 0.35)
        case .cone:
            mesh = .generateCone(height: size, radius: size * 0.45)
        default:
            mesh = .generateBox(size: size) // not reached for non-primitive kinds
        }
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.name = "primitive.\(kind.rawValue)"
        return model
    }

    // MARK: Mechanical

    /// A piston: a housing cylinder + a sliding shaft, both children of one rigid
    /// body. Flinging it toggles the shaft between collapsed/expanded (animated
    /// by the controller via `PistonComponent`).
    static func makePiston(size: Float, material: RealityKit.Material) -> ModelEntity {
        let root = ModelEntity()
        root.name = "piston"

        let housingH = size * 0.6
        let housingR = size * 0.28
        let housing = ModelEntity(mesh: .generateCylinder(height: housingH, radius: housingR),
                                  materials: [material])
        housing.name = "piston.housing"
        housing.position.y = -size * 0.1

        let shaftH = size * 0.5
        let shaftR = size * 0.14
        let shaft = ModelEntity(mesh: .generateCylinder(height: shaftH, radius: shaftR),
                                materials: [MaterialFactory.make(.metal)])
        shaft.name = "piston.shaft"
        let collapsedY = housing.position.y + housingH * 0.5 - shaftH * 0.25
        let expandedY = collapsedY + size * 0.5
        shaft.position.y = collapsedY

        root.addChild(housing)
        root.addChild(shaft)
        root.components.set(PistonComponent(extended: false,
                                            collapsedY: collapsedY,
                                            expandedY: expandedY))
        return root
    }

    /// A bearing: two coaxial discs on a thin axle. The discs spin independently
    /// (driven by the controller via `BearingComponent`); the axle is fixed.
    static func makeBearing(size: Float, material: RealityKit.Material) -> ModelEntity {
        let root = ModelEntity()
        root.name = "bearing"

        let axle = ModelEntity(mesh: .generateCylinder(height: size * 0.55, radius: size * 0.06),
                               materials: [MaterialFactory.make(.metal)])
        axle.name = "bearing.axle"

        let discR = size * 0.5
        let discH = size * 0.14
        let top = ModelEntity(mesh: .generateCylinder(height: discH, radius: discR),
                              materials: [material])
        top.name = "bearing.top"
        top.position.y = size * 0.16
        addRimMarks(to: top, radius: discR, height: discH,
                    count: 6, color: UIColor(red: 0.62, green: 0.55, blue: 0.95, alpha: 1))

        let bottom = ModelEntity(mesh: .generateCylinder(height: discH, radius: discR),
                                 materials: [MaterialFactory.make(.metal)])
        bottom.name = "bearing.bottom"
        bottom.position.y = -size * 0.16
        addRimMarks(to: bottom, radius: discR, height: discH,
                    count: 4, color: UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1))

        root.addChild(axle)
        root.addChild(top)
        root.addChild(bottom)
        root.components.set(BearingComponent(topSpeed: 0.6, bottomSpeed: -1.0))
        return root
    }

    /// Small emissive nubs around a disc's rim so its rotation is clearly visible.
    private static func addRimMarks(to disc: ModelEntity, radius: Float, height: Float,
                                    count: Int, color: UIColor) {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .black)
        mat.emissiveColor = .init(color: color)
        mat.emissiveIntensity = 1.2
        mat.roughness = 1.0
        mat.metallic = 0.0
        let markMesh = MeshResource.generateBox(size: [radius * 0.16, height * 1.1, radius * 0.16])
        for i in 0..<count {
            let angle = Float(i) / Float(count) * 2 * .pi
            let mark = ModelEntity(mesh: markMesh, materials: [mat])
            mark.position = [cosf(angle) * radius * 0.9, 0, sinf(angle) * radius * 0.9]
            disc.addChild(mark)
        }
    }

    // MARK: Throwable

    /// A grenade: a dark metallic body with a cap + lever. Flinging it throws +
    /// arms it (see `GrenadeComponent`); the controller detonates it on a fuse.
    static func makeGrenade(size: Float) -> ModelEntity {
        let root = ModelEntity()
        root.name = "grenade"

        var bodyMat = PhysicallyBasedMaterial()
        bodyMat.baseColor = .init(tint: UIColor(red: 0.18, green: 0.28, blue: 0.16, alpha: 1))
        bodyMat.roughness = 0.5
        bodyMat.metallic = 0.6
        let ball = ModelEntity(mesh: .generateSphere(radius: size * 0.45), materials: [bodyMat])
        ball.name = "grenade.body"

        let metal = MaterialFactory.make(.metal)
        let cap = ModelEntity(mesh: .generateCylinder(height: size * 0.16, radius: size * 0.16),
                              materials: [metal])
        cap.position.y = size * 0.46
        let lever = ModelEntity(mesh: .generateBox(size: [size * 0.06, size * 0.02, size * 0.3]),
                                materials: [metal])
        lever.position = [0, size * 0.5, size * 0.1]

        root.addChild(ball)
        root.addChild(cap)
        root.addChild(lever)
        root.components.set(GrenadeComponent())
        return root
    }

    /// A bouncy basketball — its own orange material and high restitution are set
    /// by the controller at placement.
    static func makeBasketball(size: Float) -> ModelEntity {
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: UIColor(red: 0.85, green: 0.38, blue: 0.12, alpha: 1))
        mat.roughness = 0.7
        mat.metallic = 0.0
        let ball = ModelEntity(mesh: .generateSphere(radius: size * 0.5), materials: [mat])
        ball.name = "basketball"
        return ball
    }

    // MARK: Uploaded files (.usdz, .usd, .usdc, .reality)

    /// Loads a model file from the app's own (stable) Uploads directory and
    /// normalizes it. Imported assets are frequently hierarchies, so we return a
    /// generic `Entity` rather than assuming a single `ModelEntity`.
    static func loadFile(_ url: URL, longestEdge target: Float) async throws -> Entity {
        let loaded = try await Entity(contentsOf: url)
        normalize(loaded, longestEdge: target)
        loaded.name = "upload.\(url.lastPathComponent)"
        return loaded
    }
}
