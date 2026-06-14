import Foundation
import Observation
import SwiftUI

/// The tool the user is currently "holding". A tap in the AR view performs the
/// active tool's action at the raycast hit point.
enum PlaygroundTool: String, CaseIterable, Identifiable {
    case place      // drop the selected model / shape
    case drag       // move an object with your finger, still colliding with the world
    case transform  // freely translate / rotate / scale, ignoring physics
    case fling      // tap a placed object to push it (physics) / actuate mechanisms
    case link       // tie two objects together (face-to-face constraint)
    case unlink     // remove links from a tapped object
    case paint      // draw free-form 3D lines
    case spray      // spray soft paint onto real surfaces
    case explode    // detonate a radial blast that flings nearby objects
    case gas        // emit rising gas / smoke
    case fluid      // open a fluid (water) source
    case erase      // remove a tapped object

    var id: String { rawValue }

    var title: String {
        switch self {
        case .place:     return "Place"
        case .drag:      return "Drag"
        case .transform: return "Transform"
        case .fling:     return "Fling"
        case .link:      return "Link"
        case .unlink:    return "Unlink"
        case .paint:     return "Paint"
        case .spray:     return "Spray"
        case .explode:   return "Explode"
        case .gas:       return "Gas"
        case .fluid:     return "Fluid"
        case .erase:     return "Erase"
        }
    }

    var systemImage: String {
        switch self {
        case .place:     return "cube.transparent"
        case .drag:      return "arrow.up.and.down.and.arrow.left.and.right"
        case .transform: return "move.3d"
        case .fling:     return "hand.draw"
        case .link:      return "link"
        case .unlink:    return "link.badge.plus"
        case .paint:     return "scribble.variable"
        case .spray:     return "paintbrush.pointed.fill"
        case .explode:   return "flame.fill"
        case .gas:       return "smoke"
        case .fluid:     return "drop"
        case .erase:     return "trash"
        }
    }

    /// One-line coaching shown above the dock so the active tool is discoverable.
    var instruction: String {
        switch self {
        case .place:     return "Aim at a surface, then tap to place"
        case .drag:      return "Drag an object to move it — it still collides"
        case .transform: return "Tap an object, then drag · pinch · twist to transform"
        case .fling:     return "Tap to shove — or actuate a piston / bearing / grenade"
        case .link:      return "Tap a face on two objects to link them"
        case .unlink:    return "Tap a linked object to cut its links"
        case .paint:     return "Drag to paint a 3D line"
        case .spray:     return "Drag across a surface to spray — closer is sharper"
        case .explode:   return "Tap to set off a blast that flings nearby objects"
        case .gas:       return "Aim at a surface, then tap to release gas"
        case .fluid:     return "Aim at a surface, then tap to pour fluid"
        case .erase:     return "Tap a placed object to remove it"
        }
    }

    /// Whether this tool drops content on a real surface (and so uses the reticle).
    var usesSurface: Bool {
        switch self {
        case .place, .gas, .fluid, .explode: return true
        case .drag, .transform, .fling, .link, .unlink, .paint, .spray, .erase: return false
        }
    }
}

/// Top-level groupings shown as tabs in the Place palette.
enum ModelCategory: String, CaseIterable, Identifiable {
    case primitives, mechanical, throwable, upload
    var id: String { rawValue }

    var title: String {
        switch self {
        case .primitives: return "Primitives"
        case .mechanical: return "Mechanical"
        case .throwable:  return "Throwable"
        case .upload:     return "Upload"
        }
    }

    var systemImage: String {
        switch self {
        case .primitives: return "cube"
        case .mechanical: return "gearshape.2"
        case .throwable:  return "burst"
        case .upload:     return "square.and.arrow.up"
        }
    }

    /// Built-in models offered by this category (empty for Upload, which is a
    /// dynamic list of user files).
    var models: [ModelKind] {
        switch self {
        case .primitives: return [.cube, .sphere, .cylinder, .cone]
        case .mechanical: return [.piston, .bearing]
        case .throwable:  return [.grenade, .basketball]
        case .upload:     return []
        }
    }
}

