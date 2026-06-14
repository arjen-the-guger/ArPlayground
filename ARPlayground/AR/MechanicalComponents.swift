import RealityKit

/// Custom ECS components that mark "mechanical" / "throwable" objects so the
/// controller can give them special behaviour when flung. Registered once in
/// `ARSessionController.attach` (assigning an unregistered component would also
/// auto-register it, but explicit registration is clearer and order-safe).

/// A piston: a housing plus a sliding shaft. Flinging it toggles the shaft
/// between its collapsed and expanded positions (animated). The two parts are
/// children of one rigid body so the whole piston places / collides as a unit.
struct PistonComponent: Component {
    var extended: Bool
    var collapsedY: Float
    var expandedY: Float
}

/// A bearing: two coaxial discs that spin independently about the shared axis
/// but stay locked together (they're children of one body, so they can never
/// move apart). Flinging it boosts the spin of both sides.
struct BearingComponent: Component {
    var topSpeed: Float       // rad/s
    var bottomSpeed: Float    // rad/s (opposite sign reads as a real bearing)
}

/// A throwable grenade. Flinging throws + arms it; after a short fuse it
/// detonates (radial blast + particle burst) and is removed.
struct GrenadeComponent: Component {
    var armed: Bool = false
}
