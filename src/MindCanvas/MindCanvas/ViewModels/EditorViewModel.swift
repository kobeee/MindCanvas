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

