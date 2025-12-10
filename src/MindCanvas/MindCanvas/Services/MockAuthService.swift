import Foundation

enum AuthError: Error {
    case invalidCredentials
    case networkError
    case unknown
}

struct LoginResponse: Codable {
    let token: String
    let user: User
}

@MainActor
final class MockAuthService {
    static let shared = MockAuthService()
    
    private init() {}
    
    func loginWithApple() async throws -> LoginResponse {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        let user = User(
            id: UUID().uuidString,
            username: "Apple用户",
            email: "user@apple.com",
            avatarUrl: nil,
            isPro: false
        )
        
        return LoginResponse(
            token: "mock_apple_token_\(UUID().uuidString)",
            user: user
        )
    }
    
    func loginWithGoogle() async throws -> LoginResponse {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        let user = User(
            id: UUID().uuidString,
            username: "Google用户",
            email: "user@gmail.com",
            avatarUrl: nil,
            isPro: false
        )
        
        return LoginResponse(
            token: "mock_google_token_\(UUID().uuidString)",
            user: user
        )
    }
    
    func loginWithGithub() async throws -> LoginResponse {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        let user = User(
            id: UUID().uuidString,
            username: "GitHub用户",
            email: "user@github.com",
            avatarUrl: nil,
            isPro: false
        )
        
        return LoginResponse(
            token: "mock_github_token_\(UUID().uuidString)",
            user: user
        )
    }
    
    func loginWithEmail(_ email: String, code: String) async throws -> LoginResponse {
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        guard code == "123456" else {
            throw AuthError.invalidCredentials
        }
        
        let user = User(
            id: UUID().uuidString,
            username: email.components(separatedBy: "@").first ?? "用户",
            email: email,
            avatarUrl: nil,
            isPro: false
        )
        
        return LoginResponse(
            token: "mock_email_token_\(UUID().uuidString)",
            user: user
        )
    }
    
    func sendVerificationCode(to email: String) async throws {
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}

