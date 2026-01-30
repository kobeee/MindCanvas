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
    private(set) var isInitialized = false

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
        print("[AuthManager] checkAuthentication - 开始认证检查")

        let isLoggedIn = authService.isLoggedIn()
        print("[AuthManager] authService.isLoggedIn(): \(isLoggedIn)")

        if isLoggedIn {
            isAuthenticated = true
            isGuestMode = false
            await loadCurrentUser()
            print("[AuthManager] 认证有效，用户已加载")
        } else {
            let hasRefreshToken = keychainManager.get("refresh_token") != nil
            print("[AuthManager] Token已过期，有refresh_token: \(hasRefreshToken)")

            if hasRefreshToken {
                do {
                    // 使用 ensureValidToken 自动刷新 token
                    _ = try await authService.ensureValidToken()
                    if authService.isLoggedIn() {
                        isAuthenticated = true
                        isGuestMode = false
                        await loadCurrentUser()
                        print("[AuthManager] Token刷新成功，用户已加载")
                    } else {
                        // 刷新失败，回到登录页面
                        isAuthenticated = false
                        isGuestMode = false
                        currentUser = nil
                        print("[AuthManager] Token刷新失败，回到登录页面")
                    }
                } catch {
                    // 刷新异常，回到登录页面
                    isAuthenticated = false
                    isGuestMode = false
                    currentUser = nil
                    print("[AuthManager] Token刷新错误: \(error)，回到登录页面")
                }
            } else {
                // 无token，显示登录页面
                isAuthenticated = false
                isGuestMode = false
                currentUser = nil
                print("[AuthManager] 无refresh_token，显示登录页面")
            }
        }

        isInitialized = true
        print("[AuthManager] checkAuthentication - 完成: isAuthenticated=\(isAuthenticated), isGuestMode=\(isGuestMode)")
    }

    private func loadCurrentUser() async {
        do {
            currentUser = try await authService.getCurrentUser()
        } catch {
            // 获取用户信息失败，但不重置登录状态（可能是临时网络问题）
            currentUser = nil
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
        print("[AuthManager] logout - 开始退出登录")
        isLoading = true
        errorMessage = nil

        do {
            try await authService.logout()
            print("[AuthManager] logout - 后端logout成功")
        } catch {
            errorMessage = formatErrorMessage(error)
            print("[AuthManager] logout - 后端logout失败: \(error)")
        }

        // 清理所有登录状态
        currentUser = nil
        isAuthenticated = false  // 退出登录后回到登录页面
        isGuestMode = false     // 重置游客模式
        isLoading = false

        // 最终验证：确认没有残留token
        let accessToken = keychainManager.get("access_token")
        let refreshToken = keychainManager.get("refresh_token")
        print("[AuthManager] logout - 最终检查: accessToken=\(accessToken != nil), refreshToken=\(refreshToken != nil)")
        print("[AuthManager] logout - 状态设置: isAuthenticated=\(isAuthenticated), isGuestMode=\(isGuestMode)")

        if accessToken != nil || refreshToken != nil {
            print("[AuthManager] CRITICAL WARNING: 退出登录后仍有残留token！重启应用后会保持登录状态！")
        }
    }
    
    func switchToGuestMode() async {
        print("[AuthManager] switchToGuestMode - 开始切换到游客模式")
        isLoading = true
        errorMessage = nil

        // 使用TokenManager清理所有token（而不是keychainManager.deleteToken()）
        tokenManager.clearTokens()
        currentUser = nil

        // 游客模式也是一种"已认证"状态，显示MainView
        isAuthenticated = true
        isGuestMode = true

        isLoading = false

        // 最终验证：确认没有残留token
        let accessToken = keychainManager.get("access_token")
        let refreshToken = keychainManager.get("refresh_token")
        print("[AuthManager] switchToGuestMode - 最终检查: accessToken=\(accessToken != nil), refreshToken=\(refreshToken != nil)")
        print("[AuthManager] switchToGuestMode - 状态设置: isAuthenticated=\(isAuthenticated), isGuestMode=\(isGuestMode)")

        if accessToken != nil || refreshToken != nil {
            print("[AuthManager] CRITICAL WARNING: 游客模式切换后仍有残留token！")
        }
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

