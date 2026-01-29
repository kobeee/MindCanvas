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
    
    /// 本地图片路径（相对路径，如 "images/xxx.jpg"）
    /// 下载成功后会保存本地路径，避免每次重新加载
    var localPath: String?
    
    /// 关联的项目ID（每个创作独立管理资源）
    var projectID: UUID?
    
    init(id: UUID = UUID(), url: String, thumbnailUrl: String? = nil, type: AssetType, prompt: String? = nil, isLoading: Bool = false, localPath: String? = nil, projectID: UUID? = nil) {
        self.id = id
        self.url = url
        self.thumbnailUrl = thumbnailUrl ?? url
        self.type = type
        self.prompt = prompt
        self.generationModeRawValue = nil
        self.aspectRatio = nil
        self.createdAt = Date()
        self.isLoading = isLoading
        self.localPath = localPath
        self.projectID = projectID
    }
}

