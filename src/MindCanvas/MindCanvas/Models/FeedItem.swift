import Foundation

struct FeedItem: Identifiable, Codable {
    let id: String
    let imageUrl: String
    let thumbnailUrl: String
    let author: User
    let prompt: String?
    let showPrompt: Bool
    let likesCount: Int
    let createdAt: Date
    var isLiked: Bool
    
    init(id: String, imageUrl: String, thumbnailUrl: String? = nil, author: User, prompt: String? = nil, showPrompt: Bool = true, likesCount: Int = 0, createdAt: Date = Date(), isLiked: Bool = false) {
        self.id = id
        self.imageUrl = imageUrl
        self.thumbnailUrl = thumbnailUrl ?? imageUrl
        self.author = author
        self.prompt = prompt
        self.showPrompt = showPrompt
        self.likesCount = likesCount
        self.createdAt = createdAt
        self.isLiked = isLiked
    }
}

