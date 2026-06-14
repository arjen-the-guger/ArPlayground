import SwiftUI

/// The bottom control surface: a context tray (model palette for Place, tuning
/// for Link, colour/material for Paint/Spray) above the main tool dock. All
/// built from Liquid Glass.
struct ControlDeck: View {
    @Environment(SceneModel.self) private var model
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 12) {
            contextTray
            toolHint
            toolDock
        }
        .animation(.spring(duration: 0.32), value: model.tool)
    }

    /// The tray that changes with the active tool.
    @ViewBuilder
    private var contextTray: some View {
        switch model.tool {
        case .place:
            ModelTray(showImporter: $showImporter)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        case .link:
            LinkTray()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        case .paint, .spray:
            PaintTray()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        default:
            EmptyView()
        }
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

/// The Place palette: a category tab row, the models in that category (or the
/// uploaded-file list), and — for built-in models — a material picker.
struct ModelTray: View {
    @Environment(SceneModel.self) private var model
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 8) {
            categoryRow
            modelRow
            if showsMaterials { materialRow }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .liquidGlass(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.spring(duration: 0.28), value: model.selectedCategory)
    }

    private var showsMaterials: Bool {
        model.selectedCategory == .primitives || model.selectedCategory == .mechanical
    }

    private var categoryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ModelCategory.allCases) { category in
                    TrayChip(systemImage: category.systemImage,
                             title: category.title,
                             isActive: model.selectedCategory == category) {
                        model.selectedCategory = category
                        if category != .upload, let first = category.models.first {
                            model.selectedModel = first
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var modelRow: some View {
        if model.selectedCategory == .upload {
            uploadRow
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.selectedCategory.models) { kind in
                        TrayChip(systemImage: kind.systemImage,
                                 title: kind.title,
                                 isActive: model.selectedModel == kind) {
                            model.selectedModel = kind
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var uploadRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TrayChip(systemImage: "plus", title: "Add file", isActive: false) {
                    showImporter = true
                }
                if model.uploads.isEmpty {
                    Text("No uploads yet — add a .usdz / .usd file")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                } else {
                    ForEach(model.uploads) { upload in
                        TrayChip(systemImage: "shippingbox.fill",
                                 title: upload.name,
                                 isActive: model.selectedUploadID == upload.id) {
                            model.selectedCategory = .upload
                            model.selectedUploadID = upload.id
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                model.removeUpload(upload)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var materialRow: some View {
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
}

/// Tuning for the Link tool: elasticity + rest distance (with an auto option).
struct LinkTray: View {
    @Environment(SceneModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Rigid").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $model.linkElasticity, in: 0...1)
                Text("Elastic").font(.caption2).foregroundStyle(.secondary)
            }

            Toggle(isOn: $model.linkDistanceAuto) {
                Text("Auto distance (keep current gap)")
                    .font(.caption.weight(.medium))
            }
            .tint(.arAccent)

            if !model.linkDistanceAuto {
                HStack(spacing: 8) {
                    Text(model.linkDistance < 0.005
                         ? "Join (0)"
                         : String(format: "%.0f cm", model.linkDistance * 100))
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    Slider(value: $model.linkDistance, in: 0...1)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .liquidGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: model.linkDistanceAuto)
    }
}

/// Colour (and, for Paint, material) for the Paint / Spray tools.
struct PaintTray: View {
    @Environment(SceneModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 8) {
            ColorPicker(selection: $model.paintColor, supportsOpacity: false) {
                Text("Paint colour").font(.footnote.weight(.medium))
            }

            if model.tool == .paint {
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
            } else {
                Text("Spray sticks to flat surfaces — closer is sharper, farther is blurrier.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .liquidGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                .lineLimit(1)
                .truncationMode(.middle)
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
