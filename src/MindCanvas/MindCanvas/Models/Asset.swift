import Foundation
import SwiftData

enum AssetType: String, Codable {
    case upload
    case generated
}

@Model
final class Asset {
    @Attribute(.unique) var id: UUID
    var url: String
    var thumbnailUrl: String
    var type: AssetType
    var prompt: String?
    var generationModeRawValue: String?
    var aspectRatio: String?
    var createdAt: Date
    var isLoading: Bool
    
    /// 关联的项目ID（每个创作独立管理资源）
    var projectID: UUID?
    
    init(id: UUID = UUID(), url: String, thumbnailUrl: String? = nil, type: AssetType, prompt: String? = nil, isLoading: Bool = false, projectID: UUID? = nil) {
        self.id = id
        self.url = url
        self.thumbnailUrl = thumbnailUrl ?? url
        self.type = type
        self.prompt = prompt
        self.generationModeRawValue = nil
        self.aspectRatio = nil
        self.createdAt = Date()
        self.isLoading = isLoading
        self.projectID = projectID
    }
}

