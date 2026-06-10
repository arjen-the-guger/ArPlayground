import SwiftUI

/// The bottom control surface: a model/material tray (shown for the Place tool)
/// above the main tool dock. All built from Liquid Glass.
struct ControlDeck: View {
    @Environment(SceneModel.self) private var model
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 12) {
            if model.tool == .place {
                ModelTray(showImporter: $showImporter)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            toolDock
        }
        .animation(.spring(duration: 0.32), value: model.tool)
    }

    private var toolDock: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(PlaygroundTool.allCases) { tool in
                    DeckButton(systemImage: tool.systemImage,
                               title: tool.title,
                               isActive: model.tool == tool) {
                        model.tool = tool
                    }
                }

                Divider().frame(height: 28).overlay(.white.opacity(0.12))

                DeckButton(systemImage: "trash", title: "Clear", isActive: false) {
                    model.clearScene()
                }
                DeckButton(systemImage: "slider.horizontal.3", title: "Tune", isActive: model.showSettings) {
                    model.showSettings = true
                }
            }
            .padding(8)
        }
        .liquidGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// A square tappable tool button with icon + caption.
struct DeckButton: View {
    let systemImage: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .frame(width: 52, height: 46)
            .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.arAccent.opacity(0.9))
            }
        }
        .liquidGlass(RoundedRectangle(cornerRadius: 16, style: .continuous),
                     tint: isActive ? .arAccent : nil,
                     interactive: true)
    }
}

/// Horizontal palette of built-in primitives + material picker + import.
struct ModelTray: View {
    @Environment(SceneModel.self) private var model
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ModelKind.allCases) { kind in
                        TrayChip(systemImage: kind.systemImage,
                                 title: kind.title,
                                 isActive: model.selectedModel == kind) {
                            model.selectedModel = kind
                            if kind == .imported { showImporter = true }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SurfaceMaterial.allCases) { mat in
                        TrayChip(systemImage: "paintpalette",
                                 title: mat.title,
                                 isActive: model.material == mat) {
                            model.material = mat
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(10)
        .liquidGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct TrayChip: View {
    let systemImage: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .foregroundStyle(isActive ? .white : .primary)
        }
        .buttonStyle(.plain)
        .background {
            if isActive {
                Capsule().fill(Color.arAccent.opacity(0.9))
            }
        }
        .liquidGlassCapsule(tint: isActive ? .arAccent : nil, interactive: true)
    }
}
