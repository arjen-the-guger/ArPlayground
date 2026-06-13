import ARKit
import RealityKit
import Combine
import UIKit
import simd
import QuartzCore

/// Owns the live `ARView` and bridges it to `SceneModel`. Configures world
/// tracking, real-world mesh physics & occlusion, image-based lighting,
/// grounding shadows and environment reflections, then routes taps to the
/// active tool.
@MainActor
final class ARSessionController: NSObject, ARSessionDelegate {

    private struct PlacedObject {
        let anchor: AnchorEntity
        let body: ModelEntity
    }

    private weak var arView: ARView?
    private weak var model: SceneModel?

    /// Root for all spawned content. Content stays in the scene's default
    /// physics simulation so it collides with the LiDAR mesh and plane colliders.
    private let worldRoot = AnchorEntity(world: .zero)

    /// Invisible static colliders mirroring ARKit's detected planes — the
    /// ground-collision fallback for devices without LiDAR, and a safety net
    /// before the LiDAR mesh has streamed in.
    private let planeRoot = AnchorEntity(world: .zero)
    private var planeColliders: [UUID: ModelEntity] = [:]

    private var sunLight: DirectionalLight?
    private var fluid: FluidSystem!

    /// Surface-tracking aiming reticle (a FocusSquare-style pad).
    private let reticle = FocusReticle()

    private var placed: [PlacedObject] = []
    private var gasEmitters: [Entity] = []

    private var updateSubscription: Cancellable?
    private var lastUpdate: TimeInterval = CACurrentMediaTime()

    /// Gravity the default simulation applies; the slider works by adding a
    /// per-frame compensation force on top of this.
    private let defaultGravity: Float = 9.81

    // MARK: Setup

    func attach(arView: ARView, model: SceneModel) {
        self.arView = arView
        self.model = model
        model.controller = self

        arView.session.delegate = self
        arView.scene.addAnchor(worldRoot)
        arView.scene.addAnchor(planeRoot)
        worldRoot.addChild(reticle.root)
        fluid = FluidSystem(root: worldRoot)

        installLighting()
        runConfiguration()
        installCoaching()
        subscribeToUpdates()
    }

    /// Apple's coaching overlay: guides the user to pan and scan until ARKit has
    /// enough to detect surfaces, and reappears if tracking is lost.
    private func installCoaching() {
        guard let arView else { return }
        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coaching.frame = arView.bounds
        arView.addSubview(coaching)
    }

    // MARK: ARKit configuration

    private func makeConfiguration() -> ARWorldTrackingConfiguration {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.isCollaborationEnabled = false

        let model = self.model

        // Image-based lighting + real environment reflections.
        if model?.realisticLighting != false || model?.reflections != false {
            config.environmentTexturing = .automatic
        } else {
            config.environmentTexturing = .none
        }

        // LiDAR: reconstruct the room as a mesh for true physics & occlusion.
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        // People occlusion: real people pass in front of virtual objects.
        if model?.peopleOcclusion != false,
           ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        }

