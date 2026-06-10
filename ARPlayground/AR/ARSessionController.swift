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

    private weak var arView: ARView?
    private weak var model: SceneModel?

    /// Root for all spawned content; also defines the physics simulation space
    /// (so we can tune gravity here).
    private let worldRoot = AnchorEntity(world: .zero)
    private var sunLight: DirectionalLight?
    private var fluid: FluidSystem!

    private var placedObjects: [Entity] = []
    private var gasEmitters: [Entity] = []

    private var updateSubscription: Cancellable?
    private var lastUpdate: TimeInterval = CACurrentMediaTime()

    // MARK: Setup

    func attach(arView: ARView, model: SceneModel) {
        self.arView = arView
        self.model = model
        model.controller = self

        arView.session.delegate = self
        arView.scene.addAnchor(worldRoot)
        fluid = FluidSystem(root: worldRoot)

        configureWorldSimulation()
        installLighting()
        runConfiguration()
        subscribeToUpdates()
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

    private func configureWorldSimulation() {
        // A simulation space lets us control gravity globally.
        var sim = PhysicsSimulationComponent()
        sim.gravity = [0, -(model?.gravity ?? 9.81), 0]
        worldRoot.components.set(sim)
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
        configureWorldSimulation()
        sunLight?.isEnabled = model?.realisticLighting ?? true
        runConfiguration()
    }

    // MARK: Update loop (fluid emission, HUD)

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
            }
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
        guard let model, let transform = surfaceTransform(at: point) else {
            model?.flash("Aim at a surface")
            return
        }

        if model.selectedModel == .imported {
            model.flash("Use Import to pick a file")
            return
        }
        let material = MaterialFactory.make(model.material)
        let entity = ModelLoader.makePrimitive(model.selectedModel,
                                               size: model.modelScale,
                                               material: material)
        finishPlacement(of: entity, at: transform, model: model)
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
                model.flash("Imported \(url.lastPathComponent)")
            } catch {
                model.flash("Import failed: \(error.localizedDescription)")
            }
        }
    }

    private func finishPlacement(of entity: Entity, at transform: Transform, model: SceneModel) {
        let anchor = AnchorEntity(.world(transform: transform.matrix))
        anchor.addChild(entity)

        // Contact (grounding) shadow under the object (applied to every mesh).
        if model.groundingShadows {
            applyGroundingShadow(to: entity)
        }

        // Physics: dynamic (falls & collides) or static collider.
        let physMat = MaterialFactory.physics(model.material, restitution: model.restitution)
        if model.physicsEnabled {
            PhysicsFactory.makeDynamic(entity, material: physMat, mass: 1.0)
        } else {
            PhysicsFactory.makeStatic(entity, material: physMat)
        }

        worldRoot.addChild(anchor)
        placedObjects.append(anchor)
        model.placedCount = placedObjects.count
    }

    private func emitGasAtSurface(_ point: CGPoint) {
        guard let transform = surfaceTransform(at: point) else {
            model?.flash("Aim at a surface")
            return
        }
        let emitter = ParticleFactory.gasEmitter()
        let anchor = AnchorEntity(.world(transform: transform.matrix))
        anchor.addChild(emitter)
        worldRoot.addChild(anchor)
        gasEmitters.append(anchor)
        model?.flash("Gas plume added")
    }

    private func openFluidSourceAtSurface(_ point: CGPoint) {
        guard let transform = surfaceTransform(at: point) else {
            model?.flash("Aim at a surface")
            return
        }
        // Emit slightly above the surface, spraying mostly upward + outward so
        // it arcs and falls back onto the real world.
        var pos = transform.translation
        pos.y += 0.15
        let camForward = cameraForward()
        let dir = simd_normalize(SIMD3<Float>(camForward.x, 0.6, camForward.z))
        fluid.addSource(at: pos, direction: dir)
        model?.flash("Fluid source opened")
    }

    private func flingObject(at point: CGPoint) {
        guard let arView, let hit = arView.entity(at: point),
              let root = placedRoot(for: hit) else {
            model?.flash("Tap a placed object")
            return
        }
        // Push it away from the camera.
        let forward = cameraForward()
        let impulse = simd_normalize(forward + [0, 0.3, 0]) * 2.2
        if let target = root.children.first {
            // Ensure it's dynamic before pushing.
            if target.components[PhysicsBodyComponent.self]?.mode != .dynamic {
                let physMat = MaterialFactory.physics(self.model?.material ?? .matte,
                                                      restitution: self.model?.restitution ?? 0.4)
                PhysicsFactory.makeDynamic(target, material: physMat)
            }
            PhysicsFactory.push(target, impulse: impulse)
        }
    }

    private func eraseObject(at point: CGPoint) {
        guard let arView, let hit = arView.entity(at: point),
              let root = placedRoot(for: hit) else {
            model?.flash("Tap a placed object")
            return
        }
        root.removeFromParent()
        placedObjects.removeAll { $0 === root }
        model?.placedCount = placedObjects.count
    }

    func clearAll() {
        for o in placedObjects { o.removeFromParent() }
        for g in gasEmitters { g.removeFromParent() }
        placedObjects.removeAll()
        gasEmitters.removeAll()
        fluid.clear()
        model?.placedCount = 0
        model?.flash("Scene cleared")
    }

    /// Grounding shadows attach to entities that have a rendered mesh, so we
    /// walk the whole hierarchy (imported assets may nest many meshes).
    private func applyGroundingShadow(to entity: Entity) {
        if entity.components[ModelComponent.self] != nil {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children { applyGroundingShadow(to: child) }
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

    /// Walk up the entity hierarchy to the placed anchor we track.
    private func placedRoot(for entity: Entity) -> Entity? {
        var current: Entity? = entity
        while let e = current {
            if placedObjects.contains(where: { $0 === e }) { return e }
            current = e.parent
        }
        return nil
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
        if hasMesh {
            Task { @MainActor in self.model?.meshAvailable = true }
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in self.model?.flash("AR error: \(error.localizedDescription)") }
    }
}
