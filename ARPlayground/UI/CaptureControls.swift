import SwiftUI

/// Photo + video capture cluster, pinned to the top-trailing corner. The photo
/// button snapshots the AR scene; the record button toggles screen recording,
/// during which the rest of the UI hides for a clean shot and a live timer shows.
struct CaptureControls: View {
    @Environment(SceneModel.self) private var model

    var body: some View {
        VStack(spacing: 12) {
            if model.isRecording {
                recordingTimer
            } else {
                photoButton
            }
            recordButton
        }
        .animation(.spring(duration: 0.3), value: model.isRecording)
    }

    private var photoButton: some View {
        Button {
            model.capturePhoto()
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .liquidGlassCapsule()
        }
        .buttonStyle(.plain)
    }

    private var recordButton: some View {
        Button {
            model.toggleRecording()
        } label: {
            ZStack {
                if model.isRecording {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.red)
                        .frame(width: 22, height: 22)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 52, height: 52)
            .liquidGlassCapsule()
        }
        .buttonStyle(.plain)
    }

    private var recordingTimer: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = Int(context.date.timeIntervalSince(model.recordingStart ?? context.date))
            let blink = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            HStack(spacing: 6) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(blink ? 1 : 0.3)
                Text(String(format: "%02d:%02d", elapsed / 60, elapsed % 60))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .liquidGlassCapsule(tint: .red)
        }
    }
}
