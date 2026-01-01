# iOS 登录功能后端适配改造方案

**文档版本**: v1.0
**创建日期**: 2025-12-28
**目标**: 将 iOS APP 的登录功能从 Mock 服务迁移到真实后端服务

---

## 一、概述

### 1.1 背景

当前 iOS APP 的登录功能完全基于 Mock 服务实现，包括：
- Apple Sign In（Mock）
- Google Sign In（Mock）
- GitHub OAuth（Mock）
- 邮箱验证码登录（Mock）

后端服务已实现完整的认证系统，包括：
- JWT Token 机制（Access Token + Refresh Token）
- 第三方登录支持（Apple、Google、GitHub）
- 邮箱验证码登录
- Token 自动刷新机制

### 1.2 目标

将 iOS 登录功能从 Mock 服务迁移到真实后端服务，实现：
- ✅ 真实的第三方登录集成
- ✅ 完整的 Token 管理机制
- ✅ 自动 Token 刷新
- ✅ 安全的 Token 存储
- ✅ 优雅的错误处理
- ✅ 保持 UI 一致性和用户体验

### 1.3 技术栈

**iOS 端**:
- Swift 5.9+
- SwiftUI
- AuthenticationServices（Apple Sign In）
- GoogleSignIn SDK（Google Sign In）
- ASWebAuthenticationSession（GitHub OAuth）
- Keychain（安全存储）

**后端服务**:
- FastAPI
- JWT（python-jose）
- Redis（验证码存储）
- PostgreSQL

---

## 二、后端 API 接口分析

### 2.1 认证接口

#### 2.1.1 第三方登录
```http
POST /api/v1/auth/login
Content-Type: application/json

{
  "provider": "apple|google|github",
  "token": "identity_token|id_token|access_token"
}

Response:
{
  "access_token": "jwt_token",
  "refresh_token": "refresh_token_string",
  "token_type": "bearer",
  "expires_in": 604800,
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "username": "username",
    "avatar_url": "https://...",
    "auth_provider": "apple",
    "created_at": "2025-12-28T00:00:00Z",
    "updated_at": "2025-12-28T00:00:00Z"
  }
}
```

#### 2.1.2 发送验证码
```http
POST /api/v1/auth/send-verification-code
Content-Type: application/json

{
  "email": "user@example.com"
}

Response:
{
  "message": "Verification code sent successfully",
  "expires_in": 300
}
```

#### 2.1.3 验证邮箱并登录
```http
POST /api/v1/auth/verify-email
Content-Type: application/json

{
  "email": "user@example.com",
  "code": "123456"
}

Response:
{
  "access_token": "jwt_token",
  "refresh_token": "refresh_token_string",
  "token_type": "bearer",
  "expires_in": 604800,
  "user": { ... }
}
```

#### 2.1.4 刷新 Access Token
```http
POST /api/v1/auth/refresh
Content-Type: application/json

{
  "refresh_token": "refresh_token_string"
}

Response:
{
  "access_token": "new_jwt_token",
  "token_type": "bearer",
  "expires_in": 604800
}
```

#### 2.1.5 获取当前用户信息
```http
GET /api/v1/auth/me
Authorization: Bearer <access_token>

Response:
{
  "id": "uuid",
  "email": "user@example.com",
  "username": "username",
  "avatar_url": "https://...",
  "auth_provider": "apple",
  "created_at": "2025-12-28T00:00:00Z",
  "updated_at": "2025-12-28T00:00:00Z"
}
```

#### 2.1.6 登出
```http
POST /api/v1/auth/logout
Authorization: Bearer <access_token>

Response:
{
  "message": "Logged out successfully"
}
```

### 2.2 Token 机制

**Access Token**:
- 类型: JWT
- 有效期: 7 天（604800 秒）
- 用途: 访问受保护的 API 资源
- 存储: Keychain
- 刷新: 使用 Refresh Token 自动刷新

**Refresh Token**:
- 类型: 随机字符串
- 有效期: 30 天
- 用途: 刷新 Access Token
- 存储: Keychain
- 过期: 需要重新登录

---

## 三、当前 iOS 端实现分析

### 3.1 架构分析

