import RealityKit
import simd

/// Draws free-form 3D "paint" strokes: a connected run of thin cylinder
/// segments with sphere joints, built up point-by-point as the finger drags.
/// Each stroke is its own entity so it can be cleared as a unit. Strokes carry
/// no collision/physics, so they never interfere with hit-testing or the solver.
///
/// All points are given in world space; the host root is the world-anchored
/// `worldRoot` (identity transform), so a child's local position equals its
/// world position.
@MainActor
final class PaintSystem {

    private let root: Entity
    private var strokes: [Entity] = []
    private var current: Entity?
    private var last: SIMD3<Float>?

    private var material: RealityKit.Material = SimpleMaterial(color: .white, isMetallic: false)
    private var radius: Float = 0.007

    /// Don't drop a new segment until the finger has moved at least this far, so
    /// a stroke is a handful of segments rather than thousands of slivers.
    private let minSegment: Float = 0.012

    init(root: Entity) {
        self.root = root
    }

    /// Start a new stroke with the given look.
    func begin(material: RealityKit.Material, radius: Float) {
        self.material = material
        self.radius = radius
        let stroke = Entity()
        stroke.name = "paint.stroke"
        root.addChild(stroke)
        strokes.append(stroke)
        current = stroke
        last = nil
    }

    /// Extend the current stroke to a new world point.
    func addPoint(_ p: SIMD3<Float>) {
        guard let stroke = current else { return }
        if let last {
            guard simd_distance(last, p) >= minSegment else { return }
            stroke.addChild(makeSegment(from: last, to: p))
        }
        let joint = ModelEntity(mesh: .generateSphere(radius: radius), materials: [material])
        joint.position = p
        stroke.addChild(joint)
        last = p
    }

    func end() {
        current = nil
        last = nil
    }

    func clear() {
        for stroke in strokes { stroke.removeFromParent() }
        strokes.removeAll()
        current = nil
        last = nil
    }

    private func makeSegment(from a: SIMD3<Float>, to b: SIMD3<Float>) -> ModelEntity {
        let length = simd_distance(a, b)
        let seg = ModelEntity(mesh: .generateCylinder(height: length, radius: radius),
                              materials: [material])
        seg.position = (a + b) * 0.5
        let dir = length > 1e-5 ? (b - a) / length : SIMD3<Float>(0, 1, 0)
        seg.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: dir)
        return seg
    }
}
