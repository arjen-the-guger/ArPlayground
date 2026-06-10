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
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

extension ARSessionController {
    @objc func onTap(_ sender: UITapGestureRecognizer) {
        guard let view = sender.view else { return }
        let point = sender.location(in: view)
        handleTap(at: point)
    }
}
