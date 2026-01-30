import SwiftUI
import SwiftData
import PhotosUI

/// 原生编辑器视图 (重构后的主编辑器)
/// 集成了原生画布、工具栏和控制面板
struct NativeEditorView: View {
    let project: Project
    @State private var viewModel: NativeEditorViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    
    @State private var activeSheet: ActiveSheet?
    @State private var lastPresentedSheet: ActiveSheet?
    @State private var didConfirmImageToImage: Bool = false
    
    // 图片选择器
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showImageSourcePicker = false
    @State private var showCamera = false
    @State private var pendingCanvasImageLocation: CGPoint?
    
    // 标题编辑状态
    @State private var isEditingTitle = false
    @FocusState private var isTitleFocused: Bool
    
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
        VStack(spacing: 0) {
            // 顶部：标题栏
            EditorTitleBar(
                projectName: $viewModel.projectName,
                isEditingTitle: $isEditingTitle,
                isTitleFocused: _isTitleFocused,
                onSave: {
                    viewModel.saveProjectName()
                }
            )
            
            Divider()
            
            // 主内容区
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
                        // 图片导入时取消选中状态
                        viewModel.stateManager.clearSelection()
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
        }
        .onAppear {
            // 设置 modelContext
            viewModel.setModelContext(modelContext)

            // 调试：列出所有图片文件
            ImageStorageService.shared.listAllFiles()

            // 修复：绑定状态同步，确保NativeCanvasView的选中状态同步到CanvasStateManager
            // 注意：canvasView 可能在 onAppear 时还没准备好，加载文档移到 onViewCreated 中
            if let canvasView = viewModel.canvasView {
                canvasView.onSelectionIdChanged = { [weak viewModel] selectedID in
                    viewModel?.stateManager.selectedNodeID = selectedID
                }

                // 绑定图片选择器请求回调
                canvasView.onShowImagePickerRequested = { [self] location in
                    pendingCanvasImageLocation = location
                    showImageSourcePicker = true
                }

                // canvasView 已准备好，加载文档
                viewModel.loadCanvasDocument()
            }
            
            // 启动配额定时刷新
            viewModel.startQuotaRefreshTimer()
            
            // 绑定清屏回调（支持撤销）
            viewModel.stateManager.onClearCanvas = { [weak viewModel] in
                guard let viewModel = viewModel, let canvasView = viewModel.canvasView else { return }
                
                // 记录当前所有对象状态用于撤销
                let previousLayers = canvasView.getLayers()
                let previousArrows = canvasView.getArrows()
                let previousShapes = canvasView.getShapes()
                let previousRectangles = canvasView.getRectangles()
                let previousTexts = canvasView.getTexts()
                let previousAnnotations = canvasView.getAnnotations()
                let previousDrawingData = canvasView.getDrawingData()
                
                let action = ClearCanvasAction(
                    previousLayers: previousLayers,
                    previousArrows: previousArrows,
                    previousShapes: previousShapes,
                    previousRectangles: previousRectangles,
                    previousTexts: previousTexts,
                    previousAnnotations: previousAnnotations,
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
            
            // 修复：绑定删除选中节点回调（增强错误处理）
            viewModel.stateManager.onDeleteSelected = { [weak viewModel] in
                guard let viewModel = viewModel,
                      let canvasView = viewModel.canvasView,
                      let selectedID = viewModel.stateManager.selectedNodeID
                else {
                    return
                }
                
                var deletionSuccess = false
                
                // 尝试删除不同类型的对象
                // 1. 尝试作为图片图层删除
                if let layer = canvasView.getLayers().first(where: { $0.id == selectedID }) {
                    let action = RemoveLayerAction(layer: layer, canvasView: canvasView)
                    viewModel.stateManager.recordAction(action)
                    canvasView.removeLayer(id: selectedID, recordUndo: false)
                    deletionSuccess = true
                    
                }
                // 2. 尝试作为箭头删除
                else if let arrow = canvasView.getArrowLayerManager().arrows.first(where: { $0.id == selectedID }) {
                    let action = RemoveArrowAction(arrow: arrow, canvasView: canvasView)
                    viewModel.stateManager.recordAction(action)
                    canvasView.removeArrow(id: selectedID)
                    deletionSuccess = true
                    
                }
                // 3. 尝试作为形状删除
                else if let shape = canvasView.getShapeLayerManager().shapes.first(where: { $0.id == selectedID }) {
                    let action = RemoveShapeAction(shape: shape, canvasView: canvasView)
                    viewModel.stateManager.recordAction(action)
                    canvasView.removeShape(id: selectedID)
                    deletionSuccess = true
                }
                // 4. 尝试作为文字删除
                else if let text = canvasView.getTextLayerManager().texts.first(where: { $0.id == selectedID }) {
                    let action = RemoveTextAction(text: text, canvasView: canvasView)
                    viewModel.stateManager.recordAction(action)
                    canvasView.removeText(id: selectedID)
                    deletionSuccess = true
                }
                
                if !deletionSuccess {
                    // Deletion failed
                }
                
                // 清除选中状态
                viewModel.stateManager.clearSelection()
            }
        }
        
        // 设置绘图操作的撤销支持
        .task {
            setupDrawingUndoSupport()
        }
        .onDisappear {
            // 停止配额定时刷新
            viewModel.stopQuotaRefreshTimer()
            
            // 保存画布文档
            viewModel.saveCanvasDocument()
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task {
                    await viewModel.loadQuota()
                }
            }
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
        .onChange(of: showImageSourcePicker) { _, newValue in
            if !newValue {
                // 图片选择器关闭时,重置状态
                viewModel.canvasView?.resetImagePickerState()
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                defer {
                    selectedPhotoItem = nil
                    pendingCanvasImageLocation = nil
                }
                if let data = try? await item.loadTransferable(type: Data.self) {
                    if let location = pendingCanvasImageLocation, let canvasView = viewModel.canvasView {
                        await MainActor.run {
                            canvasView.importImage(data, at: location)
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker { imageData in
                // 拍照成功后,将图片直接添加到画布,而不是导入到资源栏
                if let location = pendingCanvasImageLocation, let canvasView = viewModel.canvasView {
                    canvasView.importImage(imageData, at: location)
                }
            }
        }
        // 下载成功 Toast 提示
        .overlay(alignment: .bottom) {
            if viewModel.showDownloadSuccessToast {
                ToastView(message: "已保存至相册", icon: "checkmark.circle.fill")
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        // 2秒后自动隐藏
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                viewModel.showDownloadSuccessToast = false
                            }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showDownloadSuccessToast)
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
    
    // 文字工具状态监听
    @State private var previousTool: CanvasTool = .select
    
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
                    onCanvasUpdated: {
                        viewModel.saveCanvasDocument()
                    },
                    onViewCreated: { view in
                        viewModel.canvasView = view
                        // 修复：绑定状态同步，确保选中状态正确同步
                        view.onSelectionIdChanged = { [weak viewModel] selectedID in
                            viewModel?.stateManager.selectedNodeID = selectedID
                        }
                        // 设置箭头创建回调
                        view.onArrowCreated = { arrow in
                            // 这里可以添加箭头创建后的处理逻辑
                        }
                        // 绑定图片选择器请求回调
                        view.onShowImagePickerRequested = { location in
                            // 这里通过 onImageImport 触发
                        }
                        // canvasView 准备好后，加载文档
                        viewModel.loadCanvasDocument()
                    },
                    onZoomChanged: { scale in
                        viewModel.stateManager.zoomScale = scale
                    },
                    stateManager: viewModel.stateManager,
                    assets: viewModel.assets
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
                            
                            // 创建箭头或直线图层（使用全局 zIndex 确保正确的层级顺序）
                            let arrow = ArrowLayerNode(
                                startPoint: contentStart,
                                endPoint: contentEnd,
                                color: viewModel.stateManager.arrowColor,
                                lineWidth: viewModel.stateManager.arrowLineWidth,
                                zIndex: canvasView.getNextGlobalZIndex(),
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

                            // 修复：圆形创建时强制正方形，避免后续约束问题
                            var finalFrame = contentRect
                            if viewModel.selectedShapeType == .circle {
                                let size = min(contentRect.width, contentRect.height)
                                finalFrame = CGRect(
                                    x: contentRect.midX - size / 2,
                                    y: contentRect.midY - size / 2,
                                    width: size,
                                    height: size
                                )
                            }
                            
                            // 使用全局 zIndex 确保正确的层级顺序
                            let shape = ShapeLayerNode(
                                frame: finalFrame,
                                shapeType: viewModel.selectedShapeType,
                                color: viewModel.stateManager.shapeStrokeColor,
                                lineWidth: viewModel.stateManager.shapeLineWidth,
                                isFilled: viewModel.stateManager.shapeIsFilled,
                                zIndex: canvasView.getNextGlobalZIndex()
                            )
                            canvasView.addShape(shape)
                        }
                    }
                }
                
                // 箭头由 NativeCanvasView 中的 SelectableArrowView 渲染
                // 不再使用 SwiftUI ForEach 渲染，避免遮挡 UIKit 手势
                
                
                
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
                            // 创建标注图层（使用全局 zIndex 确保正确的层级顺序）
                            let annotation = AnnotationLayerNode(
                                rect: rect,
                                text: text,
                                fontSize: viewModel.stateManager.annotationFontSize,
                                color: viewModel.stateManager.annotationColor,
                                lineWidth: viewModel.stateManager.annotationLineWidth,
                                zIndex: viewModel.canvasView?.getNextGlobalZIndex() ?? 0
                            )
                            viewModel.canvasView?.addAnnotation(annotation)
                        }
                    }
                }
                
                // 显示所有文字
                ForEach(viewModel.canvasView?.getTextLayerManager().texts ?? []) { textLayer in
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
                            onClear: { viewModel.stateManager.clearCanvas() },
                            onDeleteSelected: { viewModel.stateManager.deleteSelectedNode() }
                        )
                        Spacer()
                        
                        // Magic Frame 切换按钮
                        Button {
                            // 点击"显示选框"时取消选中状态
                            viewModel.stateManager.clearSelection()
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
                        stateManager: viewModel.stateManager,
                        onImageImport: onImageImport,
                        onShapeSelected: { shapeType in
                            viewModel.selectedShapeType = shapeType
                        },
                        onToolChanged: { newTool in
                            // 验证状态同步
                            if viewModel.stateManager.currentTool != newTool {
                                // 强制同步状态
                                viewModel.stateManager.selectTool(newTool)
                            }
                            
                            // 工具切换时取消选中状态
                            viewModel.stateManager.clearSelection()
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

    @FocusState private var isPromptFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
                .focused($isPromptFocused)
                .frame(minHeight: 120, maxHeight: 200)
                .padding(8)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isPromptFocused ? Color.blue : Color.gray.opacity(0.2),
                            lineWidth: isPromptFocused ? 2 : 1
                        )
                )
                .scrollContentBackground(.hidden)
        }
    }
    
    private var generateSection: some View {
        VStack(spacing: 12) {
            // 配额提示或 API Key 提示
            if let hint = viewModel.getGenerationHint() {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.quotaInfo?.hasFreeQuota == true ? "gift.fill" : "key.fill")
                        .foregroundStyle(Theme.Colors.brandBlue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hint)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Theme.Colors.brandBlue.opacity(0.1))
                .cornerRadius(8)
            }

            Button {
                // 先收起键盘
                isPromptFocused = false

                // 延迟执行，等待键盘动画完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onImageToImageTapped()
                }
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
                !viewModel.stateManager.isMagicFrameVisible ||
                !viewModel.checkCanGenerate()
            )
            .frame(maxWidth: .infinity)
            .frame(height: 50)

            Button {
                onTextToImageTapped()
            } label: {
                Label("文生图", systemImage: "paintpalette")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isGenerating || !viewModel.checkCanGenerate())
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
    @State private var showingDeleteConfirmation = false
    @State private var assetToDelete: Asset?
    
    var body: some View {
        VStack(spacing: 0) {
            // 精致的头部导航栏
            HStack(spacing: Theme.Spacing.lg) {
                // 返回按钮 - 轻量级设计，有微妙背景
                Button {
                    onClose()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("返回")
                            .font(.system(size: 15, weight: .regular))
                    }
                    .foregroundStyle(Theme.Colors.brandBlue)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Theme.Colors.brandBlue.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // 标题 - 突出但不侵入
                Text("资源库")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.primaryText)
                
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(.ultraThinMaterial)
            
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
                                assetToDelete = asset
                                showingDeleteConfirmation = true
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
        .alert("删除确认", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {
                assetToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let asset = assetToDelete {
                    onDelete(asset)
                    if selectedAsset?.id == asset.id {
                        selectedAsset = nil
                    }
                }
                assetToDelete = nil
            }
        } message: {
            Text("确定要删除这张图片吗？此操作不可恢复。")
        }
    }
}