**当前架构**:
```
LoginView (UI)
    ↓
AuthManager (认证管理)
    ↓
MockAuthService (Mock 服务)
    ↓
KeychainManager (Token 存储)
```

**问题**:
- MockAuthService 完全模拟，不调用真实 API
- 没有 Token 刷新机制
- User 模型字段不完整
- 没有网络错误处理
- 没有第三方登录的真实集成

### 3.2 文件清单

| 文件 | 路径 | 说明 |
|-----|------|-----|
| LoginView | Views/Auth/LoginView.swift | 登录 UI |
| AuthManager | Managers/AuthManager.swift | 认证管理器 |
| MockAuthService | Services/MockAuthService.swift | Mock 服务 |
| User | Models/User.swift | 用户模型 |
| KeychainManager | Infrastructure/KeychainManager.swift | Keychain 存储 |
| MindCanvasApp | MindCanvasApp.swift | 应用入口 |

### 3.3 当前 User 模型

```swift
struct User: Codable, Identifiable {
    let id: String
    let username: String
    let email: String?
    let avatarUrl: String?
    let isPro: Bool
}
```

**问题**:
- 缺少 `auth_provider` 字段
- 缺少 `created_at` 和 `updated_at` 字段
- `isPro` 字段后端未提供
- 字段命名不一致（后端使用 snake_case，iOS 使用 camelCase）

---

## 四、改造方案

### 4.1 总体架构设计

**新架构**:
```
LoginView (UI)
    ↓
AuthManager (认证管理)
    ↓
AuthService (真实服务)
    ├─ APIClient (网络层)
    ├─ TokenManager (Token 管理)
    ├─ AppleSignInManager (Apple 登录)
    ├─ GoogleSignInManager (Google 登录)
    └─ GitHubOAuthManager (GitHub 登录)
    ↓
KeychainManager (安全存储)
```

### 4.2 数据模型改造

#### 4.2.1 User 模型扩展

**文件**: `Models/User.swift`

```swift
import Foundation

struct User: Codable, Identifiable {
    let id: String
    let username: String
    let email: String?
    let avatarUrl: String?
    let authProvider: String
    let createdAt: Date
    let updatedAt: Date
    
    // 后端未提供，暂时保留用于 UI
    var isPro: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case email
        case avatarUrl = "avatar_url"
        case authProvider = "auth_provider"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
```

#### 4.2.2 Token 模型

**新文件**: `Models/Token.swift`

```swift
import Foundation

struct Token: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: User
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case user
    }
    
    /// 计算过期时间
    var expiresAt: Date {
        return Date().addingTimeInterval(TimeInterval(expiresIn))
    }
    
    /// 检查是否即将过期（5分钟内）
    var isExpiringSoon: Bool {
        let fiveMinutes: TimeInterval = 300
        return Date().addingTimeInterval(fiveMinutes) >= expiresAt
    }
}
```

#### 4.2.3 API 请求/响应模型

**新文件**: `Models/APIModels.swift`

```swift
import Foundation

// MARK: - 登录请求
struct LoginRequest: Codable {
    let provider: String
    let token: String
}

// MARK: - 发送验证码请求
struct SendVerificationCodeRequest: Codable {
    let email: String
}

// MARK: - 验证邮箱请求
struct VerifyEmailRequest: Codable {
    let email: String
    let code: String
}

// MARK: - 刷新 Token 请求
struct RefreshTokenRequest: Codable {
    let refreshToken: String
    
    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

// MARK: - 刷新 Token 响应
struct RefreshTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }
}

// MARK: - 通用错误响应
struct ErrorResponse: Codable {
    let error: String?
    let message: String?
    let details: [String: String]?
}
```

### 4.3 网络层改造

#### 4.3.1 API 错误定义

**新文件**: `Services/APIError.swift`

```swift
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
        case .serverError(let message):
            return "服务器错误: \(message ?? "请稍后重试")"
        case .unknown:
            return "未知错误"
        }
    }
}
```

#### 4.3.2 API 客户端

**新文件**: `Services/APIClient.swift`

