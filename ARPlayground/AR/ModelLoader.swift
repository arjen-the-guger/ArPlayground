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
        case .imported:
            mesh = .generateBox(size: size) // unused fallback
        }
        let model = ModelEntity(mesh: mesh, materials: [material])
        model.name = "primitive.\(kind.rawValue)"
        return model
    }

    // MARK: Imported files (.usdz, .usd, .usdc, .reality)

    /// Loads a model file off the main thread and normalizes it. The file is
    /// copied into a stable location first because security-scoped picker URLs
    /// are short-lived. Imported assets are frequently hierarchies, so we return
    /// a generic `Entity` rather than assuming a single `ModelEntity`.
    static func loadImported(from url: URL, longestEdge target: Float) async throws -> Entity {
        let localURL = try copyIntoCaches(from: url)
        let loaded = try await Entity(contentsOf: localURL)
        normalize(loaded, longestEdge: target)
        loaded.name = "imported.\(localURL.lastPathComponent)"
        return loaded
    }

    private static func copyIntoCaches(from url: URL) throws -> URL {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dest = caches.appendingPathComponent("imported-\(UUID().uuidString)-\(url.lastPathComponent)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }
}
