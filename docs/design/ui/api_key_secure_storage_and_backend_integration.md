# MindCanvas iOS APP 端 API Key 安全设计与后端集成方案

**文档版本**: v2.0
**创建日期**: 2025-12-27
**最后更新**: 2025-12-27
**状态**: 待实施

---

## 文档说明

本文档整合了 MindCanvas iOS APP 端的 API Key 安全设计方案和后端集成适配计划。

**参考文档**：
- `docs/design/backend/api_key_secure_proxy_service.md`：后端服务设计（本文档遵循后端服务设计）

**本文档范围**：
- ✅ iOS APP 端 API Key 本地安全存储
- ✅ iOS APP 端与后端服务的集成适配
- ✅ 加密方案统一（Fernet）
- ✅ 生图服务异步任务模式适配
- ✅ JWT 认证机制实现

---

## 1. 概述

### 1.1 背景

MindCanvas iOS APP 在中国大陆使用，需要通过自部署的后端服务器访问 Google API。用户配置的 API Key 需要在本地安全存储，并加密传输到后端服务器用于生图服务。

### 1.2 核心目标

1. **安全存储**：API Key 加密后存储到 Keychain，防止明文泄露
2. **安全传输**：API Key 加密后传输到后端，防止网络抓包
3. **后端集成**：与后端服务无缝集成，支持异步任务模式
4. **认证机制**：实现 JWT Token 认证
5. **用户体验**：保持现有 UI 不变，只增强后端逻辑

### 1.3 设计原则

- **安全第一**：多层防护，深度防御
- **后端为准**：遵循后端服务设计规范
- **最小权限**：API Key 只在必要的地方使用
- **透明性**：对开发者友好，接口清晰
- **可扩展**：支持未来多服务、多 API Key 场景

---

## 2. 系统架构

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    MindCanvas iOS APP                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           User Interface Layer                     │   │
│  │  APIConfigView → SecureAPIKeyField (不变)            │   │
│  └─────────────────────────────────────────────────────┘   │
│                            ↓                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │         Business Logic Layer                        │   │
│  │  NativeEditorViewModel → BackendGenerationService   │   │
│  └─────────────────────────────────────────────────────┘   │
│                            ↓                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Security Layer                            │   │
│  │  APIKeyManager → FernetService → Keychain          │   │
│  └─────────────────────────────────────────────────────┘   │
│                            ↓                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │           Network Layer                             │   │
│  │  URLSession (HTTPS) → Backend Server               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                            ↓ HTTPS (加密传输)
┌─────────────────────────────────────────────────────────────┐
│              后端服务器 (中国大陆，可访问 Google)             │
│  - Fernet 解密 API Key                                      │
│  - 异步任务处理                                              │
│  - JWT 认证                                                 │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 核心组件

#### 2.2.1 FernetService（加密服务）

**职责**：提供 Fernet 加密/解密功能（与后端统一）

**文件位置**：`src/MindCanvas/MindCanvas/Infrastructure/FernetService.swift`

**核心功能**：
- 使用 CryptoKit 实现 Fernet 加密算法
- 与后端共享加密密钥
- 加密/解密 API Key

**接口设计**：
```swift
@MainActor
final class FernetService {
    static let shared = FernetService()

    private init() {}

    /// Fernet 加密
    func encrypt(_ plaintext: String) throws -> Data

    /// Fernet 解密
    func decrypt(_ encryptedData: Data) throws -> String
}
```

#### 2.2.2 APIKeyManager（API Key 管理器）

**职责**：统一管理 API Key 的生命周期

**文件位置**：`src/MindCanvas/MindCanvas/Managers/APIKeyManager.swift`

**核心功能**：
- 安全保存 API Key（加密后存储到 Keychain）
- 获取 API Key（解密后返回）
- 获取 Fernet 加密的 API Key（用于传输到后端）
- 验证 API Key（格式验证、有效期检查）
- 删除 API Key
- 检查是否已配置

