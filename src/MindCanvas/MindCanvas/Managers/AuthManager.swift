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
            await loadCurrentUser()
        } else {
            isAuthenticated = false
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

    func sendVerificationCode(email: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await authService.sendVerificationCode(email: email)
        } catch {
            errorMessage = formatErrorMessage(error)
        }

        isLoading = false
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
        isAuthenticated = false
        isLoading = false
    }

    func getCurrentUser() -> User? {
        return currentUser
    }

    func ensureValidToken() async throws -> String {
        return try await authService.ensureValidToken()
    }

    private func formatErrorMessage(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? "未知错误"
        } else {
            return "登录失败: \(error.localizedDescription)"
        }
    }
}

