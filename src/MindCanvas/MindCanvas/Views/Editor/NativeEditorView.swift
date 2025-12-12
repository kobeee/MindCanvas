import SwiftUI
import SwiftData

/// 原生编辑器视图 (重构后的主编辑器)
/// 集成了原生画布、工具栏和控制面板
struct NativeEditorView: View {
    let project: Project
    @State private var viewModel: NativeEditorViewModel
    @Environment(\.columnVisibilityBinding) private var columnVisibility
    
    init(project: Project) {
        self.project = project
        self._viewModel = State(initialValue: NativeEditorViewModel(project: project))
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // 左侧：资源库
            NativeAssetLibraryView(
                assets: viewModel.assets,
                selectedAsset: $viewModel.selectedAsset,
                onImport: { imageData in
                    Task {
                        await viewModel.importImage(imageData)
                    }
                },
                onAddToCanvas: { asset in
                    viewModel.addAssetToCanvas(asset)
                },
                onDelete: { asset in
                    viewModel.deleteAsset(asset)
                },
                onDownload: { asset in
                    viewModel.downloadAsset(asset)
                },
                onPublish: { asset, title in
                    Task {
                        await viewModel.publishAsset(asset, title: title)
                    }
                }
            )
            .frame(width: 300)
            
            Divider()
            
            // 中间：原生画布
            NativeCanvasContainer(viewModel: viewModel)
            
            Divider()
            
            // 右侧：控制面板
            NativeControlPanel(viewModel: viewModel)
                .frame(width: 320)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TextField("项目名称", text: $viewModel.projectName)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .onAppear {
            columnVisibility?.wrappedValue = .detailOnly
            viewModel.loadCanvasDocument()
        }
        .onDisappear {
            columnVisibility?.wrappedValue = .all
            viewModel.saveCanvasDocument()
        }
    }
}

// MARK: - 原生画布容器

private struct NativeCanvasContainer: View {
    @Bindable var viewModel: NativeEditorViewModel

    @State private var zoomText: String = "100"
    @State private var isEditingZoom: Bool = false
    
    var body: some View {
        GeometryReader { proxy in
        ZStack {
            Color.gray.opacity(0.05)
            
            // 原生画布视图
            NativeCanvasViewWrapper(
                toolMode: $viewModel.stateManager.currentMode,
                onCanvasUpdated: {
                    viewModel.saveCanvasDocument()
                },
                onViewCreated: { view in
                    // 绑定画布视图引用
                    viewModel.canvasView = view
                    // 初始化绘图工具
                    view.setDrawingTool(isPen: viewModel.stateManager.isUsingPen)
                },
                onZoomChanged: { scale in
                    viewModel.stateManager.zoomScale = scale
                }
            )
            
            // Magic Frame 叠加层
            MagicFrameView(
                frame: $viewModel.stateManager.magicFrame,
                isVisible: $viewModel.stateManager.isMagicFrameVisible,
                viewportSize: proxy.size
            )
            
            // 左下角缩放 HUD
            VStack {
                Spacer()
                HStack {
                    zoomHUD
                    Spacer()
                }
                .padding(.leading, 16)
                .padding(.bottom, 16)
            }

            // 顶部工具栏
            VStack {
                canvasToolbar
                Spacer()
            }
        }}
        .onChange(of: viewModel.stateManager.isUsingPen) { _, newValue in
            viewModel.canvasView?.setDrawingTool(isPen: newValue)
        }
        .onChange(of: viewModel.stateManager.zoomScale) { _, newValue in
            // 避免正在编辑时被实时缩放刷新打断
            guard !isEditingZoom else { return }
            zoomText = "\(Int((newValue * 100).rounded()))"
        }
    }

