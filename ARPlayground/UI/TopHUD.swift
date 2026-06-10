import SwiftUI

/// Floating status pill at the top: tracking state, LiDAR mesh availability and
/// object count.
struct TopHUD: View {
    @Environment(SceneModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            Label(model.trackingState, systemImage: trackingIcon)
                .font(.footnote.weight(.semibold))

            Divider().frame(height: 14)

            Label(model.meshAvailable ? "Mesh" : "No LiDAR",
                  systemImage: model.meshAvailable ? "cube.transparent.fill" : "cube.transparent")
                .font(.footnote.weight(.medium))
                .foregroundStyle(model.meshAvailable ? Color.green : Color.secondary)

            Divider().frame(height: 14)

            Label("\(model.placedCount)", systemImage: "shippingbox.fill")
                .font(.footnote.weight(.medium))
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .liquidGlassCapsule()
        .padding(.top, 8)
    }

    private var trackingIcon: String {
        switch model.trackingState {
        case "Tracking": return "dot.radiowaves.left.and.right"
        default: return "exclamationmark.triangle"
        }
    }
}
