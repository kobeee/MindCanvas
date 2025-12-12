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
    
    init(id: UUID = UUID(), url: String, thumbnailUrl: String? = nil, type: AssetType, prompt: String? = nil, isLoading: Bool = false) {
        self.id = id
        self.url = url
        self.thumbnailUrl = thumbnailUrl ?? url
        self.type = type
        self.prompt = prompt
        self.generationModeRawValue = nil
        self.aspectRatio = nil
        self.createdAt = Date()
        self.isLoading = isLoading
    }
}

