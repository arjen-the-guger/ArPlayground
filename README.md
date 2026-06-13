# AR Playground

A native **SwiftUI + ARKit + RealityKit** iPhone app: a sandbox for the real world.
Drop 3D models into your room, give them realistic lighting / shadows / reflections,
turn on physics that respects real surfaces, and play with **gas** and **fluid**
simulations — all wrapped in **Liquid Glass** UI.

> Built on Windows, so it has **not** been compiled here. Open it on a Mac with
> Xcode 16+ and an iOS 18+ device. See *Limitations* for the honest details on the
> gas/fluid simulation.

## Features

| Tool | What it does |
|------|--------------|
| **Place** | Taps a real surface and drops the selected model. Built-in primitives (sphere/cube/cylinder/cone) or **any imported `.usdz`/`.usd`** file. |
| **Drag** | Drag an object with your finger. It turns kinematic so it follows precisely while **still colliding** with the world and shoving other objects, then resumes physics with your drag's momentum on release. |
| **Transform** | Tap an object to select it, then **drag · pinch · twist** to translate / scale / rotate it freely — physics is frozen so it holds exactly where you put it. |
| **Fling** | Tap a placed object to shove it with a physics impulse. |
| **Link** | Tap two objects to tie them together with a distance constraint (a stiff, damped strut). Link to a static object to make a pendulum. A glowing rod shows the connection. |
| **Explode** | Tap anywhere to detonate a radial blast — nearby objects (woken into dynamic bodies if needed) are flung outward and up, with a fiery particle burst. |
| **Gas** | Emits a buoyant, diffusing GPU particle plume that rises and fades. |
| **Fluid** | Opens a water source that sprays hundreds of dynamic droplets which pour, pool and splash on the **real** scanned world. |
| **Erase** | Tap to remove an object (and any links attached to it). |
| **Tune** | Gravity, bounciness, imported size, and realism toggles. |

### Capture
- **Photo** — the shutter button snapshots the rendered AR scene (camera feed + virtual content, *without* the UI) via `ARView.snapshot` and saves it straight to your photo library.
- **Video** — the record button screen-records through **ReplayKit** (with mic audio) and saves the clip to your library. The HUD, dock and hints **auto-hide while recording** for a clean shot, leaving just a live timer + stop button on the right edge.
- Both live in a capture cluster pinned to the right edge, clear of the HUD and tool dock.

### Feel & polish
- **Surface-tracking reticle** — a soft FocusSquare-style pad follows the real surface under the screen centre, so you always know the app has locked on and where content will land. It only appears for surface tools (Place/Gas/Fluid).
- **Live "surface ready" dot** in the on-screen hint pill: orange while scanning, green the moment a surface is found.
- **Contextual hints** — a one-line caption above the dock tells you exactly what the active tool does.
- **Haptics on every action** — a satisfying tap on place/fling/erase and a warning buzz when you miss a surface or an object.
- **ARKit coaching overlay** — guides you to pan and scan on launch and whenever tracking is lost.

### Realism
- **Image-based lighting** + **environment reflections** from the live camera feed (`environmentTexturing = .automatic`), so metal and glass mirror your actual room.
- **Grounding (contact) shadows** under every placed object.
- A directional key light for crisp, directional shadows.
- **People occlusion** — real people pass in front of virtual content.
- On **LiDAR** devices, the room is reconstructed as a mesh that acts as a real **physics collider** and **occluder**: objects land on actual tables/floors, gas drifts around them, fluid pools on real surfaces.
- On devices **without LiDAR**, invisible static colliders are generated from ARKit's detected planes, so ground/table collision still works (just less detailed than the mesh).

### Scale normalization
Every model — built-in or imported — is auto-scaled so its **longest edge** matches a
target size (default 25 cm, adjustable in Settings). A model authored in millimetres,
metres or inches all arrive sane. See `ModelLoader.normalize`.