```swift
import Foundation

@MainActor
final class APIClient {
    static let shared = APIClient()
    
    private let baseURL: String
    private let session: URLSession
    private let tokenManager = TokenManager.shared
    
    private init() {
        // 从配置文件读取，或使用环境变量
        self.baseURL = "http://localhost:8000"
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }
    
    // MARK: - 通用请求方法
    
    private func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        requiresAuth: Bool = false,
        responseType: T.Type
    ) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 添加认证 Token
        if requiresAuth {
            if let token = try? await tokenManager.getAccessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }
        
        // 添加请求体
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        // 发送请求
        let (data, response) = try await session.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        // 处理 401 错误（Token 过期）
        if httpResponse.statusCode == 401 && requiresAuth {
            // 尝试刷新 Token
            if try await tokenManager.refreshAccessToken() {
                // 重试请求
                return try await request(
                    endpoint: endpoint,
                    method: method,
                    body: body,
                    requiresAuth: true,
                    responseType: responseType
                )
            } else {
                throw APIError.tokenExpired
            }
        }
        
        // 处理其他 HTTP 错误
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw APIError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorMessage?.message
            )
        }
        
        // 解析响应
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
    
    // MARK: - 认证接口
    
    func login(provider: String, token: String) async throws -> Token {
        return try await request(
            endpoint: "/api/v1/auth/login",
            method: .POST,
            body: LoginRequest(provider: provider, token: token),
            requiresAuth: false,
            responseType: Token.self
        )
    }
    
    func sendVerificationCode(email: String) async throws {
        _ = try await request(
            endpoint: "/api/v1/auth/send-verification-code",
            method: .POST,
            body: SendVerificationCodeRequest(email: email),
            requiresAuth: false,
            responseType: [String: String].self
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

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
}
```

### 4.4 Token 管理改造

#### 4.4.1 Token 管理器

**新文件**: `Services/TokenManager.swift`

```swift
import Foundation

@MainActor
final class TokenManager {
    static let shared = TokenManager()
    
    private let keychainManager = KeychainManager.shared
    private let apiClient = APIClient.shared
    
    private init() {}
    
    // MARK: - Token 存储 Key
    
    private enum Keys {
        static let accessToken = "access_token"
        static let refreshToken = "refresh_token"
        static let tokenExpiresAt = "token_expires_at"
    }
    
    // MARK: - Token 操作
    
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
    
    // MARK: - Token 刷新
    
    func refreshAccessToken() async throws -> Bool {
        do {
            let refreshToken = try getRefreshToken()
            let response = try await apiClient.refreshAccessToken(refreshToken: refreshToken)
            
            // 更新 Access Token
            keychainManager.save(Keys.accessToken, value: response.accessToken)
            
            // 更新过期时间
            let expiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
            keychainManager.save(Keys.tokenExpiresAt, value: ISO8601DateFormatter().string(from: expiresAt))
            
            return true
        } catch {
            // Refresh Token 也过期了，清除所有 Token
            clearTokens()
            return false
        }
    }
    
    // MARK: - 自动刷新
    
    func ensureValidToken() async throws -> String {
        // 如果 Token 即将过期，自动刷新
        if isTokenExpiringSoon() {
            let success = try await refreshAccessToken()
            if !success {
                throw APIError.tokenExpired
            }
        }
        
        return try getAccessToken()
    }
}
```

#### 4.4.2 KeychainManager 扩展

**修改文件**: `Infrastructure/KeychainManager.swift`

```swift
extension KeychainManager {
    // MARK: - 通用存储方法
    
    func save(_ key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
```

### 4.5 第三方登录集成

#### 4.5.1 Apple Sign In Manager

**新文件**: `Services/AppleSignInManager.swift`

```swift
import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
final class AppleSignInManager: NSObject, ObservableObject {
    static let shared = AppleSignInManager()
    
    private var continuation: CheckedContinuation<String, Error>?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Nonce 生成
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    // MARK: - 登录
    
    func signIn() async throws -> String {
        let nonce = randomNonceString()
        let nonceSha256 = sha256(nonce)
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = nonceSha256
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInManager: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let identityToken = appleIDCredential.identityToken else {
                continuation?.resume(throwing: APIError.unknown)
                return
            }
            
            let tokenString = String(data: identityToken, encoding: .utf8)!
            continuation?.resume(returning: tokenString)
        }
    }
    
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("无法找到窗口")
        }
        return window
    }
}
```

