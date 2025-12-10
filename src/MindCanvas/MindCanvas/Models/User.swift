import Foundation

struct User: Codable, Identifiable {
    let id: String
    let username: String
    let email: String?
    let avatarUrl: String?
    let isPro: Bool
    
    init(id: String, username: String, email: String? = nil, avatarUrl: String? = nil, isPro: Bool = false) {
        self.id = id
        self.username = username
        self.email = email
        self.avatarUrl = avatarUrl
        self.isPro = isPro
    }
}

