import Foundation

/// 真实图像生成服务
/// 对接后端 API，使用 RSA 加密传输 API Key
@MainActor
final class RealGenerationService {
    static let shared = RealGenerationService()
    
    private let rsaService = RSAEncryptionService.shared
    private let apiClient = APIClient.shared
    
    private init() {}
    
    func generate(request: GenerationRequest, useFreeQuota: Bool = false) async throws -> GenerationResponse {
        let encryptedApiKey: String
        
        if useFreeQuota {
            // 使用免费额度，不加密 API Key
            encryptedApiKey = ""
        } else {
            // 从 Keychain 获取 API Key
            guard let apiKey = KeychainManager.shared.getAPIKey() else {
                throw APIError.invalidAPIKey
            }
            
            // 使用 RSA 公钥加密 API Key
            encryptedApiKey = try await rsaService.encrypt(apiKey)
        }
        
        // 构建请求
        let generationRequest = GenerationTaskCreate(
            encryptedApiKey: encryptedApiKey,
            prompt: request.prompt,
            baseImage: request.imageBase64
        )
        
        // 调用后端 API
        // 如果使用免费额度，需要认证（用户已登录）；如果不使用免费额度，不需要认证（使用自己的API Key）
        let response: TaskResponse = try await apiClient.request(
            endpoint: "/api/v1/generate/tasks",
            method: .POST,
            body: generationRequest,
            requiresAuth: useFreeQuota,
            responseType: TaskResponse.self
        )
        
        // 轮询任务状态
        return try await pollTaskStatus(taskId: response.id)
    }
    
    func uploadImage(_ imageData: Data) async throws -> String {
        // 图生图场景下，上传参考图到后端
        let base64Image = imageData.base64EncodedString()
        return base64Image
    }
    
    /// 轮询任务状态，直到任务完成或超时
    /// - Parameters:
    ///   - taskId: 任务 ID
    ///   - maxAttempts: 最大轮询次数，默认 200 次（约 200 秒）
    /// - Returns: 生成响应
    /// - Throws: APIError.timeout 或其他错误
    private func pollTaskStatus(taskId: String, maxAttempts: Int = 200) async throws -> GenerationResponse {
        var attempts = 0
        
        while attempts < maxAttempts {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 秒
            
            let statusResponse: TaskStatusResponse = try await apiClient.request(
                endpoint: "/api/v1/generate/tasks/\(taskId)/status",
                method: .GET,
                requiresAuth: false,
                responseType: TaskStatusResponse.self
            )
            
            switch statusResponse.status {
            case "completed":
                guard let imageUrl = statusResponse.imageUrl else {
                    throw APIError.generationFailed("生成完成但无图片 URL")
                }
                
                return GenerationResponse(
                    id: taskId,
                    imageUrl: imageUrl,
                    thumbnailUrl: imageUrl,
                    prompt: "" // 后端返回不包含 prompt
                )
                
            case "failed":
                throw APIError.generationFailed(statusResponse.errorMessage ?? "未知错误")
                
            case "pending", "processing":
                attempts += 1
                continue
                
            default:
                attempts += 1
                continue
            }
        }
        
        throw APIError.timeout
    }
}

// MARK: - 请求/响应模型

struct GenerationTaskCreate: Codable {
    let encryptedApiKey: String
    let prompt: String
    let baseImage: String?
    
    enum CodingKeys: String, CodingKey {
        case encryptedApiKey = "encrypted_api_key"
        case prompt
        case baseImage = "base_image"
    }
}

struct TaskResponse: Codable {
    let id: String
    let userId: UUID?
    let prompt: String?
    let status: String
    let imageUrl: String?
    let errorMessage: String?
    let createdAt: Date?
    let updatedAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case prompt
        case status
        case imageUrl = "image_url"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TaskStatusResponse: Codable {
    let taskId: String
    let status: String
    let imageUrl: String?
    let errorMessage: String?
    
    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case status
        case imageUrl = "image_url"
        case errorMessage = "error_message"
    }
}