#### 4.5.2 Google Sign In Manager

**新文件**: `Services/GoogleSignInManager.swift`

```swift
import Foundation
import GoogleSignIn

@MainActor
final class GoogleSignInManager: NSObject, ObservableObject {
    static let shared = GoogleSignInManager()
    
    private var continuation: CheckedContinuation<String, Error>?
    
    private override init() {
        super.init()
    }
    
    // MARK: - 配置
    
    func configure() {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            fatalError("GIDClientID 未在 Info.plist 中配置")
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
    }
    
    // MARK: - 登录
    
    func signIn() async throws -> String {
        guard let rootViewController = getRootViewController() else {
            throw APIError.unknown
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let idToken = result?.user.idToken?.tokenString else {
                    continuation.resume(throwing: APIError.unknown)
                    return
                }
                
                continuation.resume(returning: idToken)
            }
        }
    }
    
    // MARK: - 工具方法
    
    private func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }
        return window.rootViewController
    }
}
```

#### 4.5.3 GitHub OAuth Manager

**新文件**: `Services/GitHubOAuthManager.swift`

```swift
import Foundation
import AuthenticationServices

@MainActor
final class GitHubOAuthManager: NSObject, ObservableObject {
    static let shared = GitHubOAuthManager()
    
    private var continuation: CheckedContinuation<String, Error>?
    
    private let clientID: String
    private let clientSecret: String
    private let redirectURI: String
    
    private override init() {
        // 从配置文件读取
        self.clientID = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String ?? ""
        self.clientSecret = Bundle.main.object(forInfoDictionaryKey: "GitHubClientSecret") as? String ?? ""
        self.redirectURI = "mindcanvas://auth"
        super.init()
    }
    
    // MARK: - 登录
    
    func signIn() async throws -> String {
        // 1. 发起 OAuth 授权请求
        let state = UUID().uuidString
        let authURL = buildAuthURL(state: state)
        
        // 2. 使用 ASWebAuthenticationSession 打开授权页面
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: redirectURI
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: APIError.unknown)
                    return
                }
                
                // 3. 解析回调 URL，提取授权码
                guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let queryItems = components.queryItems,
                      let code = queryItems.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: APIError.unknown)
                    return
                }
                
                // 4. 交换授权码获取 Access Token
                Task {
                    do {
                        let accessToken = try await self.exchangeCodeForToken(code: code)
                        continuation.resume(returning: accessToken)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            session.start()
        }
    }
    
    // MARK: - 构建 OAuth 授权 URL
    
    private func buildAuthURL(state: String) -> URL {
        var components = URLComponents(string: "https://github.com/login/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "read:user user:email"),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }
    
    // MARK: - 交换授权码获取 Access Token
    
    private func exchangeCodeForToken(code: String) async throws -> String {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code
        ]
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        let response = try JSONDecoder().decode(GitHubTokenResponse.self, from: data)
        return response.accessToken
    }
}

// MARK: - GitHub Token Response

struct GitHubTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope = "scope"
    }
}

// MARK: - ASWebAuthenticationSessionPresentationContextProviding

extension GitHubOAuthManager: ASWebAuthenticationSessionPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("无法找到窗口")
        }
        return window
    }
}
```

### 4.6 认证服务改造

#### 4.6.1 AuthService

**新文件**: `Services/AuthService.swift`

