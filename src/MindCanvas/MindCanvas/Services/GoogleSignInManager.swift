import Foundation
import GoogleSignIn

@MainActor
final class GoogleSignInManager: NSObject {
    static let shared = GoogleSignInManager()

    private var continuation: CheckedContinuation<String, Error>?

    private override init() {
        super.init()
    }

    // MARK: - 配置

    func configure() throws {
        let clientID = "356898960552-aq7iv1iooas0ihn2j391becn9jvsuoou.apps.googleusercontent.com"
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