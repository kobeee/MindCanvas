import Foundation

struct Token: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: User
    
    private let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.refreshToken = try container.decode(String.self, forKey: .refreshToken)
        self.tokenType = try container.decode(String.self, forKey: .tokenType)
        self.expiresIn = try container.decode(Int.self, forKey: .expiresIn)

        // 手动解码 user 对象，使用自定义的日期解码器
        let userContainer = try container.nestedContainer(keyedBy: User.CodingKeys.self, forKey: .user)
        let id = try userContainer.decode(String.self, forKey: .id)
        let username = try userContainer.decode(String.self, forKey: .username)
        let email = try userContainer.decodeIfPresent(String.self, forKey: .email)
        let avatarUrl = try userContainer.decodeIfPresent(String.self, forKey: .avatarUrl)
        let authProvider = try userContainer.decode(String.self, forKey: .authProvider)

        // 自定义日期解码，支持 ISO8601 带微秒的格式
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let createdAtString = try userContainer.decode(String.self, forKey: .createdAt)
        let updatedAtString = try userContainer.decode(String.self, forKey: .updatedAt)

        let createdAt = dateFormatter.date(from: createdAtString) ?? Date()
        let updatedAt = dateFormatter.date(from: updatedAtString) ?? Date()

        self.user = User(id: id, username: username, email: email, avatarUrl: avatarUrl, authProvider: authProvider, createdAt: createdAt, updatedAt: updatedAt)
        self.createdAt = Date()
    }
    
    init(accessToken: String, refreshToken: String, tokenType: String, expiresIn: Int, user: User) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.user = user
        self.createdAt = Date()
    }

    var expiresAt: Date {
        return createdAt.addingTimeInterval(TimeInterval(expiresIn))
    }

    var isExpiringSoon: Bool {
        let fiveMinutes: TimeInterval = 300
        return Date().addingTimeInterval(fiveMinutes) >= expiresAt
    }
}