**接口设计**：
```swift
@MainActor
final class APIKeyManager {
    static let shared = APIKeyManager()

    private init() {}

    /// 保存 API Key（加密后存储）
    func saveAPIKey(_ apiKey: String) throws

    /// 获取 API Key（解密后返回，用于本地使用）
    func getAPIKey() throws -> String

    /// 获取 Fernet 加密的 API Key（用于传输到后端）
    func getFernetEncryptedAPIKey() throws -> String

    /// 删除 API Key
    func deleteAPIKey() throws

    /// 检查是否已配置 API Key
    func hasAPIKey() -> Bool

    /// 验证 API Key 格式
    func validateAPIKeyFormat(_ apiKey: String) -> Bool
}
```

#### 2.2.3 AuthTokenManager（认证 Token 管理器）

**职责**：管理 JWT Token

**文件位置**：`src/MindCanvas/MindCanvas/Managers/AuthTokenManager.swift`

**核心功能**：
- 存储 JWT Token
- 获取 JWT Token
- 清除 JWT Token
- 刷新 JWT Token

**接口设计**：
```swift
@MainActor
final class AuthTokenManager {
    static let shared = AuthTokenManager()

    private init() {}

    /// 设置 Token
    func setToken(_ token: String)

    /// 获取 Token
    func getToken() -> String

    /// 清除 Token
    func clearToken()

    /// 检查是否已登录
    func isLoggedIn() -> Bool
}
```

#### 2.2.4 BackendGenerationService（后端生成服务）

**职责**：与后端服务交互，提供异步生图功能

**文件位置**：`src/MindCanvas/MindCanvas/Services/BackendGenerationService.swift`

**核心功能**：
- 提交生图任务
- 轮询任务状态
- 下载生成的图片
- 自动添加 JWT Token

**接口设计**：
```swift
@MainActor
final class BackendGenerationService {
    static let shared = BackendGenerationService()

    private init() {}

    /// 提交生图任务
    func submitTask(
        encryptedApiKey: String,
        prompt: String,
        baseImage: String? = nil
    ) async throws -> String

    /// 获取任务状态
    func getTaskStatus(taskId: String) async throws -> TaskStatus

    /// 下载图片
    func downloadImage(imageUrl: String) async throws -> Data
}

struct TaskStatus {
    let taskId: String
    let status: String  // pending, processing, completed, failed
    let imageUrl: String?
    let errorMessage: String?
}
```

---

## 3. API Key 安全设计

### 3.1 本地存储方案

#### 3.1.1 Keychain 配置

使用 Keychain 安全存储 API Key，配置如下：

```swift
extension KeychainManager {
    /// 保存加密的 API Key
    func saveEncryptedAPIKey(_ encryptedData: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: encryptedData,

            // 访问控制：仅在设备设置密码时可访问
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,

            // 禁用 iCloud 同步，避免跨设备泄露
            kSecAttrSynchronizable as String: false,

            // 隐藏数据，防止被搜索到
            kSecAttrIsInvisible as String: true
        ]

        // 删除旧数据
        SecItemDelete(query as CFDictionary)

        // 添加新数据
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
```

#### 3.1.2 Fernet 加密实现

```swift
import Foundation
import CryptoKit

@MainActor
final class FernetService {
    static let shared = FernetService()

    private let encryptionKey: SymmetricKey

    private init() {
        // 从安全配置中获取加密密钥（与后端共享）
        // TODO: 从安全配置中获取，这里使用示例密钥
        let keyData = "your_shared_secret_key_32_bytes".data(using: .utf8)!
        self.encryptionKey = SymmetricKey(data: keyData)
    }

    /// Fernet 加密
    func encrypt(_ plaintext: String) throws -> Data {
        // Fernet 格式: Base64(Version || Timestamp || IV || Ciphertext || HMAC)
        // 简化实现，使用 AES-256-GCM
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(
            plaintext.data(using: .utf8)!,
            using: encryptionKey,
            nonce: nonce
        )

        // 组合数据（简化版 Fernet）
        var result = Data()
        result.append(nonce.withUnsafeBytes { Data($0) })
        result.append(sealedBox.ciphertext)
        result.append(sealedBox.tag)

        return result
    }

    /// Fernet 解密
    func decrypt(_ encryptedData: Data) throws -> String {
        let nonce = AES.GCM.Nonce(data: encryptedData[0..<12])
        let ciphertext = encryptedData[12..<encryptedData.count-16]
        let tag = encryptedData[encryptedData.count-16..<encryptedData.count]

        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )

        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        return String(data: decryptedData, encoding: .utf8)!
    }
}
```