/// Built-in models across the Primitives / Mechanical / Throwable categories.
/// (User uploads are tracked separately as `UploadedModel`.)
enum ModelKind: String, CaseIterable, Identifiable {
    case sphere, cube, cylinder, cone   // primitives
    case piston, bearing                // mechanical
    case grenade, basketball            // throwable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sphere:     return "Sphere"
        case .cube:       return "Cube"
        case .cylinder:   return "Cylinder"
        case .cone:       return "Cone"
        case .piston:     return "Piston"
        case .bearing:    return "Bearing"
        case .grenade:    return "Grenade"
        case .basketball: return "Basketball"
        }
    }

    var systemImage: String {
        switch self {
        case .sphere:     return "circle.fill"
        case .cube:       return "cube.fill"
        case .cylinder:   return "cylinder.fill"
        case .cone:       return "cone.fill"
        case .piston:     return "pistons"
        case .bearing:    return "gear"
        case .grenade:    return "burst.fill"
        case .basketball: return "basketball.fill"
        }
    }
}

enum SurfaceMaterial: String, CaseIterable, Identifiable {
    case matte, metal, glass, rubber
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Single source of truth shared between the SwiftUI UI and the RealityKit
/// session. The UI mutates published state; `ARSessionController` reads it and
/// the UI calls through to the controller for imperative actions.
@MainActor
@Observable
final class SceneModel {

    // MARK: Tool / palette selection
    var tool: PlaygroundTool = .place
    var selectedCategory: ModelCategory = .primitives
    var selectedModel: ModelKind = .cube
    var material: SurfaceMaterial = .metal

    // MARK: Uploads (user-imported model files)
    var uploads: [UploadedModel] = []
    var selectedUploadID: UUID?

    // MARK: Link tool tuning
    var linkElasticity: Float = 0      // 0 = rigid strut … 1 = stretchy spring
    var linkDistanceAuto: Bool = true  // keep the objects' current separation
    var linkDistance: Float = 0.2      // metres when not auto (0 = join faces)

    // MARK: Paint tool
    var paintColor: Color = Color(red: 0.95, green: 0.3, blue: 0.3)

    // MARK: World simulation settings
    var gravity: Float = 9.81          // m/s², applied to dynamic bodies
    var physicsEnabled: Bool = true    // newly placed objects are dynamic
    var restitution: Float = 0.4       // bounciness 0…1
    var modelScale: Float = 0.25       // normalized longest-edge size in metres

    // MARK: Realism toggles
    var realisticLighting = true       // image-based lighting from the room
    var groundingShadows = true        // contact shadows under objects
    var reflections = true             // environment reflections on metal/glass
    var peopleOcclusion = true         // people pass in front of virtual content

    // MARK: HUD state (driven by the controller)
    var trackingState: String = "Starting…"
    var meshAvailable: Bool = false    // LiDAR scene reconstruction present
    var placedCount: Int = 0
    var showSettings = false
    var statusMessage: String?
    var surfaceDetected: Bool = false  // reticle has locked onto a real surface

    // MARK: Capture state
    var isRecording = false            // a screen recording is in progress
    var recordingStart: Date?          // when the current recording began

    /// Bridge to the imperative RealityKit layer. Set once the AR view loads.
    weak var controller: ARSessionController?

    // MARK: Imperative actions (forwarded to the controller)

    func addUpload(from url: URL) {
        controller?.addUpload(from: url)
    }

    func removeUpload(_ upload: UploadedModel) {
        controller?.removeUpload(upload)
    }

    func clearScene() {
        controller?.clearAll()
    }

    func capturePhoto() {
        controller?.capturePhoto()
    }

    func toggleRecording() {
        controller?.toggleRecording()
    }

    func applySettings() {
        controller?.applyWorldSettings()
    }

    func flash(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if statusMessage == message { statusMessage = nil }
        }
    }
}
