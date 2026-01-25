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
    private(set) var isGuestMode = false

    var isGuest: Bool {
        isGuestMode
    }

    private let keychainManager = KeychainManager.shared
    private let authService = AuthService.shared
    private let tokenManager = TokenManager.shared

    private init() {
        Task {
            await checkAuthentication()
        }
    }

    func checkAuthentication() async {
        if authService.isLoggedIn() {
            isAuthenticated = true
            isGuestMode = false
            await loadCurrentUser()
        } else {
            isAuthenticated = false
            isGuestMode = false
            currentUser = nil
        }
    }

    private func loadCurrentUser() async {
        do {
            currentUser = try await authService.getCurrentUser()
        } catch {
            currentUser = nil
            isAuthenticated = false
        }
    }

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

    func sendVerificationCode(email: String) async -> Bool {
        isLoading = false
        errorMessage = nil

        do {
            let response = try await authService.sendVerificationCode(email: email)
            return true
        } catch {
            errorMessage = formatErrorMessage(error)
            return false
        }
    }

    func verifyEmail(email: String, code: String) async {
        await performLogin {
            try await authService.verifyEmail(email: email, code: code)
        }
    }

    func loginWithEmail(_ email: String, code: String) async {
        await verifyEmail(email: email, code: code)
    }

    private func performLogin(_ loginAction: () async throws -> Token) async {
        isLoading = true
        errorMessage = nil

        do {
            let token = try await loginAction()
            currentUser = token.user
            isGuestMode = false
            isAuthenticated = true
        } catch {
            errorMessage = formatErrorMessage(error)
        }

        isLoading = false
    }

    func logout() async {
        isLoading = true
        errorMessage = nil

        do {
            try await authService.logout()
        } catch {
            errorMessage = formatErrorMessage(error)
        }

        currentUser = nil
        isGuestMode = false
        isAuthenticated = false
        isLoading = false
    }
    
    func switchToGuestMode() async {
        isLoading = true
        errorMessage = nil

        keychainManager.deleteToken()
        currentUser = nil

        // 先设置认证状态，确保 RootView 能正确响应
        isAuthenticated = true

        // 然后设置游客模式标志
        isGuestMode = true

        isLoading = false
    }

    func getCurrentUser() -> User? {
        return currentUser
    }

    func ensureValidToken() async throws -> String {
        return try await authService.ensureValidToken()
    }
    
    func updateUsername(_ newUsername: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }

        do {
            let token = try await ensureValidToken()
            
            let response: [String: String] = try await APIClient.shared.request(
                endpoint: "/api/v1/users/me/username",
                method: .PUT,
                body: ["username": newUsername],
                requiresAuth: true,
                responseType: [String: String].self
            )
            
            if let updatedUsername = response["username"] {
                currentUser?.username = updatedUsername
                return true
            }
            
            return false
        } catch {
            errorMessage = formatErrorMessage(error)
            return false
        }
    }

    private func formatErrorMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "未知错误"
        } else {
            return "登录失败: \(error.localizedDescription)"
        }
    }
}

