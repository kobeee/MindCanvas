import Foundation

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    private let baseURL: String
    private let session: URLSession
    private let tokenManager = TokenManager.shared
    private let decoder: JSONDecoder

    private init() {
        self.baseURL = "http://localhost:8008"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        // 自定义 JSONDecoder，支持 ISO8601 带微秒的日期格式
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            return dateFormatter.date(from: dateString) ?? Date()
        }
    }

    private func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        requiresAuth: Bool = false,
        responseType: T.Type,
        retryCount: Int = 0
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth {
            let token = try await tokenManager.getAccessToken()
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            urlRequest.httpBody = try JSONEncoder().encode(body)
        }

        print("🌐 API 请求: \(method.rawValue) \(baseURL + endpoint)")

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("📡 响应状态码: \(httpResponse.statusCode)")

        if let responseString = String(data: data, encoding: .utf8) {
            print("📦 响应数据: \(responseString)")
        }

        if httpResponse.statusCode == 401 && requiresAuth && retryCount == 0 {
            if try await tokenManager.refreshAccessToken() {
                return try await request(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    requiresAuth: true,
                    responseType: responseType,
                    retryCount: retryCount + 1
                )
            } else {
                throw APIError.tokenExpired
            }
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw APIError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorMessage?.message
            )
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("❌ 解码错误: \(error)")
            throw APIError.decodingError(error)
        }
    }

    func login(provider: String, token: String) async throws -> Token {
        return try await request(
            endpoint: "/api/v1/auth/login",
            method: .POST,
            body: LoginRequest(provider: provider, token: token),
            requiresAuth: false,
            responseType: Token.self
        )
    }

    func sendVerificationCode(email: String) async throws -> SendVerificationCodeResponse {
        return try await request(
            endpoint: "/api/v1/auth/send-verification-code",
            method: .POST,
            body: SendVerificationCodeRequest(email: email),
            requiresAuth: false,
            responseType: SendVerificationCodeResponse.self
        )
    }

    func verifyEmail(email: String, code: String) async throws -> Token {
        return try await request(
            endpoint: "/api/v1/auth/verify-email",
            method: .POST,
            body: VerifyEmailRequest(email: email, code: code),
            requiresAuth: false,
            responseType: Token.self
        )
    }

    func refreshAccessToken(refreshToken: String) async throws -> RefreshTokenResponse {
        return try await request(
            endpoint: "/api/v1/auth/refresh",
            method: .POST,
            body: RefreshTokenRequest(refreshToken: refreshToken),
            requiresAuth: false,
            responseType: RefreshTokenResponse.self
        )
    }

    func getCurrentUser() async throws -> User {
        return try await request(
            endpoint: "/api/v1/auth/me",
            method: .GET,
            requiresAuth: true,
            responseType: User.self
        )
    }

    func logout() async throws {
        _ = try await request(
            endpoint: "/api/v1/auth/logout",
            method: .POST,
            requiresAuth: true,
            responseType: [String: String].self
        )
    }
}