import SwiftUI
import SwiftData
import Observation

/// 原生编辑器视图模型 (适配新架构)
@Observable
@MainActor
final class NativeEditorViewModel {
    // MARK: - 项目信息
    
    let project: Project
    var projectName: String
    
    // MARK: - 画布文档
    
    var canvasDocument: CanvasDocument
    
    // MARK: - 状态管理
    
    var stateManager = CanvasStateManager()
    
    // MARK: - 资源管理
    
    var assets: [Asset] = []
    var selectedAsset: Asset?
    
    // MARK: - AI 生成
    
    var prompt = ""
    var isGenerating = false
    /// 图生图/文生图流程的提示（用于 UI 呈现失败原因，避免“点了没反应/空 sheet”）
    var flowHintMessage: String?

    // MARK: - 生成流程（由 View 的 activeSheet 驱动）
    // 这里不再维护 sheet 的 presented 状态，避免出现“双状态源”导致的无法再次打开问题。
    // 仅保留流程中需要复用的数据（预览图 / base64）。

    private var pendingImageToImageBase64: String?
    private var pendingImageToImagePreview: UIImage?
    
    // MARK: - 服务
    
    private let generationService = MockGenerationService.shared
    private var modelContext: ModelContext?
    
    // MARK: - 画布引用 (用于调用原生方法)
    
    weak var canvasView: NativeCanvasView?
    
    // MARK: - 形状工具
    
    /// 当前选中的形状类型
    var selectedShapeType: ShapeType = .rectangle
    
    // MARK: - Initialization
    
    init(project: Project) {
        self.project = project
        self.projectName = project.name
        
        // 初始化画布文档
        self.canvasDocument = CanvasDocument(projectID: project.id)
        
        // TODO: 从持久化存储加载画布文档
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadAssets()
    }
    
    // MARK: - 资源管理
    
