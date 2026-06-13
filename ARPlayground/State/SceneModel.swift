import Foundation
import Observation
import SwiftUI

/// The tool the user is currently "holding". A tap in the AR view performs the
/// active tool's action at the raycast hit point.
enum PlaygroundTool: String, CaseIterable, Identifiable {
    case place      // drop the selected model / shape
    case fling      // tap a placed object to push it (physics)
    case gas        // emit rising gas / smoke
    case fluid      // open a fluid (water) source
    case erase      // remove a tapped object

    var id: String { rawValue }

    var title: String {
        switch self {
        case .place: return "Place"
        case .fling: return "Fling"
        case .gas:   return "Gas"
        case .fluid: return "Fluid"
        case .erase: return "Erase"
        }
    }

    var systemImage: String {
        switch self {
        case .place: return "cube.transparent"
        case .fling: return "hand.draw"
        case .gas:   return "smoke"
        case .fluid: return "drop"
        case .erase: return "trash"
        }
    }

    /// One-line coaching shown above the dock so the active tool is discoverable.
    var instruction: String {
        switch self {
        case .place: return "Aim at a surface, then tap to place"
        case .fling: return "Tap a placed object to shove it"
        case .gas:   return "Aim at a surface, then tap to release gas"
        case .fluid: return "Aim at a surface, then tap to pour fluid"
        case .erase: return "Tap a placed object to remove it"
        }
    }

    /// Whether this tool drops content on a real surface (and so uses the reticle).
    var usesSurface: Bool {
        switch self {
        case .place, .gas, .fluid: return true
        case .fling, .erase:       return false
        }
    }
}

/// Built-in primitive models, plus a marker for "user imported file".
enum ModelKind: String, CaseIterable, Identifiable {
    case sphere, cube, cylinder, cone
    case imported

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sphere:   return "Sphere"
        case .cube:     return "Cube"
        case .cylinder: return "Cylinder"
        case .cone:     return "Cone"
        case .imported: return "Import"
        }
    }

    var systemImage: String {
        switch self {
        case .sphere:   return "circle.fill"
        case .cube:     return "cube.fill"
        case .cylinder: return "cylinder.fill"
        case .cone:     return "cone.fill"
        case .imported: return "square.and.arrow.down.fill"
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
    var selectedModel: ModelKind = .cube
    var material: SurfaceMaterial = .metal

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

    /// Bridge to the imperative RealityKit layer. Set once the AR view loads.
    weak var controller: ARSessionController?

    // MARK: Imperative actions (forwarded to the controller)

    func importModel(from url: URL) {
        controller?.importModel(from: url)
    }

    func clearScene() {
        controller?.clearAll()
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
