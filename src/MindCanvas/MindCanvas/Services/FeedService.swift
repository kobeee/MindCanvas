import Foundation

/// 真实 Feed 服务
/// 对接后端 API
@MainActor
final class FeedService {
    static let shared = FeedService()

    private let apiClient = APIClient.shared

    private init() {}

    // MARK: - 获取动态列表

    func fetchFeed(page: Int = 0, sort: String = "latest") async throws -> [FeedItem] {
        // 后端页码从 1 开始，iOS 端从 0 开始
        let backendPage = page + 1

        let response: FeedListResponse = try await apiClient.request(
            endpoint: "/api/v1/feed?page=\(backendPage)&size=20&sort=\(sort)",
            method: .GET,
            requiresAuth: false,
            responseType: FeedListResponse.self
        )

        return response.items.map { item in
            FeedItem(
                id: item.id.uuidString,
                imageUrl: item.asset?.url ?? "",
                thumbnailUrl: item.asset?.url ?? "",
                author: User(
                    id: item.user?.id.uuidString ?? "",
                    username: item.user?.username ?? "未知用户",
                    email: item.user?.email ?? "",
                    avatarUrl: item.user?.avatarUrl,
                    isPro: false
                ),
                prompt: item.asset?.prompt,
                showPrompt: true,
                likesCount: item.likesCount,
                createdAt: item.publishedAt,
                isLiked: false
            )
        }
    }

    // MARK: - 点赞/取消点赞

    func likeImage(id: String) async throws {
        _ = try await apiClient.request(
            endpoint: "/api/v1/feed/\(id)/like",
            method: .POST,
            requiresAuth: false,
            responseType: SuccessResponse.self
        )
    }

    func unlikeImage(id: String) async throws {
        // 后端没有取消点赞接口，暂时使用点赞接口
        // TODO: 后续需要后端添加取消点赞接口
        _ = try await apiClient.request(
            endpoint: "/api/v1/feed/\(id)/like",
            method: .POST,
            requiresAuth: false,
            responseType: SuccessResponse.self
        )
    }

    // MARK: - 发布图片

    func publishImage(imageUrl: String, title: String, prompt: String?, showPrompt: Bool) async throws {
        // 注意：后端发布接口需要 asset_id，而不是 imageUrl
        // 这里需要先通过 imageUrl 查找对应的 asset_id，或者上传图片到后端
        // 暂时使用 Mock 数据，后续需要实现完整的上传和发布流程

        // TODO: 实现完整的上传和发布流程
        // 1. 上传图片到后端，获取 asset_id
        // 2. 使用 asset_id 发布到社区

        print("发布图片: \(imageUrl), 标题: \(title)")
    }
}

// MARK: - 后端响应模型

struct FeedListResponse: Codable {
    let total: Int
    let page: Int
    let size: Int
    let items: [FeedItemResponse]
}

struct FeedItemResponse: Codable {
    let id: UUID
    let assetId: UUID
    let userId: UUID
    let title: String?
    let likesCount: Int
    let publishedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let asset: AssetResponse?
    let user: UserResponse?

    enum CodingKeys: String, CodingKey {
        case id
        case assetId = "asset_id"
        case userId = "user_id"
        case title
        case likesCount = "likes_count"
        case publishedAt = "published_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case asset
        case user
    }
}

struct AssetResponse: Codable {
    let id: UUID
    let url: String
    let type: String
    let prompt: String?
    let modelVersion: String?
    let isPublic: Bool
    let userId: UUID
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case type
        case prompt
        case modelVersion = "model_version"
        case isPublic = "is_public"
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct UserResponse: Codable {
    let id: UUID
    let email: String
    let username: String?
    let avatarUrl: String?
    let authProvider: String
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case username
        case avatarUrl = "avatar_url"
        case authProvider = "auth_provider"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SuccessResponse: Codable {
    let success: Bool
    let message: String
}