    private func loadAssets() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<Asset>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        do {
            assets = try context.fetch(descriptor)
        } catch {
            print("加载资源失败: \(error)")
        }
    }
    
    /// 导入图片
    func importImage(_ imageData: Data) async {
        guard let context = modelContext else { return }
        
        do {
            // 上传图片
            let url = try await generationService.uploadImage(imageData)
            
            // 创建 Asset 记录
            let asset = Asset(
                url: url,
                type: .upload
            )
            
            context.insert(asset)
            try? context.save()
            
            loadAssets()
        } catch {
            print("上传图片失败: \(error)")
        }
    }
    
    // MARK: - 画布操作
    
    /// 添加图片到画布
    func addAssetToCanvas(_ asset: Asset) {
        guard let canvasView = canvasView else { return }
        
        // 计算图片应该放置的位置 (画布中心)
        let canvasSize = CGSize(width: 5000, height: 5000)
        let imageSize = CGSize(width: 300, height: 300)
        let position = CGPoint(
            x: (canvasSize.width - imageSize.width) / 2,
            y: (canvasSize.height - imageSize.height) / 2
        )
        
        // 创建图层节点
        let layer = LayerNode.userImage(
            url: asset.url,
            at: position,
            size: imageSize
        )
        
        // 添加到画布
        canvasView.addLayer(layer)
        canvasDocument.addLayer(layer)
    }
    
    /// 删除选中的图层
    func deleteSelectedLayer() {
        guard let selectedID = stateManager.selectedNodeID,
              let canvasView = canvasView else { return }
        
        canvasView.removeLayer(id: selectedID)
        canvasDocument.removeLayer(id: selectedID)
        stateManager.clearSelection()
    }
    
    /// 锁定/解锁选中的图层
    func toggleSelectedLayerLock() {
        guard let selectedID = stateManager.selectedNodeID,
              let canvasView = canvasView else { return }
        
        canvasView.toggleLayerLock(id: selectedID)
        
        // 同步到文档
        if let layer = canvasView.getSelectedLayer() {
            canvasDocument.updateLayer(layer)
        }
    }
    
    /// 图层置顶
    func bringSelectedLayerToFront() {
        guard let selectedID = stateManager.selectedNodeID,
              let canvasView = canvasView else { return }
        
        canvasView.bringLayerToFront(id: selectedID)
        
        // 同步到文档
        let layers = canvasView.getLayers()
        canvasDocument.layers = layers
    }
    
    /// 图层置底
    func sendSelectedLayerToBack() {
        guard let selectedID = stateManager.selectedNodeID,
              let canvasView = canvasView else { return }
        
        canvasView.sendLayerToBack(id: selectedID)
        
        // 同步到文档
        let layers = canvasView.getLayers()
        canvasDocument.layers = layers
    }
    
    // MARK: - AI 生成工作流
    
    /// 图生图：准备预览（立即截取选框内容，然后弹出确认浮窗）
    @discardableResult
    func prepareImageToImageFlow() -> Bool {
        guard !isGenerating else {
            print("[ImageToImage] Error: Already generating")
            return false
        }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("[ImageToImage] Error: Prompt is empty")
            flowHintMessage = "请输入生成描述"
            return false
        }
        guard let canvasView else {
            print("[ImageToImage] Error: canvasView is nil")
            flowHintMessage = "画布尚未就绪"
            return false
        }
        guard stateManager.isMagicFrameVisible else {
            print("[ImageToImage] Error: Magic frame not visible")
            flowHintMessage = "请先显示选框并框选区域"
            return false
        }

        // 视口坐标（magicFrame）-> 画布内容坐标（截图使用 contentRect）
        let viewportRect = stateManager.magicFrame
        print("[ImageToImage] viewportRect (magicFrame): \(viewportRect)")
        
        let contentRect = canvasView.contentRect(forViewportRect: viewportRect)
        print("[ImageToImage] contentRect (after conversion): \(contentRect)")

        guard let snapshot = canvasView.captureContentSnapshot(rect: contentRect),
              let imageData = snapshot.pngData() else {
            print("[ImageToImage] Error: Failed to capture snapshot")
            pendingImageToImagePreview = nil
            pendingImageToImageBase64 = nil
            flowHintMessage = "预览准备失败：选框无效或截图失败（区域过小/越界/渲染失败）"
            return false
        }

        print("[ImageToImage] Snapshot captured: size=\(snapshot.size)")
        pendingImageToImagePreview = snapshot
        pendingImageToImageBase64 = imageData.base64EncodedString()
        flowHintMessage = nil
        return true
    }

    func getPendingImageToImagePreview() -> UIImage? {
        pendingImageToImagePreview
    }

    func cancelImageToImageFlow() {
        pendingImageToImageBase64 = nil
        pendingImageToImagePreview = nil
        flowHintMessage = nil
    }

    /// 图生图：用户确认后执行生成
    func confirmImageToImageGenerate() async {
        guard !isGenerating else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let context = modelContext else { return }
        guard let canvasView = canvasView else { return }
        guard stateManager.isMagicFrameVisible else { return }
        guard let base64String = pendingImageToImageBase64 else { return }

        isGenerating = true
        flowHintMessage = nil
        // 生成开始后立即清理 pending（避免 UI dismiss 链路误触发取消导致丢失输入）
        pendingImageToImageBase64 = nil
        pendingImageToImagePreview = nil

        let loadingAsset = Asset(
            url: "",
            type: .generated,
            prompt: trimmed,
            isLoading: true
        )
        loadingAsset.generationModeRawValue = GenerationMode.img2img.rawValue

        context.insert(loadingAsset)
        try? context.save()
        loadAssets()

        do {
            let request = GenerationRequest(
                prompt: trimmed,
                imageBase64: base64String,
                model: "Nano Banana Pro"
            )

            let response = try await generationService.generate(request: request)

            loadingAsset.url = response.imageUrl
            loadingAsset.thumbnailUrl = response.thumbnailUrl
            loadingAsset.isLoading = false

            try? context.save()
            loadAssets()

            let maxZ = canvasDocument.maxZIndex
            // 回填必须使用“画布内容坐标”frame，而不是视口 magicFrame
            let contentRect = canvasView.contentRect(forViewportRect: stateManager.magicFrame)
            let generatedLayer = LayerNode.aiGenerated(
                url: response.imageUrl,
                frame: contentRect,
                zIndex: maxZ + 1
            )

            canvasView.addLayer(generatedLayer)
            canvasDocument.addLayer(generatedLayer)

            prompt = ""
            stateManager.hideMagicFrame()

        } catch {
            context.delete(loadingAsset)
            try? context.save()
            loadAssets()
            print("生成失败: \(error)")
            flowHintMessage = "生成失败：\(error.localizedDescription)"
        }

        isGenerating = false
    }

    /// 文生图：生成资源（不自动上画布）
    func generateTextToImage(prompt: String, ratio: ImageAspectRatio) async {
        guard !isGenerating else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let context = modelContext else { return }

        isGenerating = true

        let loadingAsset = Asset(
            url: "",
            type: .generated,
            prompt: trimmed,
            isLoading: true
        )
        loadingAsset.generationModeRawValue = GenerationMode.txt2img.rawValue
        loadingAsset.aspectRatio = ratio.rawValue

        context.insert(loadingAsset)
        try? context.save()
        loadAssets()

        do {
            let request = GenerationRequest(
                prompt: trimmed,
                imageBase64: nil,
                model: "Nano Banana Pro"
            )

            let response = try await generationService.generate(request: request)

            loadingAsset.url = response.imageUrl
            loadingAsset.thumbnailUrl = response.thumbnailUrl
            loadingAsset.isLoading = false

            try? context.save()
            loadAssets()

        } catch {
            context.delete(loadingAsset)
            try? context.save()
            loadAssets()
            print("生成失败: \(error)")
        }

        isGenerating = false
    }
    
    // MARK: - Asset 操作
    
    func deleteAsset(_ asset: Asset) {
        guard let context = modelContext else { return }
        context.delete(asset)
        try? context.save()
        loadAssets()
    }
    
    func downloadAsset(_ asset: Asset) {
        // TODO: 实现下载到相册功能
        print("下载资源: \(asset.url)")
    }
    
    func publishAsset(_ asset: Asset, title: String) async {
        guard asset.type == .generated else { return }
        
        do {
            try await MockFeedService.shared.publishImage(
                imageUrl: asset.url,
                title: title,
                prompt: asset.prompt,
                showPrompt: true
            )
            print("发布成功")
        } catch {
            print("发布失败: \(error)")
        }
    }
    
    // MARK: - 画布持久化
    
    /// 保存画布文档
    func saveCanvasDocument() {
        guard let canvasView = canvasView else { return }
        
        // 同步图层数据
        canvasDocument.layers = canvasView.getLayers()
        
        // 同步箭头数据
        canvasDocument.arrows = canvasView.getArrowLayerManager().arrows
        
        // 同步矩形数据
        canvasDocument.rectangles = canvasView.getRectangleLayerManager().rectangles
        
        // 同步文字数据
        canvasDocument.texts = canvasView.getTextLayerManager().textLayers
        
        // 同步标注数据
        canvasDocument.annotations = canvasView.getAnnotationLayerManager().annotations
        
        // 同步绘图数据
        canvasDocument.drawingData = canvasView.getDrawingData()
        
        // TODO: 持久化到 SwiftData 或文件系统
        print("画布文档已保存")
    }
    
    /// 加载画布文档
    func loadCanvasDocument() {
        guard let canvasView = canvasView else { return }
        
        // 加载图层
        canvasView.setLayers(canvasDocument.layers)
        
        // 加载箭头
        let arrowManager = canvasView.getArrowLayerManager()
        for arrow in canvasDocument.arrows {
            arrowManager.addArrow(arrow)
        }
        
        // 加载矩形
        let rectangleManager = canvasView.getRectangleLayerManager()
        for rectangle in canvasDocument.rectangles {
            rectangleManager.addRectangle(rectangle)
        }
        
        // 加载文字
        let textManager = canvasView.getTextLayerManager()
        for text in canvasDocument.texts {
            textManager.addText(text)
        }
        
        // 加载标注
        let annotationManager = canvasView.getAnnotationLayerManager()
        for annotation in canvasDocument.annotations {
            annotationManager.addAnnotation(annotation)
        }
        
        // 加载绘图
        if let drawingData = canvasDocument.drawingData {
            canvasView.loadDrawing(from: drawingData)
        }
        
        // 清空撤销栈（新会话开始）
        stateManager.clearUndoRedoStacks()
        
        print("画布文档已加载")
    }
}

