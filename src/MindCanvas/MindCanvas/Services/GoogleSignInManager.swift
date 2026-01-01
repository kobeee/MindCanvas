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
        print("=== GoogleSignInManager.configure() 开始 ===")

        // 打印 Bundle 信息
        print("Bundle.main.bundleIdentifier: \(Bundle.main.bundleIdentifier ?? "nil")")
        print("Bundle.main.infoDictionary keys: \(Bundle.main.infoDictionary?.keys.map { $0 as! String }.sorted() ?? [])")

        // 打印 URL Scheme 配置
        print("CFBundleURLTypes from Info.plist: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") ?? "nil")")

        // 直接在代码中配置 GIDClientID，避免 Info.plist 构建冲突
        let clientID = "356898960552-aq7iv1iooas0ihn2j391becn9jvsuoou.apps.googleusercontent.com"

        print("✅ 使用硬编码的 GIDClientID: \(clientID)")

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        print("✅ GIDSignIn.sharedInstance.configuration 已设置")
        print("✅ GIDSignIn.sharedInstance.configuration.clientID: \(GIDSignIn.sharedInstance.configuration?.clientID ?? "nil")")

        print("=== GoogleSignInManager.configure() 完成 ===")
    }

    // MARK: - 登录

    func signIn() async throws -> String {
        print("=== GoogleSignInManager.signIn() 开始 ===")

        guard let rootViewController = getRootViewController() else {
            print("❌ 无法获取 rootViewController")
            throw APIError.unknown
        }

        print("✅ 获取到 rootViewController: \(type(of: rootViewController))")

        // 检查 GIDSignIn.sharedInstance.configuration 的状态
        print("GIDSignIn.sharedInstance.configuration: \(GIDSignIn.sharedInstance.configuration != nil ? "已设置" : "nil")")
        if let config = GIDSignIn.sharedInstance.configuration {
            print("GIDSignIn.sharedInstance.configuration.clientID: \(config.clientID)")
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            print("准备调用 GIDSignIn.sharedInstance.signIn()...")

            GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
                if let error = error {
                    print("❌ Google Sign In 失败: \(error.localizedDescription)")
                    print("Error details: \(error)")
                    continuation.resume(throwing: error)
                    return
                }

                guard let idToken = result?.user.idToken?.tokenString else {
                    print("❌ 无法获取 idToken")
                    continuation.resume(throwing: APIError.unknown)
                    return
                }

                print("✅ Google Sign In 成功，获取到 idToken")
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