import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(SceneModel.self) private var model
    @State private var showImporter = false

    /// File types we accept for "any 3D model". USDZ/USD are loaded natively;
    /// other formats should be converted to USDZ (Reality Converter) first.
    private var importTypes: [UTType] {
        var types: [UTType] = [.usdz]
        if let usd = UTType("com.pixar.universal-scene-description") { types.append(usd) }
        if let reality = UTType("com.apple.reality") { types.append(reality) }
        types.append(.threeDContent)
        return types
    }

    var body: some View {
        ZStack {
            ARViewContainer(model: model)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if !model.isRecording { TopHUD() }
                Spacer()
                if !model.isRecording {
                    statusToast
                    ControlDeck(showImporter: $showImporter)
                        .padding(.bottom, 8)
                }
            }
            .padding(.horizontal, 14)
            .animation(.spring(duration: 0.3), value: model.statusMessage)
            .animation(.spring(duration: 0.3), value: model.isRecording)

            // Photo / video capture, pinned to the right edge (vertically
            // centered so it clears the HUD and dock). Stays up while recording.
            HStack {
                Spacer()
                CaptureControls()
            }
            .padding(.trailing, 14)
        }
        .sheet(isPresented: Binding(get: { model.showSettings },
                                    set: { model.showSettings = $0 })) {
            SettingsPanel()
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.addUpload(from: url) }
            case .failure(let error):
                model.flash("Couldn't open: \(error.localizedDescription)")
            }
        }
    }

    @ViewBuilder
    private var statusToast: some View {
        if let message = model.statusMessage {
            Text(message)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .liquidGlassCapsule(tint: .arAccent)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 12)
        }
    }
}
