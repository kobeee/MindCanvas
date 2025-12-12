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
    
    // MARK: - 服务
    
    private let generationService = MockGenerationService.shared
    private var modelContext: ModelContext?
    
    // MARK: - 画布引用 (用于调用原生方法)
    
    weak var canvasView: NativeCanvasView?
    
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
    
    /// 生成图片
    func generate() async {
        guard !prompt.isEmpty else { return }
        guard let context = modelContext else { return }
        guard let canvasView = canvasView else { return }
        guard stateManager.isMagicFrameVisible else { return }
        
        isGenerating = true
        
        // Step 1: 创建 Loading Asset
        let loadingAsset = Asset(
            url: "",
            type: .generated,
            prompt: prompt,
            isLoading: true
        )
        
        context.insert(loadingAsset)
        try? context.save()
        loadAssets()
        
        // Step 2: 捕获 Magic Frame 区域的快照
        guard let snapshot = canvasView.captureSnapshot(rect: stateManager.magicFrame) else {
            isGenerating = false
            context.delete(loadingAsset)
            return
        }
        
        // 转换为 Base64
        guard let imageData = snapshot.pngData() else {
            isGenerating = false
            context.delete(loadingAsset)
            return
        }
        let base64String = imageData.base64EncodedString()
        
        do {
            // Step 3: 调用生成 API
            let request = GenerationRequest(
                prompt: prompt,
                imageBase64: base64String,
                model: "Nano Banana Pro"
            )
            
            let response = try await generationService.generate(request: request)
            
            // Step 4: 更新 Asset
            loadingAsset.url = response.imageUrl
            loadingAsset.thumbnailUrl = response.thumbnailUrl
            loadingAsset.isLoading = false
            
            try? context.save()
            loadAssets()
            
            // Step 5: 创建图层节点并回填到画布
            let maxZ = canvasDocument.maxZIndex
            let generatedLayer = LayerNode.aiGenerated(
                url: response.imageUrl,
                frame: stateManager.magicFrame,
                zIndex: maxZ + 1
            )
            
            canvasView.addLayer(generatedLayer)
            canvasDocument.addLayer(generatedLayer)
            
            // Step 6: 清空 Prompt
            prompt = ""
            
            // 隐藏 Magic Frame
            stateManager.hideMagicFrame()
            
        } catch {
            // 失败：移除 Loading Asset
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
        
        // 加载绘图
        if let drawingData = canvasDocument.drawingData {
            canvasView.loadDrawing(from: drawingData)
        }
        
        print("画布文档已加载")
    }
}

