import SwiftUI
import RealityKit
import ARKit

/// Hosts a RealityKit `ARView` inside SwiftUI and wires a tap gesture to the
/// active tool.
struct ARViewContainer: UIViewRepresentable {
    var model: SceneModel

    func makeCoordinator() -> ARSessionController {
        ARSessionController()
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero,
                            cameraMode: .ar,
                            automaticallyConfigureSession: false)
        arView.renderOptions.remove(.disableHDR)

        context.coordinator.attach(arView: arView, model: model)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(ARSessionController.onTap(_:)))
        arView.addGestureRecognizer(tap)

        // The Drag tool's pan. Disabled until the Drag tool is selected so it
        // never competes with RealityKit's built-in transform gestures.
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(ARSessionController.onPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.isEnabled = false
        arView.addGestureRecognizer(pan)
        context.coordinator.dragPanRecognizer = pan

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

extension ARSessionController {
    @objc func onTap(_ sender: UITapGestureRecognizer) {
        guard let view = sender.view else { return }
        handleTap(at: sender.location(in: view))
    }

    @objc func onPan(_ sender: UIPanGestureRecognizer) {
        guard let view = sender.view else { return }
        handleDrag(state: sender.state, at: sender.location(in: view))
    }
}
