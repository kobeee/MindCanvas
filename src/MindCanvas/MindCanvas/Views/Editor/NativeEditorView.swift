import SwiftUI
import SwiftData
import PhotosUI

/// 原生编辑器视图 (重构后的主编辑器)
/// 集成了原生画布、工具栏和控制面板
struct NativeEditorView: View {
    let project: Project
    @State private var viewModel: NativeEditorViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var activeSheet: ActiveSheet?
    @State private var lastPresentedSheet: ActiveSheet?
    @State private var didConfirmImageToImage: Bool = false
    
    // 图片选择器
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showImageSourcePicker = false
    @State private var showCamera = false
    
    init(project: Project) {
        self.project = project
        self._viewModel = State(initialValue: NativeEditorViewModel(project: project))
    }
    
    /// 设置绘图操作的撤销支持
    private func setupDrawingUndoSupport() {
        // 等待画布视图初始化完成
        guard let canvasView = viewModel.canvasView else { return }
        
        // 监听画布更新 - 只用于保存文档，不再记录撤销操作
        let originalOnCanvasUpdated = canvasView.onCanvasUpdated
        canvasView.onCanvasUpdated = { [weak viewModel] in
            // 调用原始回调
            originalOnCanvasUpdated?()
            
            // 保存画布文档
            viewModel?.saveCanvasDocument()
        }
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
                },
                onClose: {
                    dismiss()
                }
            )
            .frame(width: 300)
            
            Divider()
            
            // 中间：原生画布
            NativeCanvasContainer(
                viewModel: viewModel,
                onImageImport: {
                    showImageSourcePicker = true
                }
            )
            
            Divider()
            
            // 右侧：控制面板
            NativeControlPanel(
                viewModel: viewModel,
                onImageToImageTapped: {
                    let ok = viewModel.prepareImageToImageFlow()
                    if ok, viewModel.getPendingImageToImagePreview() != nil {
                        didConfirmImageToImage = false
                        activeSheet = .img2imgConfirm
                    }
                },
                onTextToImageTapped: {
                    activeSheet = .txt2img
                }
            )
            .frame(width: 320)
        }
        .onAppear {
            viewModel.loadCanvasDocument()
            // 绑定清屏回调（支持撤销）
            viewModel.stateManager.onClearCanvas = { [weak viewModel] in
                guard let viewModel = viewModel, let canvasView = viewModel.canvasView else { return }
                // 记录当前状态用于撤销
                let previousLayers = canvasView.getLayers()
                let previousDrawingData = canvasView.getDrawingData()
                let action = ClearCanvasAction(
                    previousLayers: previousLayers,
                    previousDrawingData: previousDrawingData,
                    canvasView: canvasView
                )
                viewModel.stateManager.recordAction(action)
                // 执行清屏
                canvasView.clearCanvas()
            }
            // 绑定复制回调（支持撤销）
            viewModel.stateManager.onDuplicateSelected = { [weak viewModel] in
                guard let viewModel = viewModel,
                      let canvasView = viewModel.canvasView,
                      let selectedID = viewModel.stateManager.selectedNodeID,
                      let selectedLayer = canvasView.getLayers().first(where: { $0.id == selectedID })
                else { return }
                // 创建复制的图层（偏移一点位置）
                let duplicatedLayer = LayerNode(
                    id: UUID(),
                    type: selectedLayer.type,
                    url: selectedLayer.url,
                    frame: selectedLayer.frame.offsetBy(dx: 20, dy: 20),
                    rotation: selectedLayer.rotation,
                    isLocked: selectedLayer.isLocked,
                    zIndex: (canvasView.getLayers().map(\.zIndex).max() ?? 0) + 1,
                    opacity: selectedLayer.opacity,
                    createdAt: Date()
                )
                // 记录操作用于撤销
                let action = DuplicateLayerAction(
                    originalLayerID: selectedID,
                    duplicatedLayer: duplicatedLayer,
                    canvasView: canvasView
                )
                viewModel.stateManager.recordAction(action)
                // 执行复制
                canvasView.addLayer(duplicatedLayer)
                // 选中新复制的图层
                viewModel.stateManager.selectNode(duplicatedLayer.id)
            }
        }
        
        // 设置绘图操作的撤销支持
        .task {
            setupDrawingUndoSupport()
        }
        .onDisappear {
            viewModel.saveCanvasDocument()
        }
        .onChange(of: activeSheet) { _, newValue in
            if let sheet = newValue {
                lastPresentedSheet = sheet
                if sheet == .img2imgConfirm {
                    didConfirmImageToImage = false
                }
            }
        }
        // 图片选择器（只支持图片，自动过滤视频）
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        // 自定义图片来源选择浮窗
        .sheet(isPresented: $showImageSourcePicker) {
            NavigationView {
                VStack(spacing: 0) {
                    // 标题栏
                    HStack {
                        Button("取消") {
                            showImageSourcePicker = false
                        }
                        Spacer()
                        Text("选择图片来源")
                            .font(.headline)
                        Spacer()
                        Color.clear.frame(width: 60) // 平衡布局
                    }
                    .padding()
                    .background(.regularMaterial)
                    
                    // 内容区域
                    VStack(spacing: 20) {
                        Spacer()
                        
                        // 选项按钮
                        HStack(spacing: 20) {
                            // 相册按钮
                            Button {
                                showImageSourcePicker = false
                                showPhotoPicker = true
                            } label: {
                                VStack(spacing: 12) {
                                    Image(systemName: "photo.on.rectangle")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.blue)
                                        .frame(width: 80, height: 80)
                                        .background(.blue.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    
                                    Text("从相册选择")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    
                                    Text("选择已有照片")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            
                            // 拍照按钮（开发阶段强制显示，实际设备会检查相机可用性）
                            #if DEBUG
                            Button {
                                showImageSourcePicker = false
                                showCamera = true
                            } label: {
                                VStack(spacing: 12) {
                                    Image(systemName: "camera")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.green)
                                        .frame(width: 80, height: 80)
                                        .background(.green.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    
                                    Text("拍照")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    
                                    Text("使用相机拍摄")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            #else
                            if CameraImagePicker.isCameraAvailable {
                                Button {
                                    showImageSourcePicker = false
                                    showCamera = true
                                } label: {
                                    VStack(spacing: 12) {
                                        Image(systemName: "camera")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.green)
                                            .frame(width: 80, height: 80)
                                            .background(.green.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                        
                                        Text("拍照")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        
                                        Text("使用相机拍摄")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                            #endif
                        }
                        .padding(.horizontal, 40)
                        
                        Spacer()
                        
                        // 提示信息
                        Text("仅支持图片格式，视频文件将被自动过滤")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 30)
                    }
                }
                .background(Color(.systemGroupedBackground))
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await viewModel.importImage(data)
                }
            }
            selectedPhotoItem = nil
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker { imageData in
                Task {
                    await viewModel.importImage(imageData)
                }
            }
        }
        .sheet(item: $activeSheet, onDismiss: {
            if lastPresentedSheet == .img2imgConfirm, didConfirmImageToImage == false {
                viewModel.cancelImageToImageFlow()
            }
            lastPresentedSheet = nil
            didConfirmImageToImage = false
        }) { sheet in
            switch sheet {
            case .img2imgConfirm:
                if let preview = viewModel.getPendingImageToImagePreview() {
                    ImageToImageConfirmSheet(
                        previewImage: preview,
                        prompt: viewModel.prompt,
                        onConfirm: {
                            didConfirmImageToImage = true
                            activeSheet = nil
                            Task { await viewModel.confirmImageToImageGenerate() }
                        },
                        onCancel: {
                            viewModel.cancelImageToImageFlow()
                            activeSheet = nil
                        }
                    )
                } else {
                    VStack(spacing: 12) {
                        Text("预览准备失败")
                            .font(.headline)
                        if let msg = viewModel.flowHintMessage, !msg.isEmpty {
                            Text(msg)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        Button("关闭") {
                            activeSheet = nil
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 24)
                }
            case .txt2img:
                TextToImageSheet(
                    onGenerate: { prompt, ratio in
                        activeSheet = nil
                        Task { await viewModel.generateTextToImage(prompt: prompt, ratio: ratio) }
                    },
                    onCancel: {
                        activeSheet = nil
                    }
                )
            }
        }
    }
}

private enum ActiveSheet: String, Identifiable {
    case img2imgConfirm
    case txt2img

    var id: String { rawValue }
}

// MARK: - 原生画布容器

private struct NativeCanvasContainer: View {
    @Bindable var viewModel: NativeEditorViewModel
    var onImageImport: () -> Void
    
    // 箭头绘制状态
    @State private var isDrawingArrow = false
    @State private var arrowStartPoint: CGPoint?
    @State private var arrowEndPoint: CGPoint?
    
    // 矩形绘制状态
    @State private var isDrawingRectangle = false
    @State private var rectangleStartPoint: CGPoint?
    @State private var rectangleEndPoint: CGPoint?
    
    // 文字编辑状态
    @State private var isEditingText = false
    @State private var textPosition: CGPoint = .zero
    @State private var editingText: String = ""
    
    // 标注绘制状态
    @State private var isDrawingAnnotation = false
    @State private var annotationStartPoint: CGPoint?
    @State private var annotationEndPoint: CGPoint?
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.gray.opacity(0.05)
                
                // 原生画布视图
                NativeCanvasViewWrapper(
                    currentTool: $viewModel.stateManager.currentTool,
                    onCanvasUpdated: {
                        viewModel.saveCanvasDocument()
                    },
                    onViewCreated: { view in
                        viewModel.canvasView = view
                        // 设置箭头创建回调
                        view.onArrowCreated = { arrow in
                            // 这里可以添加箭头创建后的处理逻辑
                        }
                    },
                    onZoomChanged: { scale in
                        viewModel.stateManager.zoomScale = scale
                    }
                )
                
                // 箭头绘制层
                if viewModel.stateManager.currentTool == .arrow {
                    ZStack {
                        // 显示正在绘制的箭头或直线
                        if isDrawingArrow, let start = arrowStartPoint, let end = arrowEndPoint {
                            if viewModel.selectedShapeType == .line {
                                LinePreviewView(
                                    startPoint: start,
                                    endPoint: end,
                                    color: Color.fromHex(viewModel.stateManager.arrowColor) ?? .blue,
                                    lineWidth: viewModel.stateManager.arrowLineWidth
                                )
                            } else {
                                ArrowView(
                                    startPoint: start,
                                    endPoint: end,
                                    color: Color.fromHex(viewModel.stateManager.arrowColor) ?? .blue,
                                    lineWidth: viewModel.stateManager.arrowLineWidth
                                )
                            }
                        }
                        
                        // 箭头绘制手势
                        ArrowDrawingView(
                            isDrawing: $isDrawingArrow,
                            startPoint: $arrowStartPoint,
                            endPoint: $arrowEndPoint,
                            color: Color.fromHex(viewModel.stateManager.arrowColor) ?? .blue,
                            lineWidth: viewModel.stateManager.arrowLineWidth
                        ) { start, end in
                            // 将 SwiftUI 视图坐标转换为画布内容坐标
                            guard let canvasView = viewModel.canvasView else { return }

                            // 坐标转换：SwiftUI 坐标 + contentOffset = 画布内容坐标
                            let offset = canvasView.pencilCanvas.contentOffset
                            let scale = canvasView.pencilCanvas.zoomScale
                            let contentStart = CGPoint(
                                x: (start.x + offset.x) / scale,
                                y: (start.y + offset.y) / scale
                            )
                            let contentEnd = CGPoint(
                                x: (end.x + offset.x) / scale,
                                y: (end.y + offset.y) / scale
                            )

                            // 根据选择的形状类型决定是否显示箭头头部
                            let hasArrowHead = viewModel.selectedShapeType != .line
                            
                            // 创建箭头或直线图层
                            let arrow = ArrowLayerNode(
                                startPoint: contentStart,
                                endPoint: contentEnd,
                                color: viewModel.stateManager.arrowColor,
                                lineWidth: viewModel.stateManager.arrowLineWidth,
                                zIndex: canvasView.getArrowLayerManager().getNextZIndex(),
                                hasArrowHead: hasArrowHead
                            )
                            canvasView.addArrow(arrow)
                        }
                    }
                }
                
                // 形状绘制层
                if viewModel.stateManager.currentTool == .rectangle {
                    ZStack {
                        // 显示正在绘制的形状
                        if isDrawingRectangle, let start = rectangleStartPoint, let end = rectangleEndPoint {
                            let rect = CGRect(
                                x: min(start.x, end.x),
                                y: min(start.y, end.y),
                                width: abs(end.x - start.x),
                                height: abs(end.y - start.y)
                            )
                            
                            ShapeDrawingView(
                                rect: rect,
                                shapeType: viewModel.selectedShapeType,
                                color: Color.fromHex(viewModel.stateManager.shapeStrokeColor) ?? .blue,
                                lineWidth: viewModel.stateManager.shapeLineWidth,
                                isFilled: viewModel.stateManager.shapeIsFilled
                            )
                        }
                        
                        // 形状绘制手势
                        ShapeDrawingGestureView(
                            isDrawing: $isDrawingRectangle,
                            startPoint: $rectangleStartPoint,
                            endPoint: $rectangleEndPoint,
                            shapeType: viewModel.selectedShapeType,
                            color: Color.fromHex(viewModel.stateManager.shapeStrokeColor) ?? .blue,
                            lineWidth: viewModel.stateManager.shapeLineWidth,
                            isFilled: viewModel.stateManager.shapeIsFilled
                        ) { viewportRect in
                            guard let canvasView = viewModel.canvasView else { return }

                            let offset = canvasView.pencilCanvas.contentOffset
                            let scale = canvasView.pencilCanvas.zoomScale

                            let contentRect = CGRect(
                                x: (viewportRect.origin.x + offset.x) / scale,
                                y: (viewportRect.origin.y + offset.y) / scale,
                                width: viewportRect.width / scale,
                                height: viewportRect.height / scale
                            )

                            let shape = ShapeLayerNode(
                                frame: contentRect,
                                shapeType: viewModel.selectedShapeType,
                                color: viewModel.stateManager.shapeStrokeColor,
                                lineWidth: viewModel.stateManager.shapeLineWidth,
                                isFilled: viewModel.stateManager.shapeIsFilled,
                                zIndex: canvasView.getShapeLayerManager().getNextZIndex()
                            )
                            canvasView.addShape(shape)
                        }
                    }
                }
                
                // 箭头由 NativeCanvasView 中的 SelectableArrowView 渲染
                // 不再使用 SwiftUI ForEach 渲染，避免遮挡 UIKit 手势
                
                // 文字编辑层
                if viewModel.stateManager.currentTool == .text {
                    TextEditingView(
                        isEditing: $isEditingText,
                        position: $textPosition,
                        text: $editingText,
                        fontSize: viewModel.stateManager.textFontSize,
                        color: Color.fromHex(viewModel.stateManager.textColor) ?? .black
                    ) { position, text in
                        // 创建文字图层
                        let textLayer = TextLayerNode(
                            position: position,
                            text: text,
                            fontSize: viewModel.stateManager.textFontSize,
                            color: viewModel.stateManager.textColor,
                            fontName: viewModel.stateManager.textFontName,
                            zIndex: viewModel.canvasView?.getTextLayerManager().getNextZIndex() ?? 0
                        )
                        viewModel.canvasView?.addText(textLayer)
                    }
                }
                
                // 显示所有矩形
                ForEach(viewModel.canvasView?.getRectangleLayerManager().rectangles ?? []) { rectangle in
                    RectangleShapeView(
                        rect: rectangle.rect,
                        color: Color.fromHex(rectangle.color) ?? .black,
                        lineWidth: rectangle.lineWidth,
                        isFilled: rectangle.isFilled
                    )
                }
                
                // 标注绘制层
                if viewModel.stateManager.currentTool == .annotation {
                    ZStack {
                        // 显示正在绘制的标注框
                        if isDrawingAnnotation, let start = annotationStartPoint, let end = annotationEndPoint {
                            let rect = CGRect(
                                x: min(start.x, end.x),
                                y: min(start.y, end.y),
                                width: abs(end.x - start.x),
                                height: abs(end.y - start.y)
                            )
                            
                            Rectangle()
                                .stroke(Color.fromHex(viewModel.stateManager.annotationColor) ?? .blue, lineWidth: viewModel.stateManager.annotationLineWidth)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                        
                        // 标注绘制手势
                        AnnotationDrawingView(
                            isDrawing: $isDrawingAnnotation,
                            startPoint: $annotationStartPoint,
                            endPoint: $annotationEndPoint,
                            color: Color.fromHex(viewModel.stateManager.annotationColor) ?? .blue,
                            lineWidth: viewModel.stateManager.annotationLineWidth,
                            fontSize: viewModel.stateManager.annotationFontSize
                        ) { rect, text in
                            // 创建标注图层
                            let annotation = AnnotationLayerNode(
                                rect: rect,
                                text: text,
                                fontSize: viewModel.stateManager.annotationFontSize,
                                color: viewModel.stateManager.annotationColor,
                                lineWidth: viewModel.stateManager.annotationLineWidth,
                                zIndex: viewModel.canvasView?.getAnnotationLayerManager().getNextZIndex() ?? 0
                            )
                            viewModel.canvasView?.addAnnotation(annotation)
                        }
                    }
                }
                
                // 显示所有文字
                ForEach(viewModel.canvasView?.getTextLayerManager().textLayers ?? []) { textLayer in
                    TextDisplayView(textLayer: textLayer)
                }
                
                // 显示所有标注
                ForEach(viewModel.canvasView?.getAnnotationLayerManager().annotations ?? []) { annotation in
                    AnnotationView(annotation: annotation)
                }
                
                // Magic Frame 叠加层
                MagicFrameView(
                    frame: $viewModel.stateManager.magicFrame,
                    isVisible: $viewModel.stateManager.isMagicFrameVisible,
                    viewportSize: proxy.size
                )
                
                // 左上角：功能键
                VStack {
                    HStack {
                        CanvasActionBar(
                            canUndo: viewModel.stateManager.canUndo,
                            canRedo: viewModel.stateManager.canRedo,
                            hasSelection: viewModel.stateManager.hasSelection,
                            onUndo: { viewModel.stateManager.undo() },
                            onRedo: { viewModel.stateManager.redo() },
                            onDuplicate: { viewModel.stateManager.duplicateSelected() },
                            onClear: { viewModel.stateManager.clearCanvas() }
                        )
                        Spacer()
                        
                        // Magic Frame 切换按钮
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
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.lg)
                    Spacer()
                }
                
                // 左下角：缩放滑动条
                VStack {
                    Spacer()
                    HStack {
                        ZoomSlider(
                            zoomScale: $viewModel.stateManager.zoomScale,
                            onZoomChanged: { scale in
                                viewModel.canvasView?.setZoomScale(scale, animated: true)
                            }
                        )
                        Spacer()
                    }
                    .padding(.leading, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.lg + 60) // 为底部工具栏留空间
                }
                
                // 底部：工具栏
                VStack {
                    Spacer()
                    CanvasToolbar(
                        currentTool: $viewModel.stateManager.currentTool,
                        onImageImport: onImageImport,
                        onShapeSelected: { shapeType in
                            viewModel.selectedShapeType = shapeType
                        },
                        penColor: Binding(
                            get: { Color(hex: viewModel.stateManager.penColor) },
                            set: { newColor in
                                viewModel.stateManager.setPenColor(newColor.toHex() ?? "#000000")
                                // 同步更新 NativeCanvasView
                                viewModel.canvasView?.updatePenSettings(
                                    color: UIColor(newColor),
                                    width: viewModel.stateManager.penLineWidth
                                )
                            }
                        ),
                        penWidth: Binding(
                            get: { viewModel.stateManager.penLineWidth },
                            set: { newWidth in
                                viewModel.stateManager.setPenLineWidth(newWidth)
                                viewModel.canvasView?.updatePenSettings(
                                    color: UIColor(Color(hex: viewModel.stateManager.penColor)),
                                    width: newWidth
                                )
                            }
                        )
                    )
                    .padding(.bottom, Theme.Spacing.xl)
                }
            }
        }
    }
}

// MARK: - 原生控制面板

private struct NativeControlPanel: View {
    @Bindable var viewModel: NativeEditorViewModel
    let onImageToImageTapped: () -> Void
    let onTextToImageTapped: () -> Void
    
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
                onImageToImageTapped()
            } label: {
                if viewModel.isGenerating {
                    HStack {
                        ProgressView()
                            .tint(.white)
                        Text("生成中...")
                    }
                } else {
                    Label("图生图", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                viewModel.isGenerating ||
                !viewModel.stateManager.isMagicFrameVisible
            )
            .frame(maxWidth: .infinity)
            .frame(height: 50)

            Button {
                onTextToImageTapped()
            } label: {
                Label("文生图", systemImage: "paintpalette")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isGenerating)
            .frame(maxWidth: .infinity)
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
                    text: "点击图生图开始创作，或使用文生图生成独立素材"
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

                if let msg = viewModel.flowHintMessage, !msg.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
    let onClose: () -> Void
    
    @State private var showingPublishSheet = false
    @State private var publishTitle = ""
    @State private var assetToPublish: Asset?
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部导航栏
            HStack(spacing: Theme.Spacing.md) {
                // 返回按钮
                Button {
                    onClose()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundStyle(Theme.Colors.brandBlue)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                Text("资源库")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.primaryText)
                
                Spacer()
                
                // 占位符保持标题居中
                Color.clear
                    .frame(width: 60)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(.regularMaterial)
            
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