        return config
    }

    func runConfiguration() {
        guard let arView else { return }
        let config = makeConfiguration()
        arView.session.run(config, options: [])

        // Tell RealityKit to use the scanned mesh for occlusion, physics
        // collision and to let real surfaces receive virtual light/shadow.
        var options: ARView.Environment.SceneUnderstanding.Options = []
        if model?.peopleOcclusion != false { options.insert(.occlusion) }
        options.insert(.physics)
        options.insert(.collision)
        if model?.realisticLighting != false { options.insert(.receivesLighting) }
        arView.environment.sceneUnderstanding.options = options

        arView.environment.lighting.intensityExponent = 1.0
        arView.renderOptions.remove(.disableGroundingShadows)
        arView.renderOptions.remove(.disableMotionBlur)
    }

    private func installLighting() {
        // A soft key light gives crisp, directional grounding shadows on top of
        // the ambient image-based lighting from the room.
        let light = DirectionalLight()
        light.light.intensity = 2500
        light.shadow = DirectionalLightComponent.Shadow(
            maximumDistance: 4.0,
            depthBias: 2.0
        )
        light.orientation = simd_quatf(angle: -.pi / 3, axis: simd_normalize([1, 0.4, 0]))
        let lightAnchor = AnchorEntity(world: [0, 2, 0])
        lightAnchor.addChild(light)
        arView?.scene.addAnchor(lightAnchor)
        sunLight = light
    }

    // MARK: Live settings

    func applyWorldSettings() {
        sunLight?.isEnabled = model?.realisticLighting ?? true
        runConfiguration()
        // Gravity is read live every frame in the update loop.
    }

    // MARK: Update loop (fluid emission, gravity tuning)

    private func subscribeToUpdates() {
        guard let arView else { return }
        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            // Scene update events are delivered on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = CACurrentMediaTime()
                let dt = Float(min(now - self.lastUpdate, 1.0 / 20.0))
                self.lastUpdate = now
                self.fluid.update(deltaTime: dt, now: now)
                self.applyGravityCompensation()
                self.updateReticle()
            }
        }
    }

    /// Drive the aiming reticle from the screen-centre ray, and surface the
    /// "surface ready" state to the UI (only on transitions, to avoid churning
    /// SwiftUI every frame). The reticle only shows for surface-placing tools.
    private func updateReticle() {
        guard let arView, let model else { return }
        let onSurface: Bool
        if model.tool.usesSurface {
            onSurface = reticle.update(in: arView)
        } else {
            reticle.hide()
            onSurface = false
        }
        if model.surfaceDetected != onSurface { model.surfaceDetected = onSurface }
    }

    /// The gravity slider: the default simulation always pulls at 9.81 m/s², so
    /// we add a continuous force making the *net* acceleration match the model.
    private func applyGravityCompensation() {
        guard let model else { return }
        let delta = defaultGravity - model.gravity
        guard abs(delta) > 0.01 else { return }
        for object in placed {
            guard let body = object.body.components[PhysicsBodyComponent.self],
                  body.mode == .dynamic else { continue }
            object.body.addForce([0, delta * body.massProperties.mass, 0], relativeTo: nil)
        }
    }

    // MARK: Tap routing

    func handleTap(at point: CGPoint) {
        guard let model else { return }
        switch model.tool {
        case .place: placeAtSurface(point)
        case .gas:   emitGasAtSurface(point)
        case .fluid: openFluidSourceAtSurface(point)
        case .fling: flingObject(at: point)
        case .erase: eraseObject(at: point)
        }
    }

    // MARK: Tool actions

    private func placeAtSurface(_ point: CGPoint) {
        guard let model, var transform = surfaceTransform(at: point) else {
            model?.flash("Aim at a surface")
            Haptics.warning()
            return
        }

        if model.selectedModel == .imported {
            model.flash("Use Import to pick a file")
            Haptics.warning()
            return
        }
        let material = MaterialFactory.make(model.material)
        let entity = ModelLoader.makePrimitive(model.selectedModel,
                                               size: model.modelScale,
                                               material: material)
        // Spawn just above the surface so the body doesn't start embedded in
        // the collider (which makes the solver eject or tunnel it).
        transform.translation.y += model.modelScale * 0.5 + 0.02
        finishPlacement(of: entity, at: transform, model: model)
        Haptics.success()
    }

    func importModel(from url: URL) {
        guard let model else { return }
        Task {
            do {
                let entity = try await ModelLoader.loadImported(from: url,
                                                                longestEdge: model.modelScale)
                // Place in front of the camera at a comfortable distance.
                let transform = transformInFrontOfCamera(distance: 0.6)
                finishPlacement(of: entity, at: transform, model: model)
                Haptics.success()
                model.flash("Imported \(url.lastPathComponent)")
            } catch {
                Haptics.warning()
                model.flash("Import failed: \(error.localizedDescription)")
            }
        }
    }

    private func finishPlacement(of entity: Entity, at transform: Transform, model: SceneModel) {
        // Imported assets are arbitrary hierarchies; wrap them in a ModelEntity
        // container so the whole object is one physics body we can fling.
        let body: ModelEntity
        if let modelEntity = entity as? ModelEntity {
            body = modelEntity
        } else {
            let container = ModelEntity()
            container.name = "imported.container"
            container.addChild(entity)
            body = container
        }

        let anchor = AnchorEntity(.world(transform: transform.matrix))
        anchor.addChild(body)

        // Contact (grounding) shadow under the object (applied to every mesh).
        if model.groundingShadows {
            applyGroundingShadow(to: body)
        }

        // Physics: dynamic (falls & collides) or static collider.
        let physMat = MaterialFactory.physics(model.material, restitution: model.restitution)
        if model.physicsEnabled {
            PhysicsFactory.makeDynamic(body, material: physMat, mass: 1.0)
        } else {
            PhysicsFactory.makeStatic(body, material: physMat)
        }

        worldRoot.addChild(anchor)
        placed.append(PlacedObject(anchor: anchor, body: body))
        model.placedCount = placed.count
    }

    private func emitGasAtSurface(_ point: CGPoint) {
        guard let transform = surfaceTransform(at: point) else {
            model?.flash("Aim at a surface")
            Haptics.warning()
            return
        }
        let emitter = ParticleFactory.gasEmitter()
        let anchor = AnchorEntity(.world(transform: transform.matrix))
        anchor.addChild(emitter)
        worldRoot.addChild(anchor)
        gasEmitters.append(anchor)
        Haptics.impact(.soft)
        model?.flash("Gas plume added")
    }

    private func openFluidSourceAtSurface(_ point: CGPoint) {
        guard let transform = surfaceTransform(at: point) else {
            model?.flash("Aim at a surface")
            Haptics.warning()
            return
        }
        // Emit slightly above the surface, spraying mostly upward + outward so
        // it arcs and falls back onto the real world.
        var pos = transform.translation
        pos.y += 0.15
        let camForward = cameraForward()
        let dir = simd_normalize(SIMD3<Float>(camForward.x, 0.6, camForward.z))
        fluid.addSource(at: pos, direction: dir)
        Haptics.impact(.soft)
        model?.flash("Fluid source opened")
    }

    private func flingObject(at point: CGPoint) {
        guard let target = placedHit(at: point) else {
            model?.flash("Tap a placed object")
            Haptics.warning()
            return
        }
        // Ensure it's dynamic, then push it away from the camera.
        if target.body.components[PhysicsBodyComponent.self]?.mode != .dynamic {
            let physMat = MaterialFactory.physics(model?.material ?? .matte,
                                                  restitution: model?.restitution ?? 0.4)
            PhysicsFactory.makeDynamic(target.body, material: physMat)
        }
        let impulse = simd_normalize(cameraForward() + SIMD3<Float>(0, 0.35, 0)) * 2.2
        PhysicsFactory.push(target.body, impulse: impulse)
        Haptics.impact(.medium)
    }

    private func eraseObject(at point: CGPoint) {
        guard let target = placedHit(at: point) else {
            model?.flash("Tap a placed object")
            Haptics.warning()
            return
        }
        target.anchor.removeFromParent()
        placed.removeAll { $0.anchor === target.anchor }
        model?.placedCount = placed.count
        Haptics.impact(.rigid)
    }

    func clearAll() {
        for o in placed { o.anchor.removeFromParent() }
        for g in gasEmitters { g.removeFromParent() }
        placed.removeAll()
        gasEmitters.removeAll()
        fluid.clear()
        model?.placedCount = 0
        model?.flash("Scene cleared")
    }

    // MARK: Hit testing

    /// Collision-ray hit test that skips room geometry (LiDAR mesh, plane
    /// colliders, droplets) and returns the first *placed* object along the ray.
    /// `entity(at:)` alone returns the nearest collidable, which is usually the
    /// room itself — that made taps on objects feel broken.
    private func placedHit(at point: CGPoint) -> PlacedObject? {
        guard let arView else { return nil }
        for hit in arView.hitTest(point, query: .all, mask: .all) {
            var current: Entity? = hit.entity
            while let entity = current {
                if let match = placed.first(where: { $0.body === entity || $0.anchor === entity }) {
                    return match
                }
                current = entity.parent
            }
        }
        return nil
    }

    // MARK: Plane colliders (non-LiDAR ground physics)

    private func upsertPlaneCollider(for plane: ARPlaneAnchor) {
        let collider: ModelEntity
        if let existing = planeColliders[plane.identifier] {
            collider = existing
        } else {
            collider = ModelEntity()
            collider.name = "plane.collider"
            planeRoot.addChild(collider)
            planeColliders[plane.identifier] = collider
        }
        collider.transform = Transform(matrix: plane.transform)

        // A thick slab whose top face sits at the plane surface (thickness
        // resists fast bodies tunneling through).
        let extent = plane.planeExtent
        let thickness: Float = 0.05
        let shape = ShapeResource.generateBox(width: extent.width,
                                              height: thickness,
                                              depth: extent.height)
            .offsetBy(rotation: simd_quatf(angle: extent.rotationOnYAxis, axis: [0, 1, 0]),
                      translation: plane.center + SIMD3<Float>(0, -thickness / 2, 0))
        collider.components.set(CollisionComponent(shapes: [shape]))
        collider.components.set(PhysicsBodyComponent(shapes: [shape],
                                                     mass: 1.0,
                                                     material: Self.planeMaterial,
                                                     mode: .static))
    }

    /// Friction/restitution for the detected-plane ground colliders. A bit of
    /// grip so objects settle instead of sliding, and a low bounce.
    private static let planeMaterial = PhysicsMaterialResource.generate(friction: 0.6, restitution: 0.1)

    private func removePlaneCollider(for plane: ARPlaneAnchor) {
        planeColliders.removeValue(forKey: plane.identifier)?.removeFromParent()
    }

    // MARK: Geometry helpers

    /// Raycast to a real surface (works with or without LiDAR via plane estimation).
    private func surfaceTransform(at point: CGPoint) -> Transform? {
        guard let arView else { return nil }
        let results = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any)
        guard let first = results.first else { return nil }
        return Transform(matrix: first.worldTransform)
    }

    private func transformInFrontOfCamera(distance: Float) -> Transform {
        guard let arView else { return Transform() }
        let cam = arView.cameraTransform
        let forward = -SIMD3<Float>(cam.matrix.columns.2.x,
                                    cam.matrix.columns.2.y,
                                    cam.matrix.columns.2.z)
        var t = Transform()
        t.translation = cam.translation + simd_normalize(forward) * distance
        return t
    }

    private func cameraForward() -> SIMD3<Float> {
        guard let arView else { return [0, 0, -1] }
        let m = arView.cameraTransform.matrix
        return simd_normalize(-SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z))
    }

    /// Grounding shadows attach to entities that have a rendered mesh, so we
    /// walk the whole hierarchy (imported assets may nest many meshes).
    private func applyGroundingShadow(to entity: Entity) {
        if entity.components[ModelComponent.self] != nil {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children { applyGroundingShadow(to: child) }
    }

    // MARK: ARSessionDelegate

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let text: String
        switch camera.trackingState {
        case .normal: text = "Tracking"
        case .notAvailable: text = "Not available"
        case .limited(let reason):
            switch reason {
            case .initializing: text = "Initializing…"
            case .excessiveMotion: text = "Slow down"
            case .insufficientFeatures: text = "Need more light/detail"
            case .relocalizing: text = "Relocalizing…"
            @unknown default: text = "Limited"
            }
        }
        Task { @MainActor in self.model?.trackingState = text }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        let hasMesh = anchors.contains { $0 is ARMeshAnchor }
        let planes = anchors.compactMap { $0 as? ARPlaneAnchor }
        guard hasMesh || !planes.isEmpty else { return }
        Task { @MainActor in
            if hasMesh { self.model?.meshAvailable = true }
            for plane in planes { self.upsertPlaneCollider(for: plane) }
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        let planes = anchors.compactMap { $0 as? ARPlaneAnchor }
        guard !planes.isEmpty else { return }
        Task { @MainActor in
            for plane in planes { self.upsertPlaneCollider(for: plane) }
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        let planes = anchors.compactMap { $0 as? ARPlaneAnchor }
        guard !planes.isEmpty else { return }
        Task { @MainActor in
            for plane in planes { self.removePlaneCollider(for: plane) }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in self.model?.flash("AR error: \(error.localizedDescription)") }
    }
}
