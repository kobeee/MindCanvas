import Foundation

struct QuotaInfo: Codable {
    let apiProvider: String
    let hasFreeQuota: Bool
    let maxQuota: Int
    let usedQuota: Int
    let remainingQuota: Int
    let subscriptionTier: String
    
    enum CodingKeys: String, CodingKey {
        case apiProvider = "api_provider"
        case hasFreeQuota = "has_free_quota"
        case maxQuota = "max_quota"
        case usedQuota = "used_quota"
        case remainingQuota = "remaining_quota"
        case subscriptionTier = "subscription_tier"
    }
}

@MainActor
final class QuotaService {
    static let shared = QuotaService()
    
    private init() {}
    
    func fetchQuota() async throws -> QuotaInfo {
        return try await APIClient.shared.request(
            endpoint: "/api/v1/users/me/quota",
            method: .GET,
            requiresAuth: true,
            responseType: QuotaInfo.self
        )
    }
}