```swift
import Foundation

@MainActor
final class AuthService {
    static let shared = AuthService()
    
    private let apiClient = APIClient.shared
    private let tokenManager = TokenManager.shared
    private let appleSignInManager = AppleSignInManager.shared
    private let googleSignInManager = GoogleSignInManager.shared
    private let gitHubOAuthManager = GitHubOAuthManager.shared
    
    private init() {}
    
    // MARK: - 第三方登录
    
    func loginWithApple() async throws -> Token {
        // 1. 获取 Apple Identity Token
        let identityToken = try await appleSignInManager.signIn()
        
        // 2. 调用后端登录接口
        let token = try await apiClient.login(provider: "apple", token: identityToken)
        
        // 3. 保存 Token
        tokenManager.saveToken(token)
        
        return token
    }
    
    func loginWithGoogle() async throws -> Token {
        // 1. 获取 Google ID Token
        let idToken = try await googleSignInManager.signIn()
        
        // 2. 调用后端登录接口
        let token = try await apiClient.login(provider: "google", token: idToken)
        
        // 3. 保存 Token
        tokenManager.saveToken(token)
        
        return token
    }
    
    func loginWithGithub() async throws -> Token {
        // 1. 获取 GitHub Access Token
        let accessToken = try await gitHubOAuthManager.signIn()
        
        // 2. 调用后端登录接口
        let token = try await apiClient.login(provider: "github", token: accessToken)
        
        // 3. 保存 Token
        tokenManager.saveToken(token)
        
        return token
    }
    
    // MARK: - 邮箱登录
    
    func sendVerificationCode(to email: String) async throws {
        try await apiClient.sendVerificationCode(email: email)
    }
    
    func loginWithEmail(email: String, code: String) async throws -> Token {
        // 1. 调用后端验证接口
        let token = try await apiClient.verifyEmail(email: email, code: code)
        
        // 2. 保存 Token
        tokenManager.saveToken(token)
        
        return token
    }
    
    // MARK: - Token 管理
    
    func getCurrentUser() async throws -> User {
        // 确保Token有效
        _ = try await tokenManager.ensureValidToken()
        
        return try await apiClient.getCurrentUser()
    }
    
    func logout() async throws {
        // 1. 调用后端登出接口
        try? await apiClient.logout()
        
        // 2. 清除本地 Token
        tokenManager.clearTokens()
    }
    
    func refreshToken() async throws -> Bool {
        return try await tokenManager.refreshAccessToken()
    }
    
    // MARK: - 认证状态检查
    
    func isAuthenticated() -> Bool {
        do {
            return !tokenManager.isTokenExpired()
        } catch {
            return false
        }
    }
}
```

### 4.7 AuthManager 改造

