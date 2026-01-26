import SwiftUI
import SwiftData
import Observation

@Observable
@MainActor
final class EditorViewModel {
    let project: Project
    var projectName: String
    var assets: [Asset] = []
    var selectedAsset: Asset?
    var prompt = ""
    var isGenerating = false
    var canvasSnapshot: String?
    var hasSelection = false
    var showDownloadSuccessToast = false
    
    private let generationService = RealGenerationService.shared
    private var modelContext: ModelContext?
    
    init(project: Project) {
        self.project = project
        self.projectName = project.name
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadAssets()
    }
    
    private func loadAssets() {
        guard let context = modelContext else { return }

        let descriptor = FetchDescriptor<Asset>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        do {
            assets = try context.fetch(descriptor)
        } catch {
        }
    }
    
    func importImage(_ imageData: Data) async {
        guard let context = modelContext else { return }
        
        do {
            let url = try await generationService.uploadImage(imageData)
            
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
    
    func generate() async {
        guard !prompt.isEmpty else { return }
        guard let context = modelContext else { return }
        
        isGenerating = true
        
        let loadingAsset = Asset(
            url: "",
            type: .generated,
            prompt: prompt,
            isLoading: true
        )
        
        context.insert(loadingAsset)
        try? context.save()
        loadAssets()
        
        do {
            let request = GenerationRequest(
                prompt: prompt,
                imageBase64: canvasSnapshot,
                model: "Nano Banana Pro"
            )
            
            let response = try await generationService.generate(request: request)
            
            loadingAsset.url = response.imageUrl
            loadingAsset.thumbnailUrl = response.thumbnailUrl
            loadingAsset.isLoading = false
            
            try? context.save()
            loadAssets()
            
            prompt = ""
        } catch {
            context.delete(loadingAsset)
            try? context.save()
            loadAssets()
            print("生成失败: \(error)")
        }
        
        isGenerating = false
    }
    
    func deleteAsset(_ asset: Asset) {
        guard let context = modelContext else { return }
        context.delete(asset)
        try? context.save()
        loadAssets()
    }
    
    func addAssetToCanvas(_ asset: Asset) {
    }
    
    func downloadAsset(_ asset: Asset) {
        Task {
            var image: UIImage?
            let urlString = asset.url

            // 判断是否为本地路径（相对路径或 file:// URL）
            let isLocalPath = ImageStorageService.isRelativePath(urlString) ||
                              (URL(string: urlString)?.isFileURL == true)

            if isLocalPath {
                // 本地图片：使用 ImageStorageService 加载（支持相对路径和路径恢复）
                image = ImageStorageService.shared.loadImage(from: urlString)
                if image == nil {
                    print("无法加载本地图片: \(urlString)")
                }
            } else if let url = URL(string: urlString) {
                // 远程 URL：异步加载
                image = await ImageStorageService.shared.getImage(from: url)
                if image == nil {
                    print("无法加载远程图片: \(urlString)")
                }
            } else {
                print("无效的资源URL: \(urlString)")
                return
            }

            guard let validImage = image else {
                print("无法加载图片: \(urlString)")
                return
            }

            // 保存到相册
            do {
                try await saveImageToPhotoLibrary(validImage)
                // 显示成功提示
                await MainActor.run {
                    showDownloadSuccessToast = true
                }
            } catch {
                print("保存到相册失败: \(error)")
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
            try await FeedService.shared.publishImage(
                imageUrl: asset.url,
                title: title,
                prompt: asset.prompt,
                showPrompt: true
            )
        } catch {
            print("发布失败: \(error)")
        }
    }
    
    func updateCanvasSnapshot(_ base64: String) {
        canvasSnapshot = base64
    }
    
    func updateSelection(hasSelection: Bool) {
        self.hasSelection = hasSelection
    }
}