### Liquid Glass
The HUD, tool dock and model tray use the iOS 26 `.glassEffect` material via the
helpers in `GlassKit.swift`. On iOS 18–25 they **degrade gracefully** to `.ultraThinMaterial`
so the app still builds and runs.

## Build

You need a Mac + Xcode 16+. Two options:

### A. XcodeGen (recommended)
```sh
brew install xcodegen
cd arplayground
xcodegen generate
open ARPlayground.xcodeproj
```
Set your Team ID in `project.yml` (or in Xcode → Signing) and run on a **real device**
(ARKit doesn't work in the Simulator).

### B. Manual
1. Xcode → New → App (SwiftUI, iOS).
2. Delete the template `ContentView`/`App` files.
3. Drag the `ARPlayground/` folder in (Copy items, Create groups).
4. Use `ARPlayground/Info.plist` (it already has `NSCameraUsageDescription` + `arkit`).
5. Deployment target iOS 18.0, run on a device.

## Requirements
- iOS 18.0+ device (iOS 26+ to see real Liquid Glass).
- Camera permission (prompted on first launch).
- LiDAR (iPhone 12 Pro and later Pro models) unlocks real-world mesh physics/occlusion. Without it, placement falls back to plane estimation and still works.

## Project layout
```
ARPlayground/
  App/ARPlaygroundApp.swift      App entry
  State/SceneModel.swift         Observable shared state (tools, settings)
  AR/
    ARViewContainer.swift        SwiftUI ↔ ARView bridge + tap gesture
    ARSessionController.swift     Session config, lighting, shadows, tap routing
    ModelLoader.swift            Load + scale-normalize models
    MaterialFactory.swift        PBR materials (matte/metal/glass/rubber)
    PhysicsFactory.swift         Collision + rigid bodies, impulses
    ParticleFactory.swift        Gas/smoke GPU particles
    FluidSystem.swift            Physics-droplet fluid (pooled)
    LinkageSystem.swift          Distance-constraint links + connector rods
    FocusReticle.swift           Surface-tracking aiming pad
    ScreenRecorder.swift         ReplayKit video capture + Photos save
  UI/
    ContentView.swift            Composition + file importer
    TopHUD.swift                 Tracking / mesh / count pill
    ControlDeck.swift            Tool dock + model/material tray + hint
    CaptureControls.swift        Photo shutter + video record cluster
    SettingsPanel.swift          Sandbox tuning sheet
    GlassKit.swift               Liquid Glass helpers + fallback
    Haptics.swift                Feedback-generator helpers
```

## Limitations (read me)
- **Gas** is a volumetric *approximation* via `ParticleEmitterComponent` (buoyant, diffusing, light-scattering particles) — not a grid-based Navier–Stokes solve. It looks right and is cheap; it does not compute pressure/advection.
- **Fluid** is modeled as many small **dynamic rigid droplets** that genuinely collide with the real-world mesh and each other. This gives real pouring/pooling/splashing behavior, but it is *not* SPH — there's no surface-tension cohesion or a continuous water surface. Droplets are pooled (capped at 600) and recycled for steady performance.
- A true SPH/FLIP fluid or a fluid-grid gas solver would require a custom **Metal compute** pipeline. That's a natural next step if you want physically-exact simulation; the current design isolates each sim behind a small factory so it can be swapped.
- **Links** are enforced as a per-frame **distance constraint** (a stiff, critically-damped PD spring), not RealityKit's built-in physics joints — that API is narrow and version-sensitive, and a solved constraint is robust and tunable. So a link behaves like a slightly springy rigid strut rather than a perfect hinge/ball joint. Very stiff links between light bodies can jitter.
- **Transform** edits ignore physics by freezing the object (static). Scaling also scales its collision shape, so collisions stay consistent, but the object won't fall again until another tool (fling/drag/explode) wakes it back into a dynamic body.
- **Importing non-USD formats** (`.obj`, `.glb`, `.fbx`) requires converting to `.usdz` first (Apple's *Reality Converter*); RealityKit loads USD natively.