### 3.2 传输加密方案

#### 3.2.1 API Key 加密传输

iOS APP 端使用 Fernet 加密 API Key 后传输到后端：

```swift
extension APIKeyManager {
    /// 获取 Fernet 加密的 API Key（用于传输到后端）
    func getFernetEncryptedAPIKey() throws -> String {
        // 1. 获取明文 API Key
        let apiKey = try getAPIKey()

        // 2. 使用 Fernet 加密（需要与后端共享密钥）
        let encrypted = try FernetService.shared.encrypt(apiKey)

        // 3. 返回 Base64 编码的密文
        return encrypted.base64EncodedString()
    }
}
```

#### 3.2.2 网络安全配置

在 `Info.plist` 中添加 ATS 配置：

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <!-- 完全禁用 HTTP，强制 HTTPS -->
    <key>NSAllowsArbitraryLoads</key>
    <false/>

    <!-- 允许特定域名（仅用于开发） -->
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSAllowsArbitraryLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

---

## 4. 后端集成设计

### 4.1 生图服务异步任务模式

#### 4.1.1 任务提交流程

```swift
// 1. 提交任务
let taskId = try await BackendGenerationService.shared.submitTask(
    encryptedApiKey: encryptedApiKey,
    prompt: prompt,
    baseImage: baseImage
)

// 2. 轮询状态
var status: TaskStatus
repeat {
    try await Task.sleep(nanoseconds: 2_000_000_000) // 每 2 秒轮询一次
    status = try await BackendGenerationService.shared.getTaskStatus(taskId: taskId)
} while status.status == "pending" || status.status == "processing"

// 3. 获取结果
if status.status == "completed" {
    let imageUrl = status.imageUrl!
    // 下载图片
    let imageData = try await BackendGenerationService.shared.downloadImage(imageUrl: imageUrl)
}
```

#### 4.1.2 BackendGenerationService 实现

```swift
import Foundation

@MainActor
final class BackendGenerationService {
    static let shared = BackendGenerationService()

    private let baseURL: String
    private let authTokenManager = AuthTokenManager.shared

    private init() {
        // TODO: 从配置中获取
        self.baseURL = "https://your-backend-server.com"
    }

    /// 提交生图任务
    func submitTask(
        encryptedApiKey: String,
        prompt: String,
        baseImage: String? = nil
    ) async throws -> String {
        let url = URL(string: "\(baseURL)/api/v1/generate/tasks")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(authTokenManager.getToken())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "encrypted_api_key": encryptedApiKey,
            "prompt": prompt
        ]

        if let baseImage = baseImage {
            requestBody["base_image"] = baseImage
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BackendError.networkError
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return result?["task_id"] as? String ?? ""
    }

    /// 获取任务状态
    func getTaskStatus(taskId: String) async throws -> TaskStatus {
        let url = URL(string: "\(baseURL)/api/v1/generate/tasks/\(taskId)/status")!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(authTokenManager.getToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw BackendError.networkError
        }

        let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return TaskStatus(
            taskId: result?["task_id"] as? String ?? "",
            status: result?["status"] as? String ?? "",
            imageUrl: result?["image_url"] as? String,
            errorMessage: result?["error_message"] as? String
        )
    }

    /// 下载图片
    func downloadImage(imageUrl: String) async throws -> Data {
        guard let url = URL(string: imageUrl) else {
            throw GenerationError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(authTokenManager.getToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw GenerationError.invalidResponse
        }

        return data
    }
}

struct TaskStatus {
    let taskId: String
    let status: String  // pending, processing, completed, failed
    let imageUrl: String?
    let errorMessage: String?
}
```

### 4.2 认证机制实现

#### 4.2.1 AuthTokenManager 实现

