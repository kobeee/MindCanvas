import Foundation

@MainActor
final class TokenManager {
    static let shared = TokenManager()

    private let keychainManager = KeychainManager.shared
    private let baseURL = "https://mindcanvas.escapemobius.cc"
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
        let accessSaved = keychainManager.save(Keys.accessToken, value: token.accessToken)
        let refreshSaved = keychainManager.save(Keys.refreshToken, value: token.refreshToken)
        let expiresSaved = keychainManager.save(Keys.tokenExpiresAt, value: ISO8601DateFormatter().string(from: token.expiresAt))

        print("[TokenManager] saveToken - 保存结果: access=\(accessSaved), refresh=\(refreshSaved), expires=\(expiresSaved)")
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
        print("[TokenManager] clearTokens - 开始清理token")

        let accessDeleted = keychainManager.delete(Keys.accessToken)
        let refreshDeleted = keychainManager.delete(Keys.refreshToken)
        let expiresDeleted = keychainManager.delete(Keys.tokenExpiresAt)

        print("[TokenManager] clearTokens - 删除结果: access=\(accessDeleted), refresh=\(refreshDeleted), expires=\(expiresDeleted)")

        // 验证删除是否成功
        let accessExists = keychainManager.get(Keys.accessToken) != nil
        let refreshExists = keychainManager.get(Keys.refreshToken) != nil
        let expiresExists = keychainManager.get(Keys.tokenExpiresAt) != nil

        if accessExists || refreshExists || expiresExists {
            print("[TokenManager] WARNING: Token清理不完整！")
            print("[TokenManager]  access_token仍存在: \(accessExists)")
            print("[TokenManager]  refresh_token仍存在: \(refreshExists)")
            print("[TokenManager]  token_expires_at仍存在: \(expiresExists)")

            // 重试一次
            print("[TokenManager] 重试清理...")
            _ = keychainManager.delete(Keys.accessToken)
            _ = keychainManager.delete(Keys.refreshToken)
            _ = keychainManager.delete(Keys.tokenExpiresAt)

            // 再次验证
            let accessExists2 = keychainManager.get(Keys.accessToken) != nil
            let refreshExists2 = keychainManager.get(Keys.refreshToken) != nil
            if accessExists2 || refreshExists2 {
                print("[TokenManager] ERROR: Token清理失败，即使重试后仍有残留！")
            } else {
                print("[TokenManager] Token清理在重试后成功")
            }
        } else {
            print("[TokenManager] Token清理成功")
        }
    }

    func refreshAccessToken() async throws -> Bool {
        do {
            let refreshToken = try getRefreshToken()

            guard let url = URL(string: baseURL + "/api/v1/auth/refresh") else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = RefreshTokenRequest(refreshToken: refreshToken)
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.httpError(statusCode: httpResponse.statusCode, message: nil)
            }

            let tokenResponse = try JSONDecoder().decode(RefreshTokenResponse.self, from: data)

            keychainManager.save(Keys.accessToken, value: tokenResponse.accessToken)

            let expiresAt = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            keychainManager.save(Keys.tokenExpiresAt, value: ISO8601DateFormatter().string(from: expiresAt))

            return true
        } catch {
            if case APIError.httpError(let statusCode, _) = error,
               statusCode == 401 {
                clearTokens()
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