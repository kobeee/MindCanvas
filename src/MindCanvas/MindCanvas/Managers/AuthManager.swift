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
    private let authService = MockAuthService.shared
    
    private init() {
        checkAuthentication()
    }
    
    func checkAuthentication() {
        if let token = keychainManager.getToken(), !token.isEmpty {
            isAuthenticated = true
            loadMockUser()
        } else {
            isAuthenticated = false
            currentUser = nil
        }
    }
    
    private func loadMockUser() {
        currentUser = User(
            id: UUID().uuidString,
            username: "当前用户",
            email: "user@example.com",
            isPro: false
        )
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
    
    func loginWithEmail(_ email: String, code: String) async {
        await performLogin {
            try await authService.loginWithEmail(email, code: code)
        }
    }
    
    private func performLogin(_ loginAction: () async throws -> LoginResponse) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await loginAction()
            
            if keychainManager.saveToken(response.token) {
                currentUser = response.user
                isAuthenticated = true
            } else {
                errorMessage = "保存登录信息失败"
            }
        } catch {
            errorMessage = "登录失败: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func logout() {
        _ = keychainManager.deleteToken()
        currentUser = nil
        isAuthenticated = false
    }
}