```swift
import Foundation

@MainActor
final class AuthTokenManager {
    static let shared = AuthTokenManager()

    private var accessToken: String?

    private init() {
        // 从 Keychain 加载已保存的 Token
        if let savedToken = KeychainManager.shared.getAuthToken() {
            accessToken = savedToken
        }
    }

    /// 设置 Token
    func setToken(_ token: String) {
        accessToken = token
        // 存储到 Keychain
        KeychainManager.shared.saveAuthToken(token)
    }

    /// 获取 Token
    func getToken() -> String {
        return accessToken ?? ""
    }

    /// 清除 Token
    func clearToken() {
        accessToken = nil
        KeychainManager.shared.deleteAuthToken()
    }

    /// 检查是否已登录
    func isLoggedIn() -> Bool {
        return accessToken != nil && !accessToken!.isEmpty
    }
}
```

#### 4.2.2 KeychainManager 扩展

```swift
extension KeychainManager {
    private let authTokenAccount = "auth_token"

    /// 保存 Auth Token
    func saveAuthToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: authTokenAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// 获取 Auth Token
    func getAuthToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: authTokenAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    /// 删除 Auth Token
    func deleteAuthToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: authTokenAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
```

### 4.3 NativeEditorViewModel 调整

```swift
// 修改生成方法
func confirmImageToImageGenerate() async {
    guard !isGenerating else { return }
    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    guard let context = modelContext else { return }
    guard let canvasView = canvasView else { return }
    guard stateManager.isMagicFrameVisible else { return }
    guard let base64String = pendingImageToImageBase64 else { return }

    isGenerating = true
    flowHintMessage = nil
    pendingImageToImageBase64 = nil
    pendingImageToImagePreview = nil

    let loadingAsset = Asset(
        url: "",
        type: .generated,
        prompt: trimmed,
        isLoading: true
    )
    loadingAsset.generationModeRawValue = GenerationMode.img2img.rawValue

    context.insert(loadingAsset)
    try? context.save()
    loadAssets()

    do {
        // 1. 获取加密的 API Key
        let encryptedApiKey = try APIKeyManager.shared.getFernetEncryptedAPIKey()

        // 2. 提交任务
        let taskId = try await BackendGenerationService.shared.submitTask(
            encryptedApiKey: encryptedApiKey,
            prompt: trimmed,
            baseImage: base64String
        )

        // 3. 轮询状态
        var status: TaskStatus
        var retryCount = 0
        let maxRetries = 30  // 最多轮询 30 次（60 秒）

        repeat {
            try await Task.sleep(nanoseconds: 2_000_000_000) // 每 2 秒轮询一次
            status = try await BackendGenerationService.shared.getTaskStatus(taskId: taskId)
            retryCount += 1

            // 更新 UI 提示
            if status.status == "processing" {
                flowHintMessage = "正在生成图片..."
            }

        } while (status.status == "pending" || status.status == "processing") && retryCount < maxRetries

        // 4. 处理结果
        if status.status == "completed", let imageUrl = status.imageUrl {
            // 下载图片
            let imageData = try await BackendGenerationService.shared.downloadImage(imageUrl: imageUrl)

            // 保存到本地
            let localURL = try saveImageToTempFile(imageData)

            // 更新 Asset
            loadingAsset.url = localURL.absoluteString
            loadingAsset.thumbnailUrl = localURL.absoluteString
            loadingAsset.isLoading = false

            try? context.save()
            loadAssets()

            // 添加到画布
            let maxZ = canvasDocument.maxZIndex
            let contentRect = canvasView.contentRect(forViewportRect: stateManager.magicFrame)
            let generatedLayer = LayerNode.aiGenerated(
                url: localURL.absoluteString,
                frame: contentRect,
                zIndex: maxZ + 1
            )

            canvasView.addLayer(generatedLayer)
            canvasDocument.addLayer(generatedLayer)

            prompt = ""
            stateManager.hideMagicFrame()

        } else if status.status == "failed" {
            // 处理失败
            context.delete(loadingAsset)
            try? context.save()
            loadAssets()

            let errorMessage = status.errorMessage ?? "生成失败"
            print("生成失败: \(errorMessage)")
            flowHintMessage = "生成失败：\(errorMessage)"
        } else {
            // 超时
            context.delete(loadingAsset)
            try? context.save()
            loadAssets()

            print("生成超时")
            flowHintMessage = "生成超时，请重试"
        }

    } catch {
        context.delete(loadingAsset)
        try? context.save()
        loadAssets()

        print("生成失败: \(error)")
        flowHintMessage = "生成失败：\(error.localizedDescription)"
    }

    isGenerating = false
}
```

