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
| **Place** | Taps a real surface and drops the selected model. Models are grouped into **Primitives**, **Mechanical**, **Throwable** and **Upload** (see *Place palette*). |
| **Drag** | Drag an object with your finger. It turns kinematic so it follows precisely while **still colliding** with the world and shoving other objects, then resumes physics with your drag's momentum on release. |
| **Transform** | Tap an object to select it, then **drag · pinch · twist** to translate / scale / rotate it freely — physics is frozen so it holds exactly where you put it. |
| **Fling** | Tap a placed object to shove it with a physics impulse — or to **actuate** a mechanism: a piston extends/retracts, a bearing spins faster, a grenade is thrown + armed. |
| **Link** | Tap a **face** on two objects to tie those faces together. A tray sets **elasticity** (rigid strut → stretchy spring) and **distance** (Auto keeps the current gap; manual lets you dial it, and **0 joins the faces**). A glowing rod shows the link. |
| **Unlink** | Tap a linked object to cut all of its links. |
| **Paint** | Drag to draw a free-form **3D line** in the chosen colour + material (matte/metal/glass/rubber). Lines snap to a real surface under your finger, or float in mid-air if there isn't one. |
| **Spray** | Drag across a real surface to lay soft **spray-paint** dabs that stick to it. The **blur scales with distance** — close to the surface is small + crisp, far away is big + blurry, like a real spray cone. |
| **Explode** | Tap anywhere to detonate a radial blast — nearby objects (woken into dynamic bodies if needed) are flung outward and up, with a fiery particle burst. |
| **Gas** | Emits a buoyant, diffusing GPU particle plume that rises and fades. |
| **Fluid** | Opens a water source that sprays hundreds of dynamic droplets which pour, pool and splash on the **real** scanned world. |
| **Erase** | Tap to remove an object (and any links attached to it). |
| **Tune** | Gravity, bounciness, imported size, and realism toggles. |

### Place palette
The Place tray is organized into four categories:
- **Primitives** — sphere, cube, cylinder, cone.
- **Mechanical** — a **piston** (a housing + a sliding shaft; Fling toggles it between collapsed and expanded) and a **bearing** (two coaxial discs that spin independently about a shared axle but can never move apart; Fling boosts the spin).
- **Throwable** — a **grenade** (Fling throws + arms it; it detonates on a short fuse) and a **basketball** (a high-restitution ball that really bounces).
- **Upload** — pick any `.usdz` / `.usd` file with **Add file**. Uploads are copied into the app and **persist between launches**, listed as chips you can tap to place again (long-press a chip to delete it). The picker copies the file while its security-scoped URL is still valid, then loads + caches it so repeat placements are instant.

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
    ModelLoader.swift            Build primitives/mechanical/throwable + load uploads
    MechanicalComponents.swift   ECS components: piston / bearing / grenade
    MaterialFactory.swift        PBR materials (matte/metal/glass/rubber) + paint
    PhysicsFactory.swift         Collision + rigid bodies, impulses
    ParticleFactory.swift        Gas/smoke + explosion GPU particles
    FluidSystem.swift            Physics-droplet fluid (pooled)
    LinkageSystem.swift          Face-to-face distance constraints + connector rods
    PaintSystem.swift            Free-form 3D paint strokes
    SprayPaintFactory.swift      Distance-blurred spray-paint decals
    UploadStore.swift            Persists + lists user-uploaded model files
    FocusReticle.swift           Surface-tracking aiming pad
    ScreenRecorder.swift         ReplayKit video capture + Photos save
  UI/
    ContentView.swift            Composition + file importer
    TopHUD.swift                 Tracking / mesh / count pill
    ControlDeck.swift            Tool dock + Place/Link/Paint trays + hint
    CaptureControls.swift        Photo shutter + video record cluster
    SettingsPanel.swift          Sandbox tuning sheet
    GlassKit.swift               Liquid Glass helpers + fallback
    Haptics.swift                Feedback-generator helpers
```

## Limitations (read me)
- **Gas** is a volumetric *approximation* via `ParticleEmitterComponent` (buoyant, diffusing, light-scattering particles) — not a grid-based Navier–Stokes solve. It looks right and is cheap; it does not compute pressure/advection.
- **Fluid** is modeled as many small **dynamic rigid droplets** that genuinely collide with the real-world mesh and each other. This gives real pouring/pooling/splashing behavior, but it is *not* SPH — there's no surface-tension cohesion or a continuous water surface. Droplets are pooled (capped at 600) and recycled for steady performance.
- A true SPH/FLIP fluid or a fluid-grid gas solver would require a custom **Metal compute** pipeline. That's a natural next step if you want physically-exact simulation; the current design isolates each sim behind a small factory so it can be swapped.
- **Links** are enforced as a per-frame **distance constraint** between the two tapped attachment points (a PD spring whose stiffness/damping come from the elasticity slider), not RealityKit's built-in physics joints — that API is narrow and version-sensitive, and a solved constraint is robust and tunable. The force is applied at each body's centre, so it controls the *separation* of the faces but doesn't torque them into alignment. "Rigid" (and "Join", rest length 0) are stiff approximations rather than a perfect weld; very stiff links between light bodies can jitter, and the PD gains may want tuning for unusual masses.
- **Mechanical parts** are gameplay approximations, not solved joints. A **piston**'s shaft is a kinematic child animated between two positions (it doesn't transmit force); a **bearing**'s two discs are spun by a driven animation about the shared axle (not a real torque/free-spin simulation) — but they genuinely can't separate because they're children of one body.
- **Spray paint** dabs are flat, soft-edged decals whose blur is faked with a runtime-generated radial-alpha gradient (cached per blur level) and whose size/softness scale with camera distance. They're laid on the surface the raycast hits and oriented to that hit's frame, so they sit cleanest on horizontal/flat surfaces. **Paint** strokes and spray dabs are purely visual (no collision/physics).
- **Transform** edits ignore physics by freezing the object (static). Scaling also scales its collision shape, so collisions stay consistent, but the object won't fall again until another tool (fling/drag/explode) wakes it back into a dynamic body.
- **Uploads** must be USD-family (`.usdz` / `.usd` / `.usdc` / `.reality`); other formats (`.obj`, `.glb`, `.fbx`) need converting to `.usdz` first (Apple's *Reality Converter*). RealityKit loads USD natively.
