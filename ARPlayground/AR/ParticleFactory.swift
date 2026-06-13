import RealityKit
import UIKit

/// GPU particle systems for the "gas" tool. RealityKit's `ParticleEmitterComponent`
/// runs entirely on the GPU, so we can emit thousands of soft, rising, fading
/// puffs cheaply. This is a volumetric *approximation* of gas/smoke (buoyant,
/// diffusing, light-scattering) rather than a grid-based Navier–Stokes solve.
@MainActor
enum ParticleFactory {

    /// A rising, expanding, dissipating gas plume anchored at a point.
    static func gasEmitter() -> Entity {
        let entity = Entity()
        var particles = ParticleEmitterComponent()

        // Emit from a small volume at the base of the plume.
        particles.emitterShape = .sphere
        particles.emitterShapeSize = [0.04, 0.04, 0.04]
        particles.birthLocation = .volume
        particles.speed = 0.06
        particles.speedVariation = 0.03

        var main = particles.mainEmitter
        main.birthRate = 220
        main.size = 0.05
        main.sizeVariation = 0.03
        main.lifeSpan = 3.4
        main.lifeSpanVariation = 0.8
        // Buoyancy: gas accelerates upward and drifts.
        main.acceleration = [0, 0.22, 0]
        main.dampingFactor = 0.2
        main.spreadingAngle = .pi / 6
        main.billboardMode = .billboard

        // Soft grey-white smoke that fades to fully transparent.
        main.color = .evolving(
            start: .single(UIColor(white: 0.85, alpha: 0.55)),
            end:   .single(UIColor(white: 0.55, alpha: 0.0))
        )
        main.opacityCurve = .quickFadeInOut

        particles.mainEmitter = main
        particles.isEmitting = true
        entity.components.set(particles)
        entity.name = "gas.emitter"
        return entity
    }

    /// A brief fiery burst spraying outward in all directions — the visual half
    /// of the "explode" tool (the impulse is applied separately to nearby bodies).
    static func explosion() -> Entity {
        let entity = Entity()
        var particles = ParticleEmitterComponent()

        particles.emitterShape = .sphere
        particles.emitterShapeSize = [0.05, 0.05, 0.05]
        particles.birthLocation = .volume
        particles.speed = 1.6
        particles.speedVariation = 0.8

        var main = particles.mainEmitter
        main.birthRate = 1800
        main.size = 0.03
        main.sizeVariation = 0.02
        main.lifeSpan = 0.6
        main.lifeSpanVariation = 0.25
        main.acceleration = [0, -0.6, 0]      // embers arc and fall
        main.spreadingAngle = .pi             // full sphere
        main.billboardMode = .billboard
        main.color = .evolving(
            start: .single(UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1.0)),
            end:   .single(UIColor(red: 0.7, green: 0.2, blue: 0.1, alpha: 0.0))
        )
        main.opacityCurve = .quickFadeInOut

        particles.mainEmitter = main
        particles.isEmitting = true
        entity.components.set(particles)
        entity.name = "explosion.emitter"
        return entity
    }

    /// Stop emitting but let in-flight particles finish their life, then the
    /// caller removes the entity.
    static func extinguish(_ entity: Entity) {
        guard var p = entity.components[ParticleEmitterComponent.self] else { return }
        p.isEmitting = false
        entity.components.set(p)
    }
}