    private var zoomHUD: some View {
        HStack(spacing: 8) {
            Button {
                let next = viewModel.stateManager.zoomScale - 0.1
                viewModel.canvasView?.setZoomScale(next, animated: true)
            } label: {
                Image(systemName: "minus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)

            TextField("", text: $zoomText)
                .frame(width: 72)
                .multilineTextAlignment(.center)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)
                .onTapGesture {
                    isEditingZoom = true
                }
                .onSubmit {
                    applyZoomText()
                }
                .onChange(of: zoomText) { _, _ in
                    // 仅标记编辑状态即可，避免被 onChange(zoomScale) 覆盖
                    isEditingZoom = true
                }

            Text("%")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                let next = viewModel.stateManager.zoomScale + 0.1
                viewModel.canvasView?.setZoomScale(next, animated: true)
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func applyZoomText() {
        defer { isEditingZoom = false }
        let trimmed = zoomText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(trimmed) else { return }
        let scale = percent / 100.0
        viewModel.canvasView?.setZoomScale(scale, animated: true)
    }
    
    private var canvasToolbar: some View {
        HStack(spacing: 12) {
            // 工具模式切换
            Picker("工具模式", selection: $viewModel.stateManager.currentMode) {
                ForEach(CanvasToolMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.iconName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            
            Divider()
                .frame(height: 20)
            
            // 绘图工具切换 (仅在绘图模式下显示)
            if viewModel.stateManager.currentMode == .drawingMode {
                Button {
                    viewModel.stateManager.selectPen()
                } label: {
                    Image(systemName: "pencil.tip")
                        .foregroundColor(viewModel.stateManager.isUsingPen ? .blue : .secondary)
                }
                .buttonStyle(.bordered)
                
                Button {
                    viewModel.stateManager.selectEraser()
                } label: {
                    Image(systemName: "eraser.fill")
                        .foregroundColor(!viewModel.stateManager.isUsingPen ? .blue : .secondary)
                }
                .buttonStyle(.bordered)
            }
            
            // 图层操作 (仅在对象模式且有选中时显示)
            if viewModel.stateManager.currentMode == .objectMode,
               viewModel.stateManager.hasSelection {
                
                Divider()
                    .frame(height: 20)
                
                Button {
                    viewModel.bringSelectedLayerToFront()
                } label: {
                    Image(systemName: "square.3.layers.3d.top.filled")
                }
                .buttonStyle(.bordered)
                .help("置顶")
                
                Button {
                    viewModel.sendSelectedLayerToBack()
                } label: {
                    Image(systemName: "square.3.layers.3d.bottom.filled")
                }
                .buttonStyle(.bordered)
                .help("置底")
                
                Button {
                    viewModel.toggleSelectedLayerLock()
                } label: {
                    Image(systemName: "lock.fill")
                }
                .buttonStyle(.bordered)
                .help("锁定/解锁")
                
                Button(role: .destructive) {
                    viewModel.deleteSelectedLayer()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .help("删除")
            }
            
            Spacer()
            
            // Magic Frame 切换
            Button {
                viewModel.stateManager.toggleMagicFrame()
            } label: {
                Label(
                    viewModel.stateManager.isMagicFrameVisible ? "隐藏选框" : "显示选框",
                    systemImage: "viewfinder"
                )
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding()
    }
}

// MARK: - 原生控制面板

private struct NativeControlPanel: View {
    @Bindable var viewModel: NativeEditorViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // API 配置
                configSection
                
                Divider()
                
                // 模型选择
                modelSection
                
                Divider()
                
                // Prompt 输入
                promptSection
                
                Divider()
                
                // 生成按钮
                generateSection
                
                Divider()
                
                // 提示信息
                infoSection
            }
            .padding()
        }
    }
    
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("API 配置", systemImage: "server.rack")
                .font(.headline)
            
            HStack {
                Text("服务")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("官方服务")
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("生成模型", systemImage: "sparkles")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nano Banana Pro")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("v1.0 (Gemini 3 Pro Image)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
    }
    
    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("生成描述", systemImage: "text.bubble")
                .font(.headline)
            
            TextEditor(text: $viewModel.prompt)
                .frame(height: 120)
                .padding(8)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    private var generateSection: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    await viewModel.generate()
                }
            } label: {
                if viewModel.isGenerating {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("生成中...")
                    }
                } else {
                    Label("生成图片", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.prompt.isEmpty || 
                     viewModel.isGenerating || 
                     !viewModel.stateManager.isMagicFrameVisible)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("使用提示", systemImage: "info.circle")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                infoRow(
                    icon: "viewfinder",
                    text: "显示选框并框选要生成的区域"
                )
                
                infoRow(
                    icon: "text.bubble",
                    text: "输入描述你想要生成的内容"
                )
                
                infoRow(
                    icon: "wand.and.stars",
                    text: "点击生成按钮开始创作"
                )
                
                if !viewModel.stateManager.isMagicFrameVisible {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("请先显示选框")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 简化的资源库视图

private struct NativeAssetLibraryView: View {
    let assets: [Asset]
    @Binding var selectedAsset: Asset?
    let onImport: (Data) -> Void
    let onAddToCanvas: (Asset) -> Void
    let onDelete: (Asset) -> Void
    let onDownload: (Asset) -> Void
    let onPublish: (Asset, String) -> Void
    
    @State private var showingPublishSheet = false
    @State private var publishTitle = ""
    @State private var assetToPublish: Asset?
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部工具栏
            HStack {
                Text("资源库")
                    .font(.headline)
                Spacer()
                Button {
                    // TODO: 打开图片选择器
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
            }
            .padding()
            
            Divider()
            
            // 资源列表
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(assets) { asset in
                        NativeAssetCardView(
                            asset: asset,
                            isSelected: selectedAsset?.id == asset.id,
                            onTap: {
                                selectedAsset = asset
                            },
                            onAddToCanvas: {
                                onAddToCanvas(asset)
                            },
                            onDelete: {
                                onDelete(asset)
                            },
                            onDownload: {
                                onDownload(asset)
                            },
                            onPublish: {
                                assetToPublish = asset
                                showingPublishSheet = true
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $showingPublishSheet) {
            if let asset = assetToPublish {
                NativePublishSheetView(
                    asset: asset,
                    title: $publishTitle,
                    onPublish: {
                        onPublish(asset, publishTitle)
                        showingPublishSheet = false
                        publishTitle = ""
                    },
                    onCancel: {
                        showingPublishSheet = false
                        publishTitle = ""
                    }
                )
            }
        }
    }
}

// MARK: - 资源卡片视图 (简化版)

private struct NativeAssetCardView: View {
    let asset: Asset
    let isSelected: Bool
    let onTap: () -> Void
    let onAddToCanvas: () -> Void
    let onDelete: () -> Void
    let onDownload: () -> Void
    let onPublish: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            // 图片预览
            AsyncImage(url: URL(string: asset.url)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                if asset.isLoading {
                    ProgressView()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
            )
            .onTapGesture(perform: onTap)
            
            // 操作按钮
            if isSelected && !asset.isLoading {
                HStack(spacing: 8) {
                    Button {
                        onAddToCanvas()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    
                    if asset.type == .generated {
                        Button {
                            onDownload()
                        } label: {
                            Image(systemName: "arrow.down.circle")
                        }
                        
                        Button {
                            onPublish()
                        } label: {
                            Image(systemName: "globe")
                        }
                    }
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .font(.title3)
                .padding(.vertical, 8)
            }
        }
        .padding(8)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5)
    }
}

// MARK: - 发布弹窗 (简化版)

private struct NativePublishSheetView: View {
    let asset: Asset
    @Binding var title: String
    let onPublish: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                AsyncImage(url: URL(string: asset.url)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(height: 200)
                .cornerRadius(12)
                
                TextField("添加标题", text: $title)
                    .textFieldStyle(.roundedBorder)
                
                Spacer()
            }
            .padding()
            .navigationTitle("发布到 MindStream")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发布", action: onPublish)
                        .disabled(title.isEmpty)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var project = Project(name: "示例项目")
    
    NavigationStack {
        NativeEditorView(project: project)
    }
    .modelContainer(for: [Project.self, Asset.self])
}
