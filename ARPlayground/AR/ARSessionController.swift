import ARKit
import RealityKit
import Combine
import SwiftUI
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

    /// Photo / video capture (ReplayKit screen recording + Photos save).
    private let recorder = ScreenRecorder()

    /// Free-form 3D paint strokes.
    private var paint: PaintSystem!

    /// Spray-paint dabs stuck to real surfaces (cleared with the scene).
    private var sprayDabs: [Entity] = []
    private var lastSprayPoint: SIMD3<Float>?
    private let spraySpacing: Float = 0.015

    /// Loaded templates for uploaded files, cloned per placement.
    private var uploadTemplates: [UUID: Entity] = [:]

    private var placed: [PlacedObject] = []
    private var gasEmitters: [Entity] = []

    /// Linkages / distance constraints between placed objects.
    private var linkage: LinkageSystem!

    /// Drag tool state (a kinematic follow that keeps colliding with the world).
    weak var dragPanRecognizer: UIPanGestureRecognizer?
    private var draggedBody: ModelEntity?
    private var dragDistance: Float = 0.5
    private var dragRestoreMode: PhysicsBodyMode = .dynamic
    private var dragLastPoint: SIMD3<Float> = .zero
    private var dragVelocity: SIMD3<Float> = .zero
    private var dragLastTime: TimeInterval = 0

    /// Transform tool state (free translate / rotate / scale via RealityKit's
    /// built-in entity gestures, with physics frozen).
    private var transformGestures: [EntityGestureRecognizer] = []
    private var transformTarget: ModelEntity?

    /// Link tool state: the first object tapped, awaiting a second. We remember
    /// the tapped face both in the body's local space (for the live constraint)
    /// and in world space (to compute the auto rest length).
    private var pendingLinkSource: ModelEntity?
    private var pendingLinkLocal: SIMD3<Float> = .zero
    private var pendingLinkWorld: SIMD3<Float> = .zero

    /// Tracks tool changes so we can enable/disable gesture modes on transition.
    private var lastTool: PlaygroundTool = .place

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

        // Register custom components before any mechanical model is spawned.
        PistonComponent.registerComponent()
        BearingComponent.registerComponent()
        GrenadeComponent.registerComponent()

        arView.session.delegate = self
        arView.scene.addAnchor(worldRoot)
        arView.scene.addAnchor(planeRoot)
        worldRoot.addChild(reticle.root)
        fluid = FluidSystem(root: worldRoot)
        linkage = LinkageSystem(root: worldRoot)
        paint = PaintSystem(root: worldRoot)

        // Surface previously uploaded models in the palette.
        model.uploads = UploadStore.list()

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
                self.syncToolMode()
                self.fluid.update(deltaTime: dt, now: now)
                self.linkage.update(deltaTime: dt)
                self.updateMechanisms(deltaTime: dt)
                self.applyGravityCompensation()
                self.updateReticle()
            }
        }
    }

    /// React to tool switches: enable the drag gesture only for the Drag tool,
    /// and tear down any transient selection when leaving Transform / Link.
    private func syncToolMode() {
        guard let model, model.tool != lastTool else { return }
        let old = lastTool
        let new = model.tool
        lastTool = new

        // The single pan recognizer drives Drag, Paint and Spray.
        dragPanRecognizer?.isEnabled = (new == .drag || new == .paint || new == .spray)

        if old == .transform { clearTransformSelection() }
        if old == .link { cancelPendingLink() }
        if old == .drag { endDrag() }
        if old == .paint { paint.end() }
        if old == .spray { lastSprayPoint = nil }
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
        case .place:     placeAtSurface(point)
        case .drag:      break // handled by the pan recognizer
        case .transform: selectForTransform(at: point)
        case .gas:       emitGasAtSurface(point)
        case .fluid:     openFluidSourceAtSurface(point)
        case .fling:     flingObject(at: point)
        case .link:      linkTap(at: point)
        case .unlink:    unlinkTap(at: point)
        case .paint:     paintTap(at: point)
        case .spray:     sprayTap(at: point)
        case .explode:   explode(at: point)
        case .erase:     eraseObject(at: point)
        }
    }

    /// Pan-gesture entry point (wired from `ARViewContainer`). The same recognizer
    /// drives Drag, Paint and Spray depending on the active tool.
    func handleDrag(state: UIGestureRecognizer.State, at point: CGPoint) {
        switch model?.tool {
        case .drag:  handleDragMove(state: state, at: point)
        case .paint: handlePaint(state: state, at: point)
        case .spray: handleSpray(state: state, at: point)
        default:     break
        }
    }

    private func handleDragMove(state: UIGestureRecognizer.State, at point: CGPoint) {
        let now = CACurrentMediaTime()
        switch state {
        case .began:
            beginDrag(at: point)
            dragLastTime = now
        case .changed:
            let dt = Float(min(now - dragLastTime, 1.0 / 20.0))
            dragLastTime = now
            updateDrag(at: point, deltaTime: dt)
        case .ended, .cancelled, .failed:
            endDrag()
        default:
            break
        }
    }

    // MARK: Tool actions

    private func placeAtSurface(_ point: CGPoint) {
        guard let model else { return }

        // Uploaded files take a separate (async) path.
        if model.selectedCategory == .upload {
            placeUpload(at: point)
            return
        }

        guard var transform = surfaceTransform(at: point) else {
            model.flash("Aim at a surface")
            Haptics.warning()
            return
        }

        let kind = model.selectedModel
        let material = MaterialFactory.make(model.material)
        let entity = ModelLoader.makeModel(kind, size: model.modelScale, material: material)
        // Spawn just above the surface so the body doesn't start embedded in
        // the collider (which makes the solver eject or tunnel it).
        transform.translation.y += model.modelScale * 0.5 + 0.02
        finishPlacement(of: entity, at: transform, model: model, kind: kind)
        Haptics.success()
    }

    // MARK: Uploads

    /// Copy a picked file into the persistent store and select it. Done
    /// synchronously while the picker's security-scoped URL is still valid.
    func addUpload(from url: URL) {
        guard let model else { return }
        guard UploadStore.canLoad(url) else {
            Haptics.warning()
            model.flash("\(url.pathExtension.uppercased()) isn't supported — convert to .usdz first")
            return
        }
        do {
            let upload = try UploadStore.add(from: url)
            model.uploads = UploadStore.list()
            model.selectedCategory = .upload
            model.selectedUploadID = upload.id
            Haptics.success()
            model.flash("Uploaded \(upload.name)")
        } catch {
            Haptics.warning()
            model.flash("Couldn't import: \(error.localizedDescription)")
        }
    }

    func removeUpload(_ upload: UploadedModel) {
        guard let model else { return }
        UploadStore.remove(upload)
        uploadTemplates.removeValue(forKey: upload.id)
        model.uploads = UploadStore.list()
        if model.selectedUploadID == upload.id {
            model.selectedUploadID = model.uploads.first?.id
        }
    }

    private func placeUpload(at point: CGPoint) {
        guard let model else { return }
        guard let id = model.selectedUploadID,
              let upload = model.uploads.first(where: { $0.id == id }) else {
            model.flash("Pick an uploaded file")
            Haptics.warning()
            return
        }
        guard var transform = surfaceTransform(at: point) else {
            model.flash("Aim at a surface")
            Haptics.warning()
            return
        }
        transform.translation.y += model.modelScale * 0.5 + 0.02
        spawnUpload(upload, at: transform, model: model)
    }

    /// Place an uploaded model, loading + caching its template on first use and
    /// cloning it thereafter so repeat placements are instant.
    private func spawnUpload(_ upload: UploadedModel, at transform: Transform, model: SceneModel) {
        if let template = uploadTemplates[upload.id] {
            finishPlacement(of: template.clone(recursive: true), at: transform, model: model, kind: nil)
            Haptics.success()
            return
        }
        Task {
            do {
                let entity = try await ModelLoader.loadFile(upload.url, longestEdge: model.modelScale)
                uploadTemplates[upload.id] = entity
                finishPlacement(of: entity.clone(recursive: true), at: transform, model: model, kind: nil)
                Haptics.success()
            } catch {
                Haptics.warning()
                model.flash("Couldn't load \(upload.name)")
            }
        }
    }

    private func finishPlacement(of entity: Entity, at transform: Transform,
                                 model: SceneModel, kind: ModelKind?) {
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

        // Physics: dynamic (falls & collides) or static collider. The basketball
        // is intentionally bouncy regardless of the slider.
        let physMat: PhysicsMaterialResource
        if kind == .basketball {
            physMat = .generate(friction: 0.5, restitution: 0.85)
        } else {
            physMat = MaterialFactory.physics(model.material, restitution: model.restitution)
        }
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
        let body = target.body

        // Mechanical / throwable objects actuate instead of being shoved.
        if body.components[PistonComponent.self] != nil { togglePiston(body); return }
        if body.components[BearingComponent.self] != nil { spinBearing(body); return }
        if body.components[GrenadeComponent.self] != nil { throwGrenade(body); return }

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
        if transformTarget === target.body { clearTransformSelection() }
        if pendingLinkSource === target.body { cancelPendingLink() }
        linkage.pruneLinks(removed: target.body)
        target.anchor.removeFromParent()
        placed.removeAll { $0.anchor === target.anchor }
        model?.placedCount = placed.count
        Haptics.impact(.rigid)
    }

    // MARK: Mechanical / throwable behaviour

    /// Per-frame spin for the two sides of every placed bearing.
    private func updateMechanisms(deltaTime dt: Float) {
        guard dt > 0 else { return }
        for object in placed {
            guard let bearing = object.body.components[BearingComponent.self] else { continue }
            spin(object.body, named: "bearing.top", by: bearing.topSpeed * dt)
            spin(object.body, named: "bearing.bottom", by: bearing.bottomSpeed * dt)
        }
    }

    private func spin(_ body: ModelEntity, named name: String, by angle: Float) {
        guard abs(angle) > 1e-6, let part = body.findEntity(named: name) else { return }
        part.orientation = part.orientation * simd_quatf(angle: angle, axis: [0, 1, 0])
    }

    /// Slide a piston's shaft between its collapsed and expanded positions.
    private func togglePiston(_ body: ModelEntity) {
        guard var piston = body.components[PistonComponent.self],
              let shaft = body.findEntity(named: "piston.shaft") else { return }
        piston.extended.toggle()
        var target = shaft.transform
        target.translation.y = piston.extended ? piston.expandedY : piston.collapsedY
        shaft.move(to: target, relativeTo: shaft.parent, duration: 0.35, timingFunction: .easeInOut)
        body.components.set(piston)
        Haptics.impact(.rigid)
    }

    /// Boost a bearing's spin (alternating direction reads as a real bearing).
    private func spinBearing(_ body: ModelEntity) {
        guard var bearing = body.components[BearingComponent.self] else { return }
        bearing.topSpeed += 2.5
        bearing.bottomSpeed -= 3.5
        body.components.set(bearing)
        Haptics.impact(.medium)
    }

    /// Throw + arm a grenade; it detonates after a short fuse, then is removed.
    private func throwGrenade(_ body: ModelEntity) {
        if body.components[PhysicsBodyComponent.self]?.mode != .dynamic {
            let physMat = MaterialFactory.physics(.metal, restitution: model?.restitution ?? 0.4)
            PhysicsFactory.makeDynamic(body, material: physMat)
        }
        let impulse = simd_normalize(cameraForward() + SIMD3<Float>(0, 0.4, 0)) * 2.6
        PhysicsFactory.push(body, impulse: impulse)

        var grenade = body.components[GrenadeComponent.self] ?? GrenadeComponent()
        guard !grenade.armed else { return }   // already counting down
        grenade.armed = true
        body.components.set(grenade)
        Haptics.impact(.heavy)
        model?.flash("Grenade armed!")

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard let self, body.parent != nil else { return }   // erased before it blew
            self.detonate(at: body.position(relativeTo: nil))
            if let object = self.placed.first(where: { $0.body === body }) {
                self.linkage.pruneLinks(removed: body)
                object.anchor.removeFromParent()
                self.placed.removeAll { $0.anchor === object.anchor }
                self.model?.placedCount = self.placed.count
            }
        }
    }

    // MARK: Drag tool (physics-respecting move)

    /// Begin dragging the object under the touch. It becomes kinematic so it
    /// follows the finger precisely while still shoving dynamic objects out of
    /// the way; on release it resumes its prior mode with the drag's momentum.
    private func beginDrag(at point: CGPoint) {
        guard let arView, let target = placedHit(at: point) else {
            model?.flash("Drag onto an object")
            Haptics.warning()
            return
        }
        let body = target.body
        let bodyPos = body.position(relativeTo: nil)
        dragDistance = max(0.2, simd_distance(bodyPos, arView.cameraTransform.translation))
        dragRestoreMode = body.components[PhysicsBodyComponent.self]?.mode ?? .dynamic
        setMode(.kinematic, on: body)
        dragLastPoint = bodyPos
        dragVelocity = .zero
        draggedBody = body
        Haptics.impact(.soft)
    }

    private func updateDrag(at point: CGPoint, deltaTime dt: Float) {
        guard let arView, let body = draggedBody,
              let ray = arView.ray(through: point) else { return }
        let target = ray.origin + ray.direction * dragDistance
        if dt > 0 {
            dragVelocity = (target - dragLastPoint) / dt
            // Clamp so a fast flick doesn't launch it across the room.
            let speed = simd_length(dragVelocity)
            if speed > 6 { dragVelocity *= 6 / speed }
        }
        dragLastPoint = target
        body.setPosition(target, relativeTo: nil)
    }

    private func endDrag() {
        guard let body = draggedBody else { return }
        draggedBody = nil
        setMode(dragRestoreMode, on: body)
        // Hand the released object its drag momentum so it keeps moving / falls.
        if dragRestoreMode == .dynamic {
            body.components.set(PhysicsMotionComponent(linearVelocity: dragVelocity,
                                                       angularVelocity: .zero))
        }
    }

    // MARK: Transform tool (free transform, ignores physics)

    /// Select the tapped object for free transforming. Physics is frozen
    /// (static) so it holds whatever position/rotation/scale you give it, and
    /// RealityKit's built-in gestures drive translate / rotate / scale.
    private func selectForTransform(at point: CGPoint) {
        guard let arView, let target = placedHit(at: point) else {
            model?.flash("Tap an object to transform")
            Haptics.warning()
            return
        }
        if transformTarget === target.body { return } // already selected
        clearTransformSelection()
        let body = target.body
        setMode(.static, on: body)
        transformGestures = arView.installGestures(.all, for: body)
        transformTarget = body
        setHighlight(true, on: body)
        Haptics.impact(.soft)
        model?.flash("Drag · pinch · twist to transform")
    }

    private func clearTransformSelection() {
        // The concrete entity recognizers are all UIGestureRecognizers; cast so
        // we can disable + detach them regardless of the protocol's declaration.
        for gesture in transformGestures {
            guard let recognizer = gesture as? UIGestureRecognizer else { continue }
            recognizer.isEnabled = false
            arView?.removeGestureRecognizer(recognizer)
        }
        transformGestures.removeAll()
        if let body = transformTarget { setHighlight(false, on: body) }
        transformTarget = nil
    }

    // MARK: Link tool (face-to-face constraints)

    private func linkTap(at point: CGPoint) {
        guard let (target, world) = placedHitDetailed(at: point) else {
            model?.flash("Tap a face on a placed object")
            Haptics.warning()
            return
        }
        let body = target.body
        let local = body.convert(position: world, from: nil)

        guard let source = pendingLinkSource else {
            pendingLinkSource = body
            pendingLinkLocal = local
            pendingLinkWorld = world
            setHighlight(true, on: body)
            Haptics.impact(.soft)
            model?.flash("Tap a face on a second object")
            return
        }

        setHighlight(false, on: source)
        let model = self.model
        let restLength: Float
        if model?.linkDistanceAuto ?? true {
            restLength = simd_distance(pendingLinkWorld, world)
        } else {
            restLength = model?.linkDistance ?? 0.2
        }
        let gains = linkGains(model?.linkElasticity ?? 0)

        let linked = linkage.link(source, body,
                                  localA: pendingLinkLocal, localB: local,
                                  restLength: restLength,
                                  stiffness: gains.stiffness,
                                  damping: gains.damping,
                                  maxForce: gains.maxForce)
        pendingLinkSource = nil
        if linked {
            Haptics.success()
            model?.flash(restLength < 0.02 ? "Joined" : "Linked")
        } else {
            Haptics.warning()
            model?.flash("Pick a different object")
        }
    }

    /// Map the elasticity slider (0 = rigid … 1 = stretchy) to PD gains.
    private func linkGains(_ elasticity: Float) -> (stiffness: Float, damping: Float, maxForce: Float) {
        let e = max(0, min(1, elasticity))
        let stiffness = lerp(320, 45, e)
        let damping = lerp(34, 4, e)
        let maxForce = lerp(200, 90, e)
        return (stiffness, damping, maxForce)
    }

    private func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    private func cancelPendingLink() {
        if let source = pendingLinkSource { setHighlight(false, on: source) }
        pendingLinkSource = nil
    }

    // MARK: Unlink tool

    private func unlinkTap(at point: CGPoint) {
        guard let target = placedHit(at: point) else {
            model?.flash("Tap a linked object")
            Haptics.warning()
            return
        }
        let removed = linkage.unlink(target.body)
        if removed > 0 {
            Haptics.success()
            model?.flash("Removed \(removed) link\(removed == 1 ? "" : "s")")
        } else {
            Haptics.warning()
            model?.flash("No links on that object")
        }
    }

    // MARK: Paint tool (free-form 3D lines)

    private func handlePaint(state: UIGestureRecognizer.State, at point: CGPoint) {
        switch state {
        case .began:
            beginStroke()
            paintAddPoint(point)
        case .changed:
            paintAddPoint(point)
        case .ended, .cancelled, .failed:
            paint.end()
        default:
            break
        }
    }

    private func paintTap(at point: CGPoint) {
        beginStroke()
        paintAddPoint(point)
        paint.end()
        Haptics.impact(.light)
    }

    private func beginStroke() {
        guard let model else { return }
        let material = MaterialFactory.paint(UIColor(model.paintColor), kind: model.material)
        paint.begin(material: material, radius: 0.007)
    }

    private func paintAddPoint(_ point: CGPoint) {
        guard let p = paintWorldPoint(at: point) else { return }
        paint.addPoint(p)
    }

    /// Paint lands on a real surface if the ray hits one, otherwise floats at a
    /// fixed distance in front of the camera so you can draw in mid-air.
    private func paintWorldPoint(at point: CGPoint) -> SIMD3<Float>? {
        if let transform = surfaceTransform(at: point) {
            return transform.translation
        }
        guard let ray = arView?.ray(through: point) else { return nil }
        return ray.origin + ray.direction * 0.45
    }

    // MARK: Spray-paint tool (sticks to flat surfaces)

    private func handleSpray(state: UIGestureRecognizer.State, at point: CGPoint) {
        switch state {
        case .began:
            lastSprayPoint = nil
            sprayDab(at: point)
        case .changed:
            sprayDab(at: point)
        case .ended, .cancelled, .failed:
            lastSprayPoint = nil
        default:
            break
        }
    }

    private func sprayTap(at point: CGPoint) {
        lastSprayPoint = nil
        sprayDab(at: point)
    }

    /// Place one spray dab on the surface under the touch. The dab's size + blur
    /// scale with the camera→surface distance.
    private func sprayDab(at point: CGPoint) {
        guard let arView, let model,
              let hit = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first else {
            return   // spray only sticks to surfaces
        }
        let worldTransform = hit.worldTransform
        let position = SIMD3<Float>(worldTransform.columns.3.x,
                                    worldTransform.columns.3.y,
                                    worldTransform.columns.3.z)

        // Throttle so a drag lays an even line rather than a pile of dabs.
        if let last = lastSprayPoint, simd_distance(last, position) < spraySpacing { return }
        lastSprayPoint = position

        let distance = simd_distance(arView.cameraTransform.translation, position)
        let dab = SprayPaintFactory.dab(color: UIColor(model.paintColor), distance: distance)
        dab.position.y += 0.002   // lift along the surface normal to avoid z-fighting

        let anchor = AnchorEntity(.world(transform: worldTransform))
        anchor.addChild(dab)
        worldRoot.addChild(anchor)
        sprayDabs.append(anchor)
    }

    // MARK: Explode tool

    private let explosionRadius: Float = 1.2
    private let explosionPower: Float = 3.2

    private func explode(at point: CGPoint) {
        guard let center = explosionPoint(at: point) else {
            model?.flash("Aim into the scene")
            Haptics.warning()
            return
        }
        detonate(at: center)
        model?.flash("Boom")
    }

    /// The shared blast: a radial impulse with distance falloff + upward kick,
    /// plus a particle burst. Static objects in range are woken into dynamic
    /// bodies so the blast actually tosses them. Used by Explode and grenades.
    private func detonate(at center: SIMD3<Float>) {
        let physMat = MaterialFactory.physics(model?.material ?? .matte,
                                              restitution: model?.restitution ?? 0.4)
        for object in placed {
            let pos = object.body.position(relativeTo: nil)
            let offset = pos - center
            let dist = simd_length(offset)
            guard dist < explosionRadius else { continue }
            if object.body.components[PhysicsBodyComponent.self]?.mode != .dynamic {
                PhysicsFactory.makeDynamic(object.body, material: physMat)
            }
            let dir = dist > 1e-3 ? offset / dist : SIMD3<Float>(0, 1, 0)
            let falloff = 1 - (dist / explosionRadius)
            let impulse = (dir + SIMD3<Float>(0, 0.6, 0)) * explosionPower * falloff
            object.body.applyLinearImpulse(impulse, relativeTo: nil)
        }

        spawnExplosionFX(at: center)
        Haptics.impact(.heavy)
    }

    private func explosionPoint(at point: CGPoint) -> SIMD3<Float>? {
        if let transform = surfaceTransform(at: point) {
            return transform.translation
        }
        // No surface hit — detonate a fixed distance along the touch ray.
        guard let ray = arView?.ray(through: point) else { return nil }
        return ray.origin + ray.direction * 0.8
    }

    private func spawnExplosionFX(at center: SIMD3<Float>) {
        let emitter = ParticleFactory.explosion()
        var transform = Transform()
        transform.translation = center
        let anchor = AnchorEntity(.world(transform: transform.matrix))
        anchor.addChild(emitter)
        worldRoot.addChild(anchor)
        // One-shot: stop emitting almost immediately, then clean up.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            ParticleFactory.extinguish(emitter)
            try? await Task.sleep(for: .seconds(1))
            anchor.removeFromParent()
        }
    }

    // MARK: Selection highlight

    /// A faint emissive box fitted around an object to show it's selected /
    /// pending. Carries no physics, so it never interferes.
    private func setHighlight(_ on: Bool, on body: ModelEntity) {
        let name = "selection.highlight"
        if on {
            guard !body.children.contains(where: { $0.name == name }) else { return }
            let bounds = body.visualBounds(relativeTo: body)
            var mat = PhysicallyBasedMaterial()
            mat.baseColor = .init(tint: .black)
            mat.emissiveColor = .init(color: UIColor(red: 0.62, green: 0.55, blue: 0.95, alpha: 1))
            mat.emissiveIntensity = 1.0
            mat.roughness = 1.0
            mat.metallic = 0.0
            mat.blending = .transparent(opacity: 0.18)
            let extents = max(bounds.extents, SIMD3<Float>(repeating: 0.02)) * 1.08
            let box = ModelEntity(mesh: .generateBox(size: extents), materials: [mat])
            box.position = bounds.center
            box.name = name
            body.addChild(box)
        } else {
            body.children.filter { $0.name == name }.forEach { $0.removeFromParent() }
        }
    }

    private func setMode(_ mode: PhysicsBodyMode, on body: ModelEntity) {
        guard var component = body.components[PhysicsBodyComponent.self] else { return }
        component.mode = mode
        body.components.set(component)
    }

    // MARK: Capture (photo / video)

    /// Snapshot the rendered AR scene (camera feed + virtual content, without
    /// the SwiftUI overlay) and save it to the photo library.
    func capturePhoto() {
        guard let arView else { return }
        arView.snapshot(saveToHDR: false) { [weak self] image in
            Task { @MainActor in
                guard let self, let model = self.model else { return }
                guard let image else {
                    Haptics.warning()
                    model.flash("Couldn't capture photo")
                    return
                }
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                Haptics.success()
                model.flash("Photo saved")
            }
        }
    }

    /// Start or stop a screen recording. The UI hides its chrome while recording
    /// (driven by `model.isRecording`) so the captured video is clean.
    func toggleRecording() {
        guard let model else { return }
        if model.isRecording {
            // Flip UI back immediately; the save finishes in the background.
            model.isRecording = false
            model.recordingStart = nil
            Haptics.impact(.medium)
            recorder.stopAndSave { [weak self] result in
                Task { @MainActor in
                    guard let model = self?.model else { return }
                    switch result {
                    case .success:
                        Haptics.success()
                        model.flash("Video saved")
                    case .failure(let error):
                        Haptics.warning()
                        model.flash(error.localizedDescription)
                    }
                }
            }
        } else {
            recorder.start { [weak self] started in
                Task { @MainActor in
                    guard let model = self?.model else { return }
                    if started {
                        model.isRecording = true
                        model.recordingStart = Date()
                        Haptics.impact(.medium)
                    } else {
                        Haptics.warning()
                        model.flash("Recording unavailable")
                    }
                }
            }
        }
    }

    func clearAll() {
        clearTransformSelection()
        cancelPendingLink()
        endDrag()
        paint.end()
        paint.clear()
        linkage.clear()
        for o in placed { o.anchor.removeFromParent() }
        for g in gasEmitters { g.removeFromParent() }
        for d in sprayDabs { d.removeFromParent() }
        placed.removeAll()
        gasEmitters.removeAll()
        sprayDabs.removeAll()
        lastSprayPoint = nil
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
        placedHitDetailed(at: point)?.object
    }

    /// Like `placedHit`, but also returns the world-space point on the object's
    /// surface that was hit (used by the Link tool for face-to-face attachment).
    private func placedHitDetailed(at point: CGPoint) -> (object: PlacedObject, world: SIMD3<Float>)? {
        guard let arView else { return nil }
        for hit in arView.hitTest(point, query: .all, mask: .all) {
            var current: Entity? = hit.entity
            while let entity = current {
                if let match = placed.first(where: { $0.body === entity || $0.anchor === entity }) {
                    return (match, hit.position)
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