**修改文件**: `Managers/AuthManager.swift`

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AuthManager {
    static let shared = AuthManager()
    
    private(set) var isAuthenticated = false
    private(set) var currentUser: User?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    
    private let authService = AuthService.shared
    
    private init() {
        checkAuthentication()
    }
    
    // MARK: - 认证状态检查
    
    func checkAuthentication() {
        isAuthenticated = authService.isAuthenticated()
        
        if isAuthenticated {
            // 异步加载用户信息
            Task {
                await loadCurrentUser()
            }
        } else {
            currentUser = nil
        }
    }
    
    private func loadCurrentUser() async {
        do {
            currentUser = try await authService.getCurrentUser()
        } catch {
            print("加载用户信息失败: \(error)")
            isAuthenticated = false
        }
    }
    
    // MARK: - 登录
    
    func loginWithApple() async {
        await performLogin {
            try await authService.loginWithApple()
        }
    }
    
    func loginWithGoogle() async {
        await performLogin {
            try await authService.loginWithGoogle()
        }
    }
    
    func loginWithGithub() async {
        await performLogin {
            try await authService.loginWithGithub()
        }
    }
    
    func loginWithEmail(_ email: String, code: String) async {
        await performLogin {
            try await authService.loginWithEmail(email: email, code: code)
        }
    }
    
    private func performLogin(_ loginAction: () async throws -> Token) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let token = try await loginAction()
            currentUser = token.user
            isAuthenticated = true
        } catch {
            errorMessage = "登录失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - 发送验证码
    
    func sendVerificationCode(to email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await authService.sendVerificationCode(to: email)
        } catch {
            errorMessage = "发送验证码失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - 登出
    
    func logout() async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await authService.logout()
            currentUser = nil
            isAuthenticated = false
        } catch {
            errorMessage = "登出失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - 刷新 Token
    
    func refreshToken() async {
        do {
            let success = try await authService.refreshToken()
            if !success {
                // Refresh Token 也过期了，需要重新登录
                logout()
            }
        } catch {
            print("刷新 Token 失败: \(error)")
        }
    }
}
```

### 4.8 UI 层改造

#### 4.8.1 LoginView 改造

**修改文件**: `Views/Auth/LoginView.swift`

主要修改点：
1. 将 MockAuthService 调用改为 AuthService
2. 保持 UI 不变，只修改底层逻辑
3. 添加更友好的错误提示

```swift
// 修改前
try await MockAuthService.shared.sendVerificationCode(to: email)

// 修改后
try await authManager.sendVerificationCode(to: email)
```

#### 4.8.2 应用启动时初始化

**修改文件**: `MindCanvasApp.swift`

```swift
import SwiftUI
import SwiftData

@main
struct MindCanvasApp: App {
    @State private var authManager = AuthManager.shared
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            Asset.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // 初始化 Google Sign In
        GoogleSignInManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
```

### 4.9 配置文件

#### 4.9.1 Info.plist 配置

需要在 Info.plist 中添加以下配置：

```xml
<!-- Google Sign In -->
<key>GIDClientID</key>
<string>YOUR_GOOGLE_CLIENT_ID</string>

<!-- GitHub OAuth -->
<key>GitHubClientID</key>
<string>YOUR_GITHUB_CLIENT_ID</string>
<key>GitHubClientSecret</key>
<string>YOUR_GITHUB_CLIENT_SECRET</string>

<!-- URL Scheme for GitHub OAuth -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>mindcanvas</string>
        </array>
    </dict>
</array>

<!-- Apple Sign In Capability -->
<!-- 需要在 Xcode 中启用 "Sign in with Apple" capability -->
```

#### 4.9.2 后端 API 地址配置

建议创建配置文件：

**新文件**: `Infrastructure/APIConfig.swift`

```swift
import Foundation

enum APIConfig {
    static let baseURL = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? "http://localhost:8000"
    
    #if DEBUG
    static let baseURL = "http://localhost:8000"
    #else
    static let baseURL = "https://api.mindcanvas.app"
    #endif
}
```

### 4.10 错误处理优化

#### 4.10.1 友好的错误提示

在 `LoginView` 中添加更友好的错误提示：

```swift
private func errorSection(_ message: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Colors.destructive)
            Text("登录失败")
                .font(Theme.Fonts.bodyBold)
                .foregroundStyle(Theme.Colors.destructive)
        }
        
        Text(message)
            .font(Theme.Fonts.callout)
            .foregroundStyle(Theme.Colors.secondaryText)
    }
    .padding(Theme.Spacing.lg)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.Colors.destructive.opacity(0.1))
    .cornerRadius(Theme.Shapes.buttonCornerRadius)
}
```

#### 4.10.2 错误类型映射

在 `AuthManager` 中添加错误类型映射：

```swift
private func mapError(_ error: Error) -> String {
    if let apiError = error as? APIError {
        switch apiError {
        case .networkError:
            return "网络连接失败，请检查网络设置"
        case .unauthorized:
            return "登录已过期，请重新登录"
        case .httpError(let statusCode, let message):
            if statusCode == 400 {
                return message ?? "请求参数错误"
            } else if statusCode == 401 {
                return "登录失败，请检查账号密码"
            } else if statusCode >= 500 {
                return "服务器错误，请稍后重试"
            }
            return message ?? "未知错误"
        default:
            return apiError.errorDescription ?? "未知错误"
        }
    }
    return "登录失败，请稍后重试"
}
```

---

## 五、实施步骤

### 5.1 阶段一：数据模型和网络层（第1天）

**任务清单**:
1. ✅ 创建 `Models/Token.swift`
2. ✅ 创建 `Models/APIModels.swift`
3. ✅ 创建 `Services/APIError.swift`
4. ✅ 创建 `Services/APIClient.swift`
5. ✅ 创建 `Services/TokenManager.swift`
6. ✅ 扩展 `KeychainManager.swift`

**验证标准**:
- 所有模型通过编译
- APIClient 能够发送请求
- TokenManager 能够存储和读取 Token

### 5.2 阶段二：第三方登录集成（第2-3天）

**任务清单**:
1. ✅ 创建 `Services/AppleSignInManager.swift`
2. ✅ 创建 `Services/GoogleSignInManager.swift`
3. ✅ 创建 `Services/GitHubOAuthManager.swift`
4. ✅ 在 Xcode 中配置 Apple Sign In Capability
5. ✅ 配置 Google Sign In SDK
6. ✅ 配置 GitHub OAuth App

**验证标准**:
- Apple Sign In 能够获取 Identity Token
- Google Sign In 能够获取 ID Token
- GitHub OAuth 能够获取 Access Token

### 5.3 阶段三：认证服务层（第4天）

**任务清单**:
1. ✅ 创建 `Services/AuthService.swift`
2. ✅ 修改 `Managers/AuthManager.swift`
3. ✅ 修改 `Models/User.swift`

**验证标准**:
- AuthService 能够调用 APIClient
- AuthManager 能够调用 AuthService
- User 模型与后端一致

### 5.4 阶段四：UI 层集成（第5天）

**任务清单**:
1. ✅ 修改 `Views/Auth/LoginView.swift`
2. ✅ 修改 `MindCanvasApp.swift`
3. ✅ 创建 `Infrastructure/APIConfig.swift`
4. ✅ 配置 Info.plist

**验证标准**:
- LoginView 能够正常显示
- 登录按钮点击后有正确的响应
- 错误提示友好且清晰

### 5.5 阶段五：测试和优化（第6天）

**任务清单**:
1. ✅ 测试所有登录方式
2. ✅ 测试 Token 刷新机制
3. ✅ 测试错误处理
4. ✅ 优化用户体验
5. ✅ 编写单元测试

**验证标准**:
- 所有登录方式正常工作
- Token 自动刷新正常工作
- 错误处理友好且清晰
- 用户体验流畅

---

## 六、测试方案

### 6.1 单元测试

**文件**: `tests/AuthTests/AuthManagerTests.swift`

```swift
import XCTest
@testable import MindCanvas