// MARK: - 资源加载视图 (四角星呼吸效果)

private struct AssetLoadingView: View {
    @State private var shimmerOffset: CGFloat = -1.0
    @State private var breatheScale: CGFloat = 1.0
    @State private var breatheOpacity: Double = 0.5

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 纯净的浅灰背景
                Color(white: 0.97)

                // 微妙的shimmer光带 (骨架屏风格)
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.8),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geometry.size.width * 0.4)
                .offset(x: shimmerOffset * geometry.size.width)
                .blur(radius: 20)

                // 中心内容
                VStack(spacing: 14) {
                    // 四角星星组合
                    ZStack {
                        // 周围小星星 (固定位置，跟随呼吸)
                        Image(systemName: "sparkle")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Theme.Colors.brandBlue.opacity(0.4))
                            .offset(x: -22, y: -14)
                            .scaleEffect(breatheScale * 0.9)
                            .opacity(breatheOpacity + 0.2)

                        Image(systemName: "sparkle")
                            .font(.system(size: 6, weight: .medium))
                            .foregroundStyle(Theme.Colors.brandBlue.opacity(0.35))
                            .offset(x: 20, y: -18)
                            .scaleEffect(breatheScale * 0.85)
                            .opacity(breatheOpacity + 0.15)

                        Image(systemName: "sparkle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.Colors.brandBlue.opacity(0.45))
                            .offset(x: 24, y: 10)
                            .scaleEffect(breatheScale * 0.95)
                            .opacity(breatheOpacity + 0.25)

                        Image(systemName: "sparkle")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(Theme.Colors.brandBlue.opacity(0.3))
                            .offset(x: -18, y: 16)
                            .scaleEffect(breatheScale * 0.8)
                            .opacity(breatheOpacity + 0.1)

                        // 中心大星星
                        Image(systemName: "sparkle")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Theme.Colors.brandBlue.opacity(0.6))
                            .scaleEffect(breatheScale)
                            .opacity(breatheOpacity + 0.3)
                    }

                    // 简洁的文字
                    Text("生成中")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(white: 0.5))
                        .tracking(0.5)
                }
            }
        }
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            // Shimmer 流动 (缓慢、优雅)
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 1.0
            }

            // 星星呼吸动画
            withAnimation(
                .easeInOut(duration: 1.6)
                .repeatForever(autoreverses: true)
            ) {
                breatheScale = 1.15
                breatheOpacity = 0.8
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
            CachedAsyncImage(urlString: asset.url, localPath: asset.localPath, contentMode: .fill)
                .frame(height: 150)
                .clipped()  // 关键修复：裁剪触控区域
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )
                .overlay {
                    if asset.isLoading {
                        AssetLoadingView()
                    }
                }
                .onTapGesture(perform: onTap)
            
            // 操作按钮
            if isSelected && !asset.isLoading {
                HStack(spacing: 12) {
                    Button {
                        onAddToCanvas()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.Colors.brandBlue)
                    }
                    .frame(width: 60, height: 60)  // 增大触控范围
                    .contentShape(Rectangle())  // 确保整个区域都可点击
                    .zIndex(1)  // 确保按钮在图片之上
                    .buttonStyle(.plain)

                    // 下载按钮（对所有类型资源都显示）
                    Button {
                        onDownload()
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.Colors.primaryText)
                    }
                    .frame(width: 60, height: 60)  // 增大触控范围
                    .contentShape(Rectangle())  // 确保整个区域都可点击
                    .zIndex(1)  // 确保按钮在图片之上
                    .buttonStyle(.plain)

                    // 发布按钮暂时隐藏（功能待上线）
                    // if asset.type == .generated {
                    //     Button {
                    //         onPublish()
                    //     } label: {
                    //         Image(systemName: "globe")
                    //     }
                    // }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Colors.destructive)
                    }
                    .frame(width: 60, height: 60)  // 增大触控范围
                    .contentShape(Rectangle())  // 确保整个区域都可点击
                    .zIndex(1)  // 确保按钮在图片之上
                    .buttonStyle(.plain)
                }
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

    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                CachedAsyncImage(urlString: asset.url, localPath: asset.localPath, contentMode: .fit)
                    .frame(height: 200)
                    .cornerRadius(12)

                TextField("添加标题", text: $title)
                    .focused($isTitleFocused)
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

// MARK: - Toast 提示组件

private struct ToastView: View {
    let message: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        )
    }
}

// MARK: - 编辑器标题栏

private struct EditorTitleBar: View {
    @Binding var projectName: String
    @Binding var isEditingTitle: Bool
    @FocusState var isTitleFocused: Bool
    let onSave: () -> Void
    
    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Spacer()
            
            // 标题区域
            if isEditingTitle {
                TextField("输入创作名称", text: $projectName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.primaryText)
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.appBackground)
                    .cornerRadius(8)
                    .onSubmit {
                        finishEditing()
                    }
            } else {
                Button {
                    isEditingTitle = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isTitleFocused = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(projectName.isEmpty ? "未命名创作" : projectName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.Colors.primaryText)
                            .lineLimit(1)
                        
                        Image(systemName: "pencil")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .frame(height: 44)
        .background(.ultraThinMaterial)
        .onChange(of: isTitleFocused) { _, focused in
            if !focused && isEditingTitle {
                finishEditing()
            }
        }
    }
    
    private func finishEditing() {
        isEditingTitle = false
        isTitleFocused = false
        onSave()
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