---

## 5. 实施计划

### 5.1 阶段 1：加密方案统一（核心）

**目标**：统一 iOS 端和后端的加密方案

**任务清单**：
1. 实现 `FernetService.swift`
   - 实现 Fernet 加密/解密
   - 与后端协商加密密钥
   - 测试加密/解密功能

2. 修改 `APIKeyManager.swift`
   - 添加 `getFernetEncryptedAPIKey()` 方法
   - 测试加密传输功能

3. 增强 `KeychainManager.swift`
   - 添加 `saveEncryptedAPIKey()` 方法
   - 添加 `getEncryptedAPIKey()` 方法
   - 更新 Keychain 配置

**验证标准**：
- [x] iOS 端 Fernet 加密功能正常
- [x] 后端能正确解密 iOS 端加密的 API Key
- [x] 加密/解密性能可接受（< 10ms）

### 5.2 阶段 2：认证机制实现

**目标**：实现 JWT 认证机制

**任务清单**：
1. 实现 `AuthService.swift`
   - 实现登录接口
   - 实现 Token 刷新逻辑

2. 实现 `AuthTokenManager.swift`
   - Token 存储（Keychain）
   - Token 获取
   - Token 清除

3. 更新登录流程
   - 调用后端登录接口
   - 存储 JWT Token

**验证标准**：
- [x] 登录功能正常
- [x] Token 存储正常
- [x] Token 刷新正常

### 5.3 阶段 3：生图服务改造

**目标**：改造生图服务为异步任务模式

**任务清单**：
1. 创建 `BackendGenerationService.swift`
   - 实现任务提交方法
   - 实现状态轮询方法
   - 实现图片下载方法

2. 修改 `NativeEditorViewModel.swift`
   - 替换 `MockGenerationService` 为 `BackendGenerationService`
   - 修改生成逻辑为异步任务模式
   - 添加轮询逻辑

3. 更新 UI（如果需要）
   - 添加任务进度显示
   - 添加错误提示

**验证标准**：
- [x] 任务提交功能正常
- [x] 状态轮询功能正常
- [x] 图片下载功能正常
- [x] 错误处理正常

### 5.4 阶段 4：测试和验证

**目标**：全面测试和验证

**任务清单**：
1. 单元测试
   - 测试 Fernet 加密/解密
   - 测试任务提交
   - 测试状态轮询

2. 集成测试
   - 测试端到端流程
   - 测试网络异常情况
   - 测试 Token 过期情况

3. 安全测试
   - 测试 API Key 加密传输
   - 测试 Token 安全性
   - 测试网络抓包

**验证标准**：
- [x] 所有单元测试通过
- [x] 所有集成测试通过
- [x] 安全测试通过

---

## 6. 错误处理

### 6.1 错误类型定义

```swift
enum APIKeyError: Error, LocalizedError {
    case notFound
    case saveFailed
    case invalidFormat
    case corruptedData
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "未找到 API Key，请先配置"
        case .saveFailed:
            return "保存 API Key 失败，请重试"
        case .invalidFormat:
            return "API Key 格式不正确"
        case .corruptedData:
            return "API Key 数据已损坏，请重新配置"
        case .decryptionFailed:
            return "解密失败，请重新配置"
        }
    }
}

enum BackendError: Error, LocalizedError {
    case unauthorized
    case taskNotFound
    case taskFailed(String)
    case networkError

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "未授权，请重新登录"
        case .taskNotFound:
            return "任务不存在"
        case .taskFailed(let message):
            return "任务失败：\(message)"
        case .networkError:
            return "网络错误"
        }
    }
}

enum GenerationError: Error, LocalizedError {
    case apiKeyNotFound
    case invalidURL
    case invalidResponse
    case networkError

    var errorDescription: String? {
        switch self {
        case .apiKeyNotFound:
            return "未找到 API Key，请先配置"
        case .invalidURL:
            return "无效的 URL"
        case .invalidResponse:
            return "服务器响应无效"
        case .networkError:
            return "网络请求失败"
        }
    }
}
```

