import Foundation

struct User: Codable, Identifiable {
    let id: String
    var username: String
    let email: String?
    let avatarUrl: String?
    let authProvider: String
    let createdAt: Date
    let updatedAt: Date

    var isPro: Bool = false
    var freeQuota: Int = 0
    var apiProvider: String = "google"
    var totalQuotaUsed: Int = 0
    var subscriptionTier: String = "free"

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case avatarUrl = "avatar_url"
        case authProvider = "auth_provider"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPro = "is_pro"
        case freeQuota = "free_quota"
        case apiProvider = "api_provider"
        case totalQuotaUsed = "total_quota_used"
        case subscriptionTier = "subscription_tier"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        authProvider = try container.decodeIfPresent(String.self, forKey: .authProvider) ?? ""
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()

        isPro = try container.decodeIfPresent(Bool.self, forKey: .isPro) ?? false
        freeQuota = try container.decodeIfPresent(Int.self, forKey: .freeQuota) ?? 0
        apiProvider = try container.decodeIfPresent(String.self, forKey: .apiProvider) ?? "google"
        totalQuotaUsed = try container.decodeIfPresent(Int.self, forKey: .totalQuotaUsed) ?? 0
        subscriptionTier = try container.decodeIfPresent(String.self, forKey: .subscriptionTier) ?? "free"
    }

    init(id: String, username: String, email: String? = nil, avatarUrl: String? = nil, isPro: Bool = false, authProvider: String = "", createdAt: Date = Date(), updatedAt: Date = Date(), freeQuota: Int = 0, apiProvider: String = "google", totalQuotaUsed: Int = 0, subscriptionTier: String = "free") {
        self.id = id
        self.username = username
        self.email = email
        self.avatarUrl = avatarUrl
        self.isPro = isPro
        self.authProvider = authProvider
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.freeQuota = freeQuota
        self.apiProvider = apiProvider
        self.totalQuotaUsed = totalQuotaUsed
        self.subscriptionTier = subscriptionTier
    }
}

