import Foundation
import AuthenticationServices

@MainActor
final class GitHubOAuthManager: NSObject {
    static let shared = GitHubOAuthManager()

    private var continuation: CheckedContinuation<String, Error>?

    private let clientID: String
    private let clientSecret: String
    private let redirectURI: String
    private let callbackScheme: String

    private override init() {
        // 从配置文件读取
        self.clientID = Bundle.main.object(forInfoDictionaryKey: "GitHubClientID") as? String ?? ""
        self.clientSecret = Bundle.main.object(forInfoDictionaryKey: "GitHubClientSecret") as? String ?? ""
        self.redirectURI = "mindcanvas://auth"
        self.callbackScheme = "mindcanvas"
        super.init()
    }

    // MARK: - URL 回调处理

    func handleCallback(_ url: URL) {
        // ASWebAuthenticationSession 已经自动处理了 URL 回调
        // 这个方法保留用于将来可能的扩展
        // 当前不需要任何操作
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
                callbackURLScheme: callbackScheme
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

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GitHubOAuthManager: ASWebAuthenticationPresentationContextProviding {
    @objc func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            fatalError("无法找到窗口")
        }
        return window
    }
}