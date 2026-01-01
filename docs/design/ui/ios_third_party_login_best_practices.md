# iOS 第三方登录最佳实践

本文档详细介绍了在 iOS 应用中实现第三方登录（Apple Sign-In、Google Sign-In、GitHub OAuth）的最佳实践，包括技术实现、安全注意事项和代码示例。

## 目录

1. [Apple Sign-In](#1-apple-sign-in)
2. [Google Sign-In](#2-google-sign-in)
3. [GitHub OAuth](#3-github-oauth)
4. [通用最佳实践](#4-通用最佳实践)
5. [安全注意事项](#5-安全注意事项)

---

## 1. Apple Sign-In

### 1.1 技术概述

Apple Sign-In 是 iOS 13+ 引入的官方登录方式，要求所有支持第三方登录的应用必须提供此选项。

**核心框架**：
- `AuthenticationServices` - Apple 官方认证框架
- `ASAuthorizationAppleIDProvider` - 创建 Apple ID 认证请求
- `ASAuthorizationController` - 管理认证流程
- `ASAuthorizationAppleIDCredential` - 认证凭据

### 1.2 实现步骤

#### 步骤 1：添加 Capability

在 Xcode 中：
1. 选择项目 Target
2. 进入 "Signing & Capabilities"
3. 点击 "+ Capability"
4. 添加 "Sign in with Apple"

#### 步骤 2：配置认证请求

```swift
import AuthenticationServices

@available(iOS 13.0, *)
class AppleSignInManager: NSObject {

    private var currentNonce: String?

    func startSignInFlow() {
        // 1. 创建随机 nonce（防止重放攻击）
        let nonce = randomNonceString()
        currentNonce = nonce

        // 2. 创建 Apple ID 提供者
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()

        // 3. 请求用户信息（仅在首次登录时提供）
        request.requestedScopes = [.fullName, .email]

        // 4. 添加 nonce 的 SHA256 哈希
        request.nonce = sha256(nonce)

        // 5. 创建认证控制器
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])

        // 6. 设置代理
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self

        // 7. 执行请求
        authorizationController.performRequests()
    }

    // MARK: - 辅助方法

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }

            for random in randoms {
                if remainingLength == 0 {
                    break
                }
                if random < UInt8(charset.count) {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()

        return hashString
    }
}
```

#### 步骤 3：实现代理协议

```swift
@available(iOS 13.0, *)
extension AppleSignInManager: ASAuthorizationControllerDelegate {

    func authorizationController(
        _ controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        // 验证 nonce
        guard let nonce = currentNonce else {
            fatalError("Invalid state: A login callback was received, but no login request was sent.")
        }

        // 获取 identity token
        guard let appleIDToken = appleIDCredential.identityToken else {
            print("Unable to fetch identity token")
            return
        }

        guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            print("Unable to serialize token string from data: \(appleIDToken.debugDescription)")
            return
        }

        // 判断是新用户还是老用户
        if let email = appleIDCredential.email, let fullName = appleIDCredential.fullName {
            // 新用户：首次登录，Apple 提供了邮箱和姓名
            handleNewUser(
                userID: appleIDCredential.user,
                email: email,
                fullName: fullName,
                idToken: idTokenString,
                nonce: nonce
            )
        } else {
            // 老用户：Apple 不再提供邮箱和姓名
            handleExistingUser(
                userID: appleIDCredential.user,
                idToken: idTokenString,
                nonce: nonce
            )
        }
    }

    func authorizationController(
        _ controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        guard let error = error as? ASAuthorizationError else {
            return
        }

        switch error.code {
        case .canceled:
            print("用户取消了登录")
        case .failed:
            print("登录失败: \(error.localizedDescription)")
        case .invalidResponse:
            print("无效的响应")
        case .notHandled:
            print("未处理的请求")
        case .unknown:
            print("未知错误")
        @unknown default:
            print("未定义的错误")
        }
    }

    private func handleNewUser(
        userID: String,
        email: String,
        fullName: PersonNameComponents,
        idToken: String,
        nonce: String
    ) {
        // 将用户信息存储到 Keychain 或本地数据库
        let user = User(
            id: userID,
            email: email,
            fullName: fullName.formatted(),
            provider: "apple"
        )

        // 发送到后端验证
        sendTokenToBackend(idToken: idToken, nonce: nonce, user: user)
    }

    private func handleExistingUser(
        userID: String,
        idToken: String,
        nonce: String
    ) {
        // 从本地存储读取用户信息
        if let user = loadUserFromKeychain(userID: userID) {
            sendTokenToBackend(idToken: idToken, nonce: nonce, user: user)
        } else {
            print("用户信息丢失，需要重新注册")
        }
    }

    private func sendTokenToBackend(idToken: String, nonce: String, user: User) {
        // 发送 idToken 和 nonce 到后端进行验证
        // 后端需要验证 Apple 的签名并创建会话
    }
}
```

#### 步骤 4：实现展示上下文提供者

```swift
@available(iOS 13.0, *)
extension AppleSignInManager: ASAuthorizationControllerPresentationContextProviding {

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // 返回当前窗口
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}
```

#### 步骤 5：添加登录按钮

```swift
import AuthenticationServices

struct SignInView: View {
    var body: some View {
        VStack {
            // Apple Sign-In 按钮
            if #available(iOS 13.0, *) {
                SignInWithAppleButton(
                    onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    },
                    onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            handleAuthorization(authorization)
                        case .failure(let error):
                            handleError(error)
                        }
                    }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(8)
            }
        }
    }

    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            return
        }

        // 处理认证凭据
        // ...
    }

    private func handleError(_ error: Error) {
        print("Apple Sign-In error: \(error.localizedDescription)")
    }
}
```

### 1.3 关键注意事项

#### ⚠️ 重要：用户信息只在首次提供

Apple 只在**首次登录**时提供用户的邮箱和姓名，后续登录不再提供。因此：

1. **首次登录时必须保存用户信息**到本地数据库或后端
2. **使用 `appleIDCredential.user` 作为唯一标识符**（这个值在每次登录都是相同的）
3. 如果首次登录时保存失败，后续登录将无法获取用户信息

#### 验证凭据状态

在应用启动时，应该验证 Apple ID 凭据状态：

```swift
@available(iOS 13.0, *)
func checkCredentialState(userID: String) {
    let provider = ASAuthorizationAppleIDProvider()
    provider.getCredentialState(forUserID: userID) { state, error in
        switch state {
        case .authorized:
            print("用户已授权")
        case .revoked:
            print("用户已撤销授权，需要重新登录")
            // 执行登出操作
        case .notFound:
            print("未找到凭据")
        case .transferred:
            print("凭据已转移到新设备")
        @unknown default:
            print("未知状态")
        }
    }
}
```

#### 支持自动登录（iOS 16+）

```swift
@available(iOS 16.0, *)
func performExistingAccountSetupFlows() {
    let requests = [
        ASAuthorizationAppleIDProvider().createRequest(),
        ASAuthorizationPasswordProvider().createRequest()
    ]

    let authorizationController = ASAuthorizationController(authorizationRequests: requests)
    authorizationController.delegate = self
    authorizationController.presentationContextProvider = self

    // 只使用立即可用的凭据
    authorizationController.performRequests(options: .preferImmediatelyAvailableCredentials)
}
```

---

## 2. Google Sign-In

### 2.1 技术概述

Google Sign-In 提供了官方 SDK，支持 OAuth 2.0 和 OpenID Connect。

**核心技术**：
- `GoogleSignIn` SDK - 官方 Google 登录 SDK
- `GIDSignIn` - 单例管理类
- `GIDConfiguration` - 配置信息
- `GIDGoogleUser` - 用户信息

### 2.2 SDK 集成

#### 步骤 1：添加依赖

**Swift Package Manager**：

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "7.0.0")
]
```

**CocoaPods**：

```ruby
pod 'GoogleSignIn'
```

#### 步骤 2：配置 Google Cloud Console

1. 创建项目并启用 Google Sign-In API
2. 配置 OAuth 2.0 客户端 ID
3. 下载 `GoogleService-Info.plist` 并添加到项目中

#### 步骤 3：初始化配置

```swift
import GoogleSignIn

@main
struct MindCanvasApp: App {
    init() {
        // 初始化 Google Sign-In
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else {
            fatalError("GIDClientID not found in Info.plist")
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
    }

    var body: some Scene {
        // ...
    }
}
```

### 2.3 实现登录流程

```swift
import GoogleSignIn
import SwiftUI

class GoogleSignInManager: ObservableObject {

    @Published var isSignedIn = false
    @Published var errorMessage: String?

    func signIn(presenting: UIViewController) {
        GIDSignIn.sharedInstance.signIn(withPresenting: presenting) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                self.errorMessage = "Google Sign-In error: \(error.localizedDescription)"
                return
            }

            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                self.errorMessage = "Failed to get user token"
                return
            }

            // 获取用户信息
            let email = user.profile?.email
            let fullName = user.profile?.name
            let userID = user.userID

            // 发送到后端验证
            self.sendTokenToBackend(
                idToken: idToken,
                userID: userID,
                email: email,
                fullName: fullName
            )
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        isSignedIn = false
    }

    private func sendTokenToBackend(
        idToken: String,
        userID: String,
        email: String?,
        fullName: String?
    ) {
        // 发送 idToken 到后端验证
        // 后端需要验证 Google 的签名

        let parameters: [String: Any] = [
            "id_token": idToken,
            "user_id": userID,
            "email": email ?? "",
            "full_name": fullName ?? ""
        ]

        // 使用 URLSession 发送请求
        // ...
    }
}
```

### 2.4 SwiftUI 集成

```swift
import SwiftUI
import GoogleSignIn

struct GoogleSignInButtonView: View {

    @StateObject private var manager = GoogleSignInManager()

    var body: some View {
        VStack {
            Button(action: {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    manager.signIn(presenting: rootViewController)
                }
            }) {
                HStack {
                    Image("google_logo")
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text("Sign in with Google")
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
}
```

### 2.5 后端验证

后端需要验证 Google ID Token 的有效性：

```python
# Python 后端示例
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests

def verify_google_token(token):
    try:
        # 验证 ID Token
        idinfo = id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            audience=YOUR_CLIENT_ID
        )

        # 验证颁发者
        if idinfo['iss'] not in ['accounts.google.com', 'https://accounts.google.com']:
            raise ValueError('Wrong issuer.')

        # 验证用户 ID
        userid = idinfo['sub']

        return {
            'user_id': userid,
            'email': idinfo.get('email'),
            'email_verified': idinfo.get('email_verified'),
            'name': idinfo.get('name'),
            'picture': idinfo.get('picture')
        }
    except ValueError as e:
        # Invalid token
        raise ValueError(f"Token verification failed: {e}")
```

### 2.6 关键注意事项

#### ID Token 验证

后端必须验证 ID Token 的以下内容：

1. **签名验证**：使用 Google 的公钥验证签名
2. **Audience 验证**：确保 `aud` 字段等于你的 Client ID
3. **Issuer 验证**：确保 `iss` 字段为 `accounts.google.com` 或 `https://accounts.google.com`
4. **过期时间验证**：确保 `exp` 未过期
5. **Email 验证**：检查 `email_verified` 字段

#### Token 刷新

```swift
// 刷新 Token
GIDSignIn.sharedInstance.signIn(withPresenting: presenting) { result, error in
    guard let user = result?.user else { return }

    user.refreshTokensIfNeeded { user, error in
        guard error == nil else { return }
        guard let user = user else { return }

        let idToken = user.idToken?.tokenString
        let accessToken = user.accessToken.tokenString

        // 使用新的 token
    }
}
```

---

## 3. GitHub OAuth

### 3.1 技术概述

GitHub OAuth 使用标准的 OAuth 2.0 授权码流程，通过 `ASWebAuthenticationSession` 实现。

**核心组件**：
- `ASWebAuthenticationSession` - Apple 官方 Web 认证会话
- OAuth 2.0 授权码流程
- GitHub OAuth API

### 3.2 配置 GitHub OAuth App

1. 访问 GitHub Settings > Developer settings > OAuth Apps
2. 创建新的 OAuth App
3. 配置：
   - **Application name**: MindCanvas
   - **Homepage URL**: https://yourapp.com
   - **Authorization callback URL**: `mindcanvas://auth`（自定义 URL Scheme）
4. 获取 **Client ID** 和 **Client Secret**

### 3.3 注册 URL Scheme

在 Xcode 中：

1. 选择项目 Target
2. 进入 "Info" tab
3. 添加 "URL Types"
4. 添加 Scheme: `mindcanvas`

### 3.4 实现认证流程

```swift
import AuthenticationServices
import SwiftUI

class GitHubOAuthManager: NSObject, ObservableObject {

    @Published var isSignedIn = false
    @Published var errorMessage: String?

    private let clientID = "YOUR_GITHUB_CLIENT_ID"
    private let clientSecret = "YOUR_GITHUB_CLIENT_SECRET"
    private let redirectURI = "mindcanvas://auth"
    private let authURL = "https://github.com/login/oauth/authorize"
    private let tokenURL = "https://github.com/login/oauth/access_token"

    func startOAuthFlow() {
        // 1. 构建授权 URL
        var components = URLComponents(string: authURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "read:user,user:email")
        ]

        guard let authURL = components?.url else {
            errorMessage = "Failed to create auth URL"
            return
        }

        // 2. 创建认证会话
        let authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "mindcanvas"
        ) { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                self.errorMessage = "OAuth error: \(error.localizedDescription)"
                return
            }

            guard let callbackURL = callbackURL else {
                self.errorMessage = "No callback URL"
                return
            }

            // 3. 解析授权码
            self.handleCallbackURL(callbackURL)
        }

        // 4. 设置展示上下文
        authSession.presentationContextProvider = self

        // 5. 可选：使用短暂会话（不缓存 cookies）
        authSession.prefersEphemeralWebBrowserSession = true

        // 6. 启动认证流程
        if !authSession.start() {
            errorMessage = "Failed to start authentication session"
        }
    }

    private func handleCallbackURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            errorMessage = "Invalid callback URL"
            return
        }

        // 提取授权码
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            errorMessage = "No authorization code found"
            return
        }

        // 交换授权码获取 access token
        exchangeCodeForToken(code: code)
    }

    private func exchangeCodeForToken(code: String) {
        // 构建请求
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let parameters: [String: String] = [
            "client_id": clientID,
            "client_secret": clientSecret,
            "code": code,
            "redirect_uri": redirectURI
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: parameters) else {
            errorMessage = "Failed to encode parameters"
            return
        }

        request.httpBody = jsonData

        // 发送请求
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Network error: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "No data received"
                }
                return
            }

            // 解析响应
            do {
                let tokenResponse = try JSONDecoder().decode(GitHubTokenResponse.self, from: data)
                self.fetchUserInfo(accessToken: tokenResponse.access_token)
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to decode token response: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func fetchUserInfo(accessToken: String) {
        let url = URL(string: "https://api.github.com/user")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to fetch user info: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "No user data received"
                }
                return
            }

            do {
                let user = try JSONDecoder().decode(GitHubUser.self, from: data)
                DispatchQueue.main.async {
                    self.handleUserLogin(user: user, accessToken: accessToken)
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to decode user info: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func handleUserLogin(user: GitHubUser, accessToken: String) {
        // 发送 access_token 到后端验证
        // 或直接使用 access_token 访问 GitHub API

        isSignedIn = true
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GitHubOAuthManager: ASWebAuthenticationPresentationContextProviding {

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - 数据模型

struct GitHubTokenResponse: Codable {
    let access_token: String
    let token_type: String
    let scope: String
}

struct GitHubUser: Codable {
    let id: Int
    let login: String
    let name: String?
    let email: String?
    let avatar_url: String
}
```

### 3.5 SwiftUI 集成

```swift
struct GitHubSignInButtonView: View {

    @StateObject private var manager = GitHubOAuthManager()

    var body: some View {
        VStack {
            Button(action: {
                manager.startOAuthFlow()
            }) {
                HStack {
                    Image("github_logo")
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text("Sign in with GitHub")
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(8)
            }

            if let errorMessage = manager.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }
        }
    }
}
```

### 3.6 关键注意事项

#### 使用短暂会话

```swift
// 启用短暂会话，防止缓存 cookies
authSession.prefersEphemeralWebBrowserSession = true
```

这可以：
- 防止用户第二次登录时自动使用缓存的凭据
- 提高安全性
- 每次都需要用户输入凭证

#### 错误处理

需要处理以下错误：
- 用户取消登录
- 网络错误
- 授权码无效或过期
- Token 交换失败

#### Scope 权限

根据需求请求最小权限：
- `read:user` - 读取用户基本信息
- `user:email` - 读取用户邮箱
- `repo` - 访问仓库（如需要）

---

## 4. 通用最佳实践

### 4.1 Token 安全存储

#### 使用 Keychain 存储敏感 Token

```swift
import Security
import Foundation

class KeychainManager {

    enum KeychainError: Error {
        case duplicateEntry
        case unknown(OSStatus)
        case itemNotFound
    }

    // 存储 Token
    static func save(
        service: String,
        account: String,
        data: Data
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // 先删除旧数据
        SecItemDelete(query as CFDictionary)

        // 添加新数据
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unknown(status)
        }
    }

    // 读取 Token
    static func read(
        service: String,
        account: String
    ) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.itemNotFound
        }

        return data
    }

    // 删除 Token
    static func delete(
        service: String,
        account: String
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unknown(status)
        }
    }
}

// 使用示例
struct TokenStorage {

    private static let service = "com.mindcanvas.tokens"

    static func saveAccessToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else { return }
        try KeychainManager.save(
            service: service,
            account: "access_token",
            data: data
        )
    }

    static func getAccessToken() throws -> String {
        let data = try KeychainManager.read(
            service: service,
            account: "access_token"
        )
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func deleteAccessToken() throws {
        try KeychainManager.delete(
            service: service,
            account: "access_token"
        )
    }
}
```

#### Keychain 访问控制选项

```swift
// 安全级别从低到高：
// 1. kSecAttrAccessibleWhenUnlocked - 设备解锁时可访问
// 2. kSecAttrAccessibleAfterFirstUnlock - 第一次解锁后可访问
// 3. kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly - 需要密码且仅限当前设备（最安全）
// 4. kSecAttrAccessibleWhenUnlockedThisDeviceOnly - 解锁时可访问且仅限当前设备

// 推荐使用：
kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
```

### 4.2 Token 刷新机制

#### 实现自动刷新

```swift
class TokenRefreshManager {

    private var refreshTask: Task<Void, Never>?

    func refreshTokenIfNeeded() async throws -> String {
        // 检查 token 是否即将过期
        if isTokenExpiringSoon() {
            return try await performTokenRefresh()
        }

        return try TokenStorage.getAccessToken()
    }

    private func isTokenExpiringSoon() -> Bool {
        guard let expirationDate = getTokenExpirationDate() else {
            return true
        }

        // 如果在 5 分钟内过期，需要刷新
        return Date().addingTimeInterval(300) > expirationDate
    }

    private func performTokenRefresh() async throws -> String {
        // 取消之前的刷新任务
        refreshTask?.cancel()

        // 创建新的刷新任务
        refreshTask = Task {
            // 调用后端刷新接口
            let refreshToken = try TokenStorage.getRefreshToken()

            var request = URLRequest(url: URL(string: "https://api.mindcanvas.com/auth/refresh")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let parameters = ["refresh_token": refreshToken]
            request.httpBody = try? JSONSerialization.data(withJSONObject: parameters)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw TokenRefreshError.failed
            }

            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

            // 保存新 token
            try TokenStorage.saveAccessToken(tokenResponse.access_token)
            try TokenStorage.saveRefreshToken(tokenResponse.refresh_token)

            return tokenResponse.access_token
        }

        return try await refreshTask!.value
    }
}

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String
    let expires_in: Int
}

enum TokenRefreshError: Error {
    case failed
    case noRefreshToken
}
```

#### 在 API 请求中使用

```swift
class APIClient {

    private let tokenRefreshManager = TokenRefreshManager()

    func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        // 获取有效的 access token
        let accessToken = try await tokenRefreshManager.refreshTokenIfNeeded()

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        // 检查是否需要刷新 token
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode == 401 {
            // Token 可能已过期，尝试刷新后重试
            let newAccessToken = try await tokenRefreshManager.performTokenRefresh()
            request.setValue("Bearer \(newAccessToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(T.self, from: retryData)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

### 4.3 登录状态持久化

```swift
class AuthManager: ObservableObject {

    @Published var isAuthenticated = false
    @Published var currentUser: User?

    private let keychainManager = KeychainManager()

    init() {
        // 应用启动时检查登录状态
        checkAuthState()
    }

    private func checkAuthState() {
        do {
            // 检查 Keychain 中是否有 token
            let accessToken = try TokenStorage.getAccessToken()

            if !accessToken.isEmpty {
                // 验证 token 是否有效
                Task {
                    await validateToken(accessToken)
                }
            }
        } catch {
            // 没有 token 或 token 无效
            isAuthenticated = false
        }
    }

    private func validateToken(_ token: String) async {
        do {
            // 调用后端验证接口
            let user = try await APIClient().request<User>(
                endpoint: "https://api.mindcanvas.com/auth/validate"
            )

            await MainActor.run {
                self.currentUser = user
                self.isAuthenticated = true
            }
        } catch {
            // Token 无效，清除本地数据
            await signOut()
        }
    }

    func signOut() async {
        // 清除 Keychain 中的 token
        try? TokenStorage.deleteAccessToken()
        try? TokenStorage.deleteRefreshToken()

        // 清除用户信息
        await MainActor.run {
            self.currentUser = nil
            self.isAuthenticated = false
        }
    }
}
```

### 4.4 错误处理和用户提示

```swift
enum AuthError: LocalizedError {
    case networkError
    case invalidCredentials
    case userCancelled
    case tokenExpired
    case serverError(String)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "网络连接失败，请检查网络设置"
        case .invalidCredentials:
            return "用户名或密码错误"
        case .userCancelled:
            return "登录已取消"
        case .tokenExpired:
            return "登录已过期，请重新登录"
        case .serverError(let message):
            return message
        case .unknownError:
            return "未知错误，请稍后重试"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "请检查网络连接后重试"
        case .tokenExpired:
            return "请重新登录以继续使用"
        default:
            return nil
        }
    }
}

// 错误提示视图
struct ErrorAlertView: View {

    let error: AuthError
    @Binding var isPresented: Bool

    var body: some View {
        Alert(
            title: Text("错误"),
            message: Text(error.errorDescription ?? "未知错误"),
            dismissButton: .default(Text("确定")) {
                isPresented = false
            }
        )
    }
}
```

### 4.5 UI/UX 设计规范

#### 登录按钮设计

```swift
struct SocialLoginButtonsView: View {

    @StateObject private var appleManager = AppleSignInManager()
    @StateObject private var googleManager = GoogleSignInManager()
    @StateObject private var githubManager = GitHubOAuthManager()

    var body: some View {
        VStack(spacing: 16) {
            Text("或使用以下方式登录")
                .font(.caption)
                .foregroundColor(.secondary)

            // Apple Sign-In
            if #available(iOS 13.0, *) {
                SignInWithAppleButton(
                    onRequest: { request in
                        request.requestedScopes = [.fullName, .email]
                    },
                    onCompletion: { result in
                        // 处理结果
                    }
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .cornerRadius(8)
            }

            // Google Sign-In
            Button(action: {
                if let rootViewController = getRootViewController() {
                    googleManager.signIn(presenting: rootViewController)
                }
            }) {
                HStack {
                    Image("google_logo")
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text("Sign in with Google")
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white)
                .foregroundColor(.black)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }

            // GitHub Sign-In
            Button(action: {
                githubManager.startOAuthFlow()
            }) {
                HStack {
                    Image("github_logo")
                        .resizable()
                        .frame(width: 20, height: 20)
                    Text("Sign in with GitHub")
                        .font(.system(size: 16, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.black)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 20)
    }

    private func getRootViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        return rootViewController
    }
}
```

#### 加载状态

```swift
struct LoadingOverlayView: View {

    let isLoading: Bool

    var body: some View {
        if isLoading {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                ProgressView()
                    .scaleEffect(1.5)
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(radius: 10)
            }
        }
    }
}
```

---

## 5. 安全注意事项

### 5.1 传输安全

#### 强制使用 HTTPS

```swift
// 在 Info.plist 中配置
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
</dict>
```

#### 证书绑定（Certificate Pinning）

```swift
import Alamofire

class APIClient {

    static let session: Session = {
        let evaluator = PinnableServerTrustEvaluator(
            servers: ["api.mindcanvas.com"],
            certificates: [
                // 添加你的服务器证书
            ],
            performDefaultValidation: true,
            validateHost: true
        )

        let manager = ServerTrustManager(evaluators: [
            "api.mindcanvas.com": evaluator
        ])

        return Session(
            serverTrustManager: manager
        )
    }()
}
```

### 5.2 防止重放攻击

#### 使用 Nonce

Apple Sign-In 和其他 OAuth 提供商都要求使用 nonce 防止重放攻击：

```swift
// 生成随机 nonce
private func randomNonceString(length: Int = 32) -> String {
    precondition(length > 0)
    let charset: [Character] =
        Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
    var result = ""
    var remainingLength = length

    while remainingLength > 0 {
        let randoms: [UInt8] = (0..<16).map { _ in
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            return random
        }

        for random in randoms {
            if remainingLength == 0 {
                break
            }
            if random < UInt8(charset.count) {
                result.append(charset[Int(random)])
                remainingLength -= 1
            }
        }
    }
    return result
}

// 计算 SHA256 哈希
import CryptoKit

private func sha256(_ input: String) -> String {
    let inputData = Data(input.utf8)
    let hashedData = SHA256.hash(data: inputData)
    let hashString = hashedData.compactMap {
        String(format: "%02x", $0)
    }.joined()

    return hashString
}
```

### 5.3 Token 安全

#### 不在日志中打印 Token

```swift
// ❌ 错误：不要在日志中打印 token
print("Access token: \(accessToken)")

// ✅ 正确：使用掩码
let maskedToken = String(accessToken.prefix(10)) + "..." + String(accessToken.suffix(4))
print("Access token: \(maskedToken)")
```

#### Token 过期策略

```swift
// 使用短期 access token（5-15 分钟）
// 使用长期 refresh token（7-30 天）

// 后端实现 token 黑名单
// 当用户登出时，将 access token 加入黑名单
```

### 5.4 用户隐私

#### 遵循隐私政策

1. **最小权限原则**：只请求必要的权限
2. **用户同意**：明确告知用户数据用途
3. **数据删除**：提供删除账户和数据的功能

#### Apple 隐私要求

```swift
// Apple Sign-In 必须提供以下功能：
// 1. 删除账户功能
// 2. 停止使用 Apple Sign-In 功能

func deleteAppleAccount(userID: String) {
    // 调用后端删除用户数据
    // 清除本地存储
    try? TokenStorage.deleteAccessToken()
    try? TokenStorage.deleteRefreshToken()
}
```

---

## 6. 测试建议

### 6.1 单元测试

```swift
import XCTest
@testable import MindCanvas

class AuthManagerTests: XCTestCase {

    var authManager: AuthManager!

    override func setUp() {
        super.setUp()
        authManager = AuthManager()
    }

    func testTokenStorage() throws {
        let token = "test_token_12345"

        // 测试存储
        try TokenStorage.saveAccessToken(token)

        // 测试读取
        let retrievedToken = try TokenStorage.getAccessToken()
        XCTAssertEqual(retrievedToken, token)

        // 测试删除
        try TokenStorage.deleteAccessToken()
        XCTAssertThrowsError(try TokenStorage.getAccessToken())
    }
}
```

### 6.2 UI 测试

```swift
import XCTest

class LoginUITests: XCTestCase {

    func testAppleSignInFlow() throws {
        let app = XCUIApplication()
        app.launch()

        // 点击 Apple Sign-In 按钮
        app.buttons["Sign in with Apple"].tap()

        // 等待登录完成
        // ...
    }
}
```

---

## 7. 参考资料

### 官方文档

- [Apple Sign-In - Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/sign-in-with-apple)
- [Apple Sign-In - Authentication Services](https://developer.apple.com/documentation/authenticationservices)
- [Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios)
- [GitHub OAuth Apps](https://docs.github.com/en/developers/apps/building-oauth-apps)
- [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)

### 最佳实践

- [OWASP Mobile Security](https://owasp.org/www-project-mobile-security/)
- [iOS App Security Checklist](https://mobisoftinfotech.com/resources/blog/app-security/ios-app-security-checklist-best-actices)

---

## 总结

实现 iOS 第三方登录需要关注以下核心要点：

1. **Apple Sign-In**：
   - 使用 `AuthenticationServices` 框架
   - 处理首次登录和后续登录的区别
   - 使用 nonce 防止重放攻击
   - 验证凭据状态

2. **Google Sign-In**：
   - 集成官方 GoogleSignIn SDK
   - 后端验证 ID Token
   - 实现自动 token 刷新

3. **GitHub OAuth**：
   - 使用 `ASWebAuthenticationSession`
   - 实现完整的授权码流程
   - 使用短暂会话提高安全性

4. **通用最佳实践**：
   - 使用 Keychain 安全存储 token
   - 实现自动 token 刷新
   - 使用 HTTPS 和证书绑定
   - 完善的错误处理和用户提示
   - 遵循隐私政策和数据保护规范

通过遵循以上最佳实践，可以构建安全、可靠、用户体验良好的第三方登录系统。