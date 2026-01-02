import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case encodingError(Error)
    case unauthorized(message: String?)
    case tokenExpired
    case invalidAPIKey
    case generationFailed(String)
    case timeout
    case serverError(message: String?)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .invalidResponse:
            return "无效的响应"
        case .httpError(let statusCode, let message):
            return "HTTP 错误 (\(statusCode)): \(message ?? "未知错误")"
        case .decodingError(let error):
            return "数据解析错误: \(error.localizedDescription)"
        case .encodingError(let error):
            return "数据编码错误: \(error.localizedDescription)"
        case .unauthorized(let message):
            return "未授权: \(message ?? "请重新登录")"
        case .tokenExpired:
            return "Token 已过期，正在刷新..."
        case .invalidAPIKey:
            return "API Key 未配置，请在设置中添加 API Key"
        case .generationFailed(let message):
            return "生成失败: \(message)"
        case .timeout:
            return "生成超时，请稍后重试"
        case .serverError(let message):
            return "服务器错误: \(message ?? "请稍后重试")"
        case .unknown:
            return "未知错误"
        }
    }
}