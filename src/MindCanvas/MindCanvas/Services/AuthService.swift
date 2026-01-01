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
        let identityToken = try await appleSignInManager.signIn()
        let token = try await apiClient.login(provider: "apple", token: identityToken)
        tokenManager.saveToken(token)
        return token
    }

    func loginWithGoogle() async throws -> Token {
        let idToken = try await googleSignInManager.signIn()
        let token = try await apiClient.login(provider: "google", token: idToken)
        tokenManager.saveToken(token)
        return token
    }

    func loginWithGithub() async throws -> Token {
        let accessToken = try await gitHubOAuthManager.signIn()
        let token = try await apiClient.login(provider: "github", token: accessToken)
        tokenManager.saveToken(token)
        return token
    }

    // MARK: - 邮箱验证登录

    func sendVerificationCode(email: String) async throws {
        try await apiClient.sendVerificationCode(email: email)
    }

    func verifyEmail(email: String, code: String) async throws -> Token {
        let token = try await apiClient.verifyEmail(email: email, code: code)
        tokenManager.saveToken(token)
        return token
    }

    // MARK: - 用户信息

    func getCurrentUser() async throws -> User {
        return try await apiClient.getCurrentUser()
    }

    func logout() async throws {
        try await apiClient.logout()
        tokenManager.clearTokens()
    }

    // MARK: - Token 管理

    func isLoggedIn() -> Bool {
        return !tokenManager.isTokenExpired()
    }

    func ensureValidToken() async throws -> String {
        return try await tokenManager.ensureValidToken()
    }
}