final class AuthManagerTests: XCTestCase {
    var authManager: AuthManager!
    
    override func setUp() {
        super.setUp()
        authManager = AuthManager.shared
    }
    
    func testAuthenticationState() {
        XCTAssertFalse(authManager.isAuthenticated)
    }
    
    func testTokenStorage() {
        let token = Token(
            accessToken: "test_token",
            refreshToken: "test_refresh_token",
            tokenType: "bearer",
            expiresIn: 604800,
            user: User(
                id: "test_id",
                username: "test_user",
                email: "test@example.com",
                avatarUrl: nil,
                authProvider: "apple",
                createdAt: Date(),
                updatedAt: Date()
            )
        )
        
        TokenManager.shared.saveToken(token)
        
        let accessToken = try? TokenManager.shared.getAccessToken()
        XCTAssertEqual(accessToken, "test_token")
    }
}
```

### 6.2 UI 测试

**文件**: `tests/UITests/LoginViewTests.swift`

```swift
import XCTest

final class LoginViewTests: XCTestCase {
    var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        app = XCUIApplication()
        app.launch()
    }
    
    func testAppleSignIn() {
        app.buttons["Sign in with Apple"].tap()
        // 验证是否跳转到 Apple 登录页面
    }
    
    func testEmailLogin() {
        let emailField = app.textFields["邮箱地址"]
        emailField.tap()
        emailField.typeText("test@example.com")
        
        app.buttons["发送验证码"].tap()
        
        // 等待验证码发送
        let codeField = app.textFields["验证码"]
        codeField.tap()
        codeField.typeText("123456")
        
        app.buttons["登录"].tap()
        
        // 验证是否登录成功
    }
}
```

### 6.3 集成测试

**测试清单**:
- [ ] Apple Sign In 完整流程
- [ ] Google Sign In 完整流程
- [ ] GitHub OAuth 完整流程
- [ ] 邮箱验证码发送流程
- [ ] 邮箱登录完整流程
- [ ] Token 刷新机制
- [ ] Token 过期处理
- [ ] 网络错误处理
- [ ] 服务器错误处理

---

## 七、注意事项

### 7.1 安全注意事项

1. **传输安全**: 强制使用 HTTPS，防止中间人攻击
2. **Token 安全**: 使用 Keychain 存储，不要使用 UserDefaults
3. **验证码安全**: 验证码有效期 5 分钟，防止暴力破解
4. **权限最小化**: 只请求必要的权限
5. **隐私保护**: 遵循 Apple、Google、GitHub 的隐私政策

### 7.2 用户体验注意事项

1. **错误提示**: 提供友好的错误提示，避免技术术语
2. **加载状态**: 显示加载状态，避免用户重复点击
3. **登录状态**: 保持登录状态，避免频繁登录
4. **登出确认**: 登出前确认，避免误操作
5. **自动刷新**: Token 自动刷新，用户无感知

### 7.3 兼容性注意事项

1. **iOS 版本**: 最低 iOS 17.0+
2. **设备支持**: 仅支持 iPad
3. **网络环境**: 支持弱网环境
4. **证书绑定**: 考虑实现证书绑定（Certificate Pinning）

### 7.4 开发注意事项

1. **Mock 保留**: 保留 Mock 服务，方便开发测试
2. **环境切换**: 支持开发/生产环境切换
3. **日志记录**: 记录关键操作日志，便于排查问题
4. **代码审查**: 强制代码审查，确保代码质量
5. **文档更新**: 及时更新文档，保持文档与代码一致

---

## 八、参考资料

### 8.1 官方文档

- [Apple Sign In](https://developer.apple.com/sign-in-with-apple/)
- [Google Sign In](https://developers.google.com/identity/sign-in/ios)
- [GitHub OAuth](https://docs.github.com/en/developers/apps/building-oauth-apps)
- [AuthenticationServices](https://developer.apple.com/documentation/authenticationservices)
- [Keychain Services](https://developer.apple.com/documentation/security/keychain_services)

### 8.2 最佳实践

- [iOS App 安全最佳实践](https://developer.apple.com/documentation/security)
- [OAuth 2.0 最佳实践](https://oauth.net/2/)
- [JWT 最佳实践](https://tools.ietf.org/html/rfc8725)

### 8.3 项目文档

- [后端架构设计](../backend/backend_architecture.md)
- [iOS 第三方登录最佳实践](./ios_third_party_login_best_practices.md)
- [产品需求文档](../prd/v1.0.md)

---

## 九、附录

### 9.1 文件清单

| 文件 | 路径 | 类型 | 说明 |
|-----|------|-----|-----|
| Token.swift | Models/Token.swift | 新建 | Token 模型 |
| APIModels.swift | Models/APIModels.swift | 新建 | API 请求/响应模型 |
| APIError.swift | Services/APIError.swift | 新建 | API 错误定义 |
| APIClient.swift | Services/APIClient.swift | 新建 | API 客户端 |
| TokenManager.swift | Services/TokenManager.swift | 新建 | Token 管理器 |
| AppleSignInManager.swift | Services/AppleSignInManager.swift | 新建 | Apple 登录管理器 |
| GoogleSignInManager.swift | Services/GoogleSignInManager.swift | 新建 | Google 登录管理器 |
| GitHubOAuthManager.swift | Services/GitHubOAuthManager.swift | 新建 | GitHub OAuth 管理器 |
| AuthService.swift | Services/AuthService.swift | 新建 | 认证服务 |
| User.swift | Models/User.swift | 修改 | 用户模型扩展 |
| AuthManager.swift | Managers/AuthManager.swift | 修改 | 认证管理器改造 |
| KeychainManager.swift | Infrastructure/KeychainManager.swift | 修改 | Keychain 管理器扩展 |
| LoginView.swift | Views/Auth/LoginView.swift | 修改 | 登录 UI 改造 |
| MindCanvasApp.swift | MindCanvasApp.swift | 修改 | 应用入口改造 |
| APIConfig.swift | Infrastructure/APIConfig.swift | 新建 | API 配置 |

### 9.2 依赖库

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "7.0.0")
]
```

### 9.3 配置清单

- [ ] Info.plist 配置
- [ ] Apple Sign In Capability
- [ ] Google Sign In SDK
- [ ] GitHub OAuth App
- [ ] 后端 API 地址
- [ ] URL Scheme

---

**文档结束**