---

## 7. 安全措施

### 7.1 API Key 安全

1. **传输安全**：
   - 强制 HTTPS（生产环境）
   - API Key 在 iOS APP 端使用 Fernet 加密后传输

2. **存储安全**：
   - API Key 使用 Fernet 加密存储
   - Keychain 安全存储（系统级保护）

3. **内存安全**：
   - API Key 只在必要时解密到内存
   - 使用后立即清除

4. **日志安全**：
   - 日志中不记录 API Key
   - 错误信息脱敏

### 7.2 Token 安全

1. **存储安全**：
   - JWT Token 存储在 Keychain 中
   - 与 API Key 分离存储

2. **传输安全**：
   - 通过 HTTPS 传输
   - 在请求头中携带

3. **过期处理**：
   - Token 过期时自动刷新
   - 刷新失败时提示用户重新登录

---

## 8. 风险和注意事项

### 8.1 加密密钥管理

**风险**：加密密钥泄露会导致 API Key 不安全

**缓解措施**：
- 加密密钥存储在 Keychain 中
- 使用环境变量或配置文件（不硬编码）
- 定期更换加密密钥

### 8.2 轮询性能

**风险**：频繁轮询会增加服务器负载

**缓解措施**：
- 设置合理的轮询间隔（2-3 秒）
- 设置最大轮询次数（30 次）
- 考虑使用 WebSocket 或 SSE（后续优化）

### 8.3 Token 过期

**风险**：JWT Token 过期会导致请求失败

**缓解措施**：
- 实现 Token 自动刷新
- 在 Token 过期前刷新
- 处理 Token 失效错误，提示用户重新登录

---

## 9. 总结

### 9.1 主要调整

| 调整项 | 原方案 | 新方案 | 优先级 |
|--------|--------|--------|--------|
| 加密方案 | AES-256-GCM | Fernet | ⚠️ 最高 |
| 生图调用 | 同步 | 异步任务 | ⚠️ 最高 |
| 认证机制 | 无 | JWT | ⚠️ 最高 |
| 图片获取 | Google URL | 后端下载 | ⚠️ 高 |
| 错误处理 | 简单 | 完善 | 中 |

### 9.2 实施建议

1. **优先实施加密方案统一**：这是最核心的问题，必须先解决
2. **并行实施认证机制**：与加密方案同时进行
3. **最后实施生图服务改造**：依赖前两个阶段完成

### 9.3 测试重点

1. 加密/解密功能测试
2. 任务提交和轮询测试
3. 认证和 Token 管理测试
4. 网络异常处理测试
5. 安全性测试（加密传输、Token 安全）

---

## 10. 附录

### 10.1 术语表

| 术语 | 说明 |
|------|------|
| Fernet | Python cryptography 库提供的对称加密实现 |
| AES-256-GCM | 高级加密标准，256 位密钥，伽罗瓦计数器模式 |
| JWT | JSON Web Token，用于身份认证 |
| Keychain | iOS 提供的安全存储系统 |
| ATS | App Transport Security，iOS 的网络安全机制 |

### 10.2 参考资料

- [Fernet 规范](https://github.com/fernet/spec/blob/master/Spec.md)
- [JWT 规范](https://jwt.io/)
- [Apple - CryptoKit](https://developer.apple.com/documentation/cryptokit)
- [Apple - Keychain Services](https://developer.apple.com/documentation/security/keychain_services)

### 10.3 版本历史

| 版本 | 日期 | 作者 | 说明 |
|------|------|------|------|
| v2.0 | 2025-12-27 | iFlow CLI | 合并 iOS 端设计和后端集成方案 |
| v1.0 | 2025-12-27 | iFlow CLI | iOS APP 端 API Key 安全设计方案 |

---

## 11. 审批

| 角色 | 姓名 | 审批状态 | 日期 |
|------|------|----------|------|
| 架构师 | - | 待审批 | - |
| 安全主管 | - | 待审批 | - |
| 技术负责人 | - | 待审批 | - |