import Foundation

struct LoginRequest: Codable {
    let provider: String
    let token: String
}

struct SendVerificationCodeRequest: Codable {
    let email: String
}

struct VerifyEmailRequest: Codable {
    let email: String
    let code: String
}

struct RefreshTokenRequest: Codable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

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

struct ErrorResponse: Codable {
    let error: String?
    let message: String?
    let details: [String: String]?
}