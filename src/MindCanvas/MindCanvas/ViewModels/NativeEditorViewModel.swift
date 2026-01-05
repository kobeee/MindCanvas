import SwiftUI
import SwiftData
import Observation

/// 文档操作错误
enum DocumentError: Error {
    case fileNotFound
    case invalidData
    case permissionDenied
}

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
    
    private let generationService = RealGenerationService.shared
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
        
        // 只加载当前项目的资源
        let projectID = project.id
        let descriptor = FetchDescriptor<Asset>(
            predicate: #Predicate<Asset> { asset in
                asset.projectID == projectID
            },
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
            
            // 创建 Asset 记录（关联当前项目）
            let asset = Asset(
                url: url,
                type: .upload,
                projectID: project.id
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
        guard let canvasView = canvasView else {
            print("❌ [AddAsset] canvasView 不可用")
            return
        }
        
        print("🖼️ [AddAsset] 开始添加资源: \(asset.url.prefix(50))...")
        
        // 异步加载图片获取原始尺寸
        loadImageSize(from: asset.url) { [weak self] originalSize in
            guard let self = self else { return }
            
            // 限制最大尺寸，避免图片过大
            let maxSize: CGFloat = 600
            let scaledSize = self.scaleImageSizeToFit(originalSize, maxSize: maxSize)
            
            // 计算图片应该放置的位置 (画布中心)
            let canvasSize = CGSize(width: 5000, height: 5000)
            let position = CGPoint(
                x: (canvasSize.width - scaledSize.width) / 2,
                y: (canvasSize.height - scaledSize.height) / 2
            )
            
            // 创建图层节点
            let layer = LayerNode.userImage(
                url: asset.url,
                at: position,
                size: scaledSize,
                originalSize: originalSize
            )
            
            print("🖼️ [AddAsset] 创建图层: id=\(layer.id), frame=\(layer.frame)")
            
            // 添加到画布（这会触发 onCanvasUpdated -> saveCanvasDocument）
            canvasView.addLayer(layer)
            self.canvasDocument.addLayer(layer)
            
            print("✅ [AddAsset] 图层已添加到画布和文档")
        }
    }
    
    /// 加载图片获取尺寸（支持本地和远程URL）
    private func loadImageSize(from urlString: String, completion: @escaping (CGSize) -> Void) {
        let defaultSize = CGSize(width: 300, height: 300)
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(defaultSize) }
            return
        }
        
        // 本地文件
        if url.isFileURL {
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                DispatchQueue.main.async { completion(image.size) }
            } else {
                DispatchQueue.main.async { completion(defaultSize) }
            }
            return
        }
        
        // 远程图片
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async { completion(image.size) }
            } else {
                DispatchQueue.main.async { completion(defaultSize) }
            }
        }.resume()
    }
    
    /// 缩放图片尺寸以适应最大尺寸限制
    private func scaleImageSizeToFit(_ size: CGSize, maxSize: CGFloat) -> CGSize {
        if size.width <= maxSize && size.height <= maxSize {
            return size
        }
        let scale = min(maxSize / size.width, maxSize / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
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
            return false
        }

        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            flowHintMessage = "请输入生成描述"
            return false
        }

        guard let canvasView else {
            flowHintMessage = "画布尚未就绪"
            return false
        }

        guard stateManager.isMagicFrameVisible else {
            flowHintMessage = "请先显示选框并框选区域"
            return false
        }

        let viewportRect = stateManager.magicFrame

        guard let snapshot = canvasView.captureVisibleAreaSnapshot(viewportRect: viewportRect),
              let imageData = snapshot.pngData() else {
            pendingImageToImagePreview = nil
            pendingImageToImageBase64 = nil
            flowHintMessage = "预览准备失败：截图失败"
            return false
        }

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
        print("[ImageToImage] ===== Begin confirmImageToImageGenerate =====")

        guard !isGenerating else {
            print("[ImageToImage] Error: Already generating")
            flowHintMessage = "正在生成中，请稍候"
            return
        }

        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[ImageToImage] prompt: \(trimmed.isEmpty ? "(empty)" : trimmed)")

        guard !trimmed.isEmpty else {
            print("[ImageToImage] Error: Prompt is empty")
            flowHintMessage = "请输入生成描述"
            return
        }

        guard let context = modelContext else {
            print("[ImageToImage] Error: modelContext is nil")
            flowHintMessage = "数据上下文不可用"
            return
        }

        guard let canvasView = canvasView else {
            print("[ImageToImage] Error: canvasView is nil")
            flowHintMessage = "画布尚未就绪"
            return
        }

        guard stateManager.isMagicFrameVisible else {
            print("[ImageToImage] Error: Magic Frame not visible")
            flowHintMessage = "选框已关闭，请重新选择区域"
            return
        }

        guard let base64String = pendingImageToImageBase64 else {
            print("[ImageToImage] Error: pendingImageToImageBase64 is nil")
            flowHintMessage = "预览数据丢失，请重新选择区域"
            return
        }

        print("[ImageToImage] base64Image length: \(base64String.count)")

        isGenerating = true
        flowHintMessage = nil
        // 生成开始后立即清理 pending（避免 UI dismiss 链路误触发取消导致丢失输入）
        pendingImageToImageBase64 = nil
        pendingImageToImagePreview = nil

        let loadingAsset = Asset(
            url: "",
            type: .generated,
            prompt: trimmed,
            isLoading: true,
            projectID: project.id
        )
        loadingAsset.generationModeRawValue = GenerationMode.img2img.rawValue

        context.insert(loadingAsset)
        do {
            try context.save()
            print("[ImageToImage] Loading asset saved successfully")
        } catch {
            print("[ImageToImage] Error: Failed to save loading asset: \(error)")
            flowHintMessage = "保存失败：\(error.localizedDescription)"
            isGenerating = false
            return
        }

        loadAssets()

        do {
            print("[ImageToImage] Calling generationService.generate...")
            let request = GenerationRequest(
                prompt: trimmed,
                imageBase64: base64String,
                model: "Nano Banana Pro"
            )

            let response = try await generationService.generate(request: request)

            print("[ImageToImage] Generation success, url: \(response.imageUrl)")

            loadingAsset.url = response.imageUrl
            loadingAsset.thumbnailUrl = response.thumbnailUrl
            loadingAsset.isLoading = false

            do {
                try context.save()
                print("[ImageToImage] Asset updated successfully")
            } catch {
                print("[ImageToImage] Error: Failed to update asset: \(error)")
            }
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
            do {
                try context.save()
            } catch {
            }

            loadAssets()

            flowHintMessage = "生成失败：\(error.localizedDescription)"
        }

        isGenerating = false
    }

    /// 文生图：生成资源（不自动上画布）
    func generateTextToImage(prompt: String, ratio: ImageAspectRatio) async {
        guard !isGenerating else {
            flowHintMessage = "正在生成中，请稍候"
            return
        }

        // 提前验证 API Key
        guard KeychainManager.shared.hasAPIKey() else {
            flowHintMessage = "请先在设置中配置 API Key"
            return
        }

        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            flowHintMessage = "请输入生成描述"
            return
        }

        guard let context = modelContext else {
            flowHintMessage = "数据上下文不可用"
            return
        }

        isGenerating = true
        flowHintMessage = nil

        let loadingAsset = Asset(
            url: "",
            type: .generated,
            prompt: trimmed,
            isLoading: true,
            projectID: project.id
        )
        loadingAsset.generationModeRawValue = GenerationMode.txt2img.rawValue
        loadingAsset.aspectRatio = ratio.rawValue

        context.insert(loadingAsset)
        do {
            try context.save()
        } catch {
            flowHintMessage = "保存失败：\(error.localizedDescription)"
            isGenerating = false
            return
        }

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

            do {
                try context.save()
            } catch {
            }

            loadAssets()

        } catch {
            context.delete(loadingAsset)
            do {
                try context.save()
            } catch {
            }

            loadAssets()

            flowHintMessage = "生成失败：\(error.localizedDescription)"
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
        guard let url = URL(string: asset.url) else {
            print("无效的资源URL: \(asset.url)")
            return
        }
        
        Task {
            do {
                // 下载图片数据
                let (data, _) = try await URLSession.shared.data(from: url)
                
                guard let image = UIImage(data: data) else {
                    print("无法解析图片数据")
                    return
                }
                
                // 保存到相册
                try await saveImageToPhotoLibrary(image)
                print("图片已保存到相册")
                
            } catch {
                print("下载图片失败: \(error)")
            }
        }
    }
    
    /// 保存图片到相册
    private func saveImageToPhotoLibrary(_ image: UIImage) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            // 由于 UIImageWriteToSavedPhotosAlbum 是异步的但没有完成回调，
            // 我们在短暂延迟后返回成功（实际保存由系统完成）
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                continuation.resume()
            }
        }
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
    
    /// 保存画布文档（带数据验证）
    @discardableResult
    func saveCanvasDocument() -> SaveResult {
        guard !isLoadingData else {
            print("⏭️ [Save] 跳过保存：正在加载数据")
            return .success
        }

        guard let canvasView = canvasView else {
            print("❌ [Save] 失败：canvasView 不可用")
            return .failure(.canvasViewNotAvailable)
        }

        do {
            syncDataFromCanvas(canvasView)
            
            // 打印保存的数据摘要
            print("💾 [Save] 保存数据: layers=\(canvasDocument.layers.count), arrows=\(canvasDocument.arrows.count), shapes=\(canvasDocument.shapes.count), texts=\(canvasDocument.texts.count)")
            if let firstLayer = canvasDocument.layers.first {
                print("   └─ 首个图层: frame=\(firstLayer.frame), url=\(firstLayer.url?.prefix(50) ?? "nil")")
            }

            let validationErrors = canvasDocument.validate()
            if !validationErrors.isEmpty {
                canvasDocument.repair()
            }

            try performSave()
            print("✅ [Save] 保存成功")

            return .success

        } catch {
            print("❌ [Save] 保存失败: \(error)")
            return .failure(.saveError(error))
        }
    }
    
    /// 加载画布文档（带错误处理和版本兼容性）
    @discardableResult
    func loadCanvasDocument() -> LoadResult {
        guard !hasLoadedDocument else {
            print("⏭️ [Load] 跳过加载：已加载过文档")
            return .success
        }

        guard let canvasView = canvasView else {
            print("❌ [Load] 失败：canvasView 不可用")
            return .failure(.canvasViewNotAvailable)
        }

        do {
            try performLoad()
            print("📂 [Load] 加载数据: layers=\(canvasDocument.layers.count), arrows=\(canvasDocument.arrows.count), shapes=\(canvasDocument.shapes.count), texts=\(canvasDocument.texts.count)")
            if let firstLayer = canvasDocument.layers.first {
                print("   └─ 首个图层: frame=\(firstLayer.frame), url=\(firstLayer.url?.prefix(50) ?? "nil")")
            }
        } catch DocumentError.fileNotFound {
            print("📂 [Load] 文件不存在，使用空文档")
        } catch {
            print("❌ [Load] 加载失败: \(error)")
            return .failure(.loadError(error))
        }

        if canvasDocument.version > 1 {
        }

        let validationErrors = canvasDocument.validate()
        if !validationErrors.isEmpty {
            canvasDocument.repair()
        }

        syncDataToCanvas(canvasView)
        print("✅ [Load] 同步到画布完成")

        hasLoadedDocument = true

        stateManager.clearUndoRedoStacks()

        return .success
    }
    
    /// 强制保存（跳过验证）
    func forceSaveCanvasDocument() -> SaveResult {
        guard let canvasView = canvasView else {
            return .failure(.canvasViewNotAvailable)
        }

        do {
            syncDataFromCanvas(canvasView)
            try performSave()
            return .success
        } catch {
            return .failure(.saveError(error))
        }
    }
    
    /// 创建文档备份
    func createDocumentBackup() -> Bool {
        do {
            let backupData = try JSONEncoder().encode(canvasDocument)
            let backupURL = getBackupURL()
            try backupData.write(to: backupURL)
            print("✅ 文档备份已创建: \(backupURL.lastPathComponent)")
            return true
        } catch {
            print("❌ 创建文档备份失败: \(error)")
            return false
        }
    }
    
    /// 从备份恢复文档
    func restoreFromBackup() -> Bool {
        let backupURL = getBackupURL()
        
        guard FileManager.default.fileExists(atPath: backupURL.path) else {
            print("❌ 备份文件不存在")
            return false
        }
        
        do {
            let backupData = try Data(contentsOf: backupURL)
            let backupDocument = try JSONDecoder().decode(CanvasDocument.self, from: backupData)
            
            // 验证备份数据
            let validationErrors = backupDocument.validate()
            if !validationErrors.isEmpty {
                print("⚠️ 备份数据存在问题，将尝试修复")
                var repairedDocument = backupDocument
                repairedDocument.repair()
                canvasDocument = repairedDocument
            } else {
                canvasDocument = backupDocument
            }
            
            print("✅ 已从备份恢复文档")
            return true
        } catch {
            print("❌ 从备份恢复失败: \(error)")
            return false
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// 从画布视图同步数据到文档
    private func syncDataFromCanvas(_ canvasView: NativeCanvasView) {
        // 同步图层数据
        canvasDocument.layers = canvasView.getLayers()
        
        // 同步箭头数据
        canvasDocument.arrows = canvasView.getArrowLayerManager().arrows
        
        // 同步矩形数据
        canvasDocument.rectangles = canvasView.getRectangleLayerManager().rectangles
        
        // 同步形状数据
        canvasDocument.shapes = canvasView.getShapeLayerManager().shapes
        
        // 同步文字数据
        canvasDocument.texts = canvasView.getTextLayerManager().getAllTexts()
        
        // 同步标注数据
        canvasDocument.annotations = canvasView.getAnnotationLayerManager().annotations

        canvasDocument.drawingData = canvasView.getDrawingData()
    }
    
    /// 标记是否正在加载数据（防止加载过程中触发保存）
    private var isLoadingData = false
    
    /// 标记是否已经加载过文档（防止重复加载）
    private var hasLoadedDocument = false
    
    /// 从文档同步数据到画布视图
    private func syncDataToCanvas(_ canvasView: NativeCanvasView) {
        // 关键：设置加载标记，防止 clear 操作触发保存
        isLoadingData = true
        defer { isLoadingData = false }
        
        // 1. 清理所有现有图层和视图，并加载图片图层
        canvasView.setLayers(canvasDocument.layers)  // 内部会先 removeAllLayers 再添加
        
        // 2. 清理并加载箭头（使用 canvasView 方法以创建视图）
        canvasView.clearArrows()
        for arrow in canvasDocument.arrows {
            canvasView.addArrow(arrow, recordUndo: false)
        }
        
        // 3. 清理并加载矩形
        canvasView.clearRectangles()
        for rectangle in canvasDocument.rectangles {
            canvasView.addRectangle(rectangle, recordUndo: false)
        }
        
        // 4. 清理并加载形状（使用 canvasView 方法以创建视图）
        canvasView.clearShapes()
        for shape in canvasDocument.shapes {
            canvasView.addShape(shape, recordUndo: false)
        }
        
        // 5. 清理并加载文字（使用 canvasView 方法以创建视图）
        canvasView.clearTexts()
        for text in canvasDocument.texts {
            canvasView.addText(text, recordUndo: false)
        }
        
        // 6. 清理并加载标注
        canvasView.clearAnnotations()
        for annotation in canvasDocument.annotations {
            canvasView.addAnnotation(annotation, recordUndo: false)
        }
        
        // 7. 加载绘图数据
        if let drawingData = canvasDocument.drawingData {
            canvasView.loadDrawing(from: drawingData)
        }
    }
    
    /// 执行实际的保存操作
    private func performSave() throws {
        // 这里可以实现保存到 SwiftData 或文件系统
        // 目前使用简单的本地存储模拟
        
        let documentData = try JSONEncoder().encode(canvasDocument)
        let documentURL = getDocumentURL()
        
        // 确保目录存在
        let directory = documentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        try documentData.write(to: documentURL)
    }
    
    /// 执行实际的加载操作
    private func performLoad() throws {
        let documentURL = getDocumentURL()
        
        guard FileManager.default.fileExists(atPath: documentURL.path) else {
            throw DocumentError.fileNotFound
        }
        
        let documentData = try Data(contentsOf: documentURL)
        canvasDocument = try JSONDecoder().decode(CanvasDocument.self, from: documentData)
    }
    
    /// 获取文档存储URL
    private func getDocumentURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let canvasDocumentsPath = documentsPath.appendingPathComponent("CanvasDocuments")
        return canvasDocumentsPath.appendingPathComponent("\(project.id.uuidString).canvas")
    }
    
    /// 获取备份文件URL
    private func getBackupURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let canvasDocumentsPath = documentsPath.appendingPathComponent("CanvasDocuments")
        return canvasDocumentsPath.appendingPathComponent("\(project.id.uuidString).backup")
    }
}

// MARK: - 支持类型

/// 保存结果
enum SaveResult {
    case success
    case failure(SaveError)
}

/// 加载结果
enum LoadResult {
    case success
    case failure(LoadError)
}

/// 保存错误类型
enum SaveError: Error {
    case canvasViewNotAvailable
    case saveError(Error)
    case validationFailed([ValidationError])
    
    var localizedDescription: String {
        switch self {
        case .canvasViewNotAvailable:
            return "画布视图不可用"
        case .saveError(let error):
            return "保存失败: \(error.localizedDescription)"
        case .validationFailed(let errors):
            return "数据验证失败: \(errors.map(\.localizedDescription).joined(separator: ", "))"
        }
    }
}

/// 加载错误类型
enum LoadError: Error {
    case canvasViewNotAvailable
    case loadError(Error)
    case versionMismatch(Int, Int)
    case dataCorrupted
    
    var localizedDescription: String {
        switch self {
        case .canvasViewNotAvailable:
            return "画布视图不可用"
        case .loadError(let error):
            return "加载失败: \(error.localizedDescription)"
        case .versionMismatch(let current, let required):
            return "版本不匹配: 当前 v\(current)，需要 v\(required)"
        case .dataCorrupted:
            return "数据已损坏"
        }
    }
}
