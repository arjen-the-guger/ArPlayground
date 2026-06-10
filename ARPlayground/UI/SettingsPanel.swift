import SwiftUI

/// Sandbox tuning: gravity, physics, realism toggles. Changes are pushed to the
/// live AR session via `applySettings()`.
struct SettingsPanel: View {
    @Environment(SceneModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section("Physics") {
                    Toggle("Objects fall & collide", isOn: $model.physicsEnabled)

                    VStack(alignment: .leading) {
                        Text("Gravity  \(model.gravity, specifier: "%.1f") m/s²")
                            .font(.footnote).foregroundStyle(.secondary)
                        Slider(value: $model.gravity, in: 0...20, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text("Bounciness  \(model.restitution, specifier: "%.2f")")
                            .font(.footnote).foregroundStyle(.secondary)
                        Slider(value: $model.restitution, in: 0...1, step: 0.01)
                    }
                }

                Section("Placement") {
                    VStack(alignment: .leading) {
                        Text("Imported size  \(Int(model.modelScale * 100)) cm")
                            .font(.footnote).foregroundStyle(.secondary)
                        Slider(value: $model.modelScale, in: 0.05...1.0, step: 0.01)
                        Text("All models are auto-scaled so their longest edge matches this.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                Section("Realism") {
                    Toggle("Realistic lighting (IBL)", isOn: $model.realisticLighting)
                    Toggle("Environment reflections", isOn: $model.reflections)
                    Toggle("Grounding shadows", isOn: $model.groundingShadows)
                    Toggle("People occlusion", isOn: $model.peopleOcclusion)
                }

                Section {
                    Text("Tip: with LiDAR devices the scanned room mesh becomes a real collider — objects land on actual tables and floors, gas drifts around them, and fluid pools on real surfaces.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sandbox Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: model.gravity) { model.applySettings() }
            .onChange(of: model.realisticLighting) { model.applySettings() }
            .onChange(of: model.reflections) { model.applySettings() }
            .onChange(of: model.peopleOcclusion) { model.applySettings() }
        }
    }
}
