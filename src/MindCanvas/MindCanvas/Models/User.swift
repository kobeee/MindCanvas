import Foundation

struct User: Codable, Identifiable {
    let id: String
    let username: String
    let email: String?
    let avatarUrl: String?
    let authProvider: String
    let createdAt: Date
    let updatedAt: Date

    var isPro: Bool = false

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case avatarUrl = "avatar_url"
        case authProvider = "auth_provider"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: String, username: String, email: String? = nil, avatarUrl: String? = nil, isPro: Bool = false, authProvider: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.username = username
        self.email = email
        self.avatarUrl = avatarUrl
        self.isPro = isPro
        self.authProvider = authProvider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

