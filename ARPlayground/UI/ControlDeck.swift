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
            toolHint
            toolDock
        }
        .animation(.spring(duration: 0.32), value: model.tool)
    }

    /// A small coaching pill describing the active tool. For surface tools it
    /// also shows a live dot that turns green once the reticle locks on.
    private var toolHint: some View {
        HStack(spacing: 7) {
            if model.tool.usesSurface {
                Circle()
                    .fill(model.surfaceDetected ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: (model.surfaceDetected ? Color.green : Color.orange).opacity(0.6),
                            radius: 3)
            }
            Text(model.tool.instruction)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 13).padding(.vertical, 7)
        .liquidGlassCapsule()
        .animation(.easeInOut(duration: 0.2), value: model.surfaceDetected)
        .transition(.opacity)
    }

    private var toolDock: some View {
        // The tools scroll horizontally so the dock fits any iPhone no matter
        // how many tools there are; Clear and Tune stay pinned on the right.
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(PlaygroundTool.allCases) { tool in
                            DeckButton(systemImage: tool.systemImage,
                                       title: tool.title,
                                       isActive: model.tool == tool) {
                                model.tool = tool
                            }
                            .id(tool)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .onChange(of: model.tool) {
                    withAnimation(.spring(duration: 0.3)) {
                        proxy.scrollTo(model.tool, anchor: .center)
                    }
                }
            }

            Divider().frame(height: 30).overlay(.white.opacity(0.12))

            DeckButton(systemImage: "trash", title: "Clear", isActive: false) {
                model.clearScene()
            }
            DeckButton(systemImage: "slider.horizontal.3", title: "Tune", isActive: model.showSettings) {
                model.showSettings = true
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .liquidGlass(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// A tappable tool button with icon + caption that shares the dock's width
/// equally with its siblings.
struct DeckButton: View {
    let systemImage: String
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 58, height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.arAccent.opacity(0.9))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isActive)
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
        .frame(maxWidth: .infinity)
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
