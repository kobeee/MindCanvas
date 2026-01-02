import Foundation

@MainActor
final class TokenManager {
    static let shared = TokenManager()

    private let keychainManager = KeychainManager.shared
    private let baseURL = "http://localhost:8008"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    private enum Keys {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let tokenExpiresAt = "token_expires_at"
    }

    func saveToken(_ token: Token) {
        keychainManager.save(Keys.accessToken, value: token.accessToken)
        keychainManager.save(Keys.refreshToken, value: token.refreshToken)
        keychainManager.save(Keys.tokenExpiresAt, value: ISO8601DateFormatter().string(from: token.expiresAt))
    }

    func getAccessToken() throws -> String {
        guard let token = keychainManager.get(Keys.accessToken) else {
            throw APIError.unauthorized(message: "未找到 Access Token")
        }
        return token
    }

    func getRefreshToken() throws -> String {
        guard let token = keychainManager.get(Keys.refreshToken) else {
            throw APIError.unauthorized(message: "未找到 Refresh Token")
        }
        return token
    }

    func getTokenExpiresAt() throws -> Date {
        guard let dateString = keychainManager.get(Keys.tokenExpiresAt),
              let date = ISO8601DateFormatter().date(from: dateString) else {
            throw APIError.unauthorized(message: "未找到 Token 过期时间")
        }
        return date
    }

    func isTokenExpired() -> Bool {
        do {
            let expiresAt = try getTokenExpiresAt()
            return Date() >= expiresAt
        } catch {
            return true
        }
    }

    func isTokenExpiringSoon() -> Bool {
        do {
            let expiresAt = try getTokenExpiresAt()
            let fiveMinutes: TimeInterval = 300
            return Date().addingTimeInterval(fiveMinutes) >= expiresAt
        } catch {
            return true
        }
    }

    func clearTokens() {
        keychainManager.delete(Keys.accessToken)
        keychainManager.delete(Keys.refreshToken)
        keychainManager.delete(Keys.tokenExpiresAt)
    }

    func refreshAccessToken() async throws -> Bool {
        print("🔄 开始刷新 token...")

        do {
            let refreshToken = try getRefreshToken()

            guard let url = URL(string: baseURL + "/api/v1/auth/refresh") else {
                print("❌ Token 刷新失败: 无效的 URL")
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = RefreshTokenRequest(refreshToken: refreshToken)
            request.httpBody = try JSONEncoder().encode(body)

            print("📤 刷新 token 请求: POST \(url.absoluteString)")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ Token 刷新失败: 无效的响应")
                throw APIError.invalidResponse
            }

            print("📡 刷新 token 响应状态码: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                print("❌ Token 刷新失败: HTTP \(httpResponse.statusCode)")
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
            }

            let tokenResponse = try JSONDecoder().decode(RefreshTokenResponse.self, from: data)

            keychainManager.save(Keys.accessToken, value: tokenResponse.accessToken)

            let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            keychainManager.save(Keys.tokenExpiresAt, value: ISO8601DateFormatter().string(from: expiresAt))

            print("✅ Token 刷新成功，新的 access token: \(String(tokenResponse.accessToken.prefix(20)))...")

            return true
        } catch {
            // 只在 token 无效时清除 token，网络错误等临时性问题不清除
            if case APIError.httpError(let statusCode, _) = error,
               statusCode == 401 {
                print("❌ Token 无效，清除所有 token")
                clearTokens()
            } else {
                print("❌ Token 刷新失败（临时性错误，不清除 token）: \(error)")
            }
            return false
        }
    }

    func ensureValidToken() async throws -> String {
        if isTokenExpiringSoon() {
            let success = try await refreshAccessToken()
            if !success {
                throw APIError.tokenExpired
            }
        }

        return try getAccessToken()
    }
}