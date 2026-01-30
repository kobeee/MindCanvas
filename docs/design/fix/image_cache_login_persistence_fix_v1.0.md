# 图片缓存与登录状态持久化问题修复方案 v1.0

## 文档信息

- **版本**: 1.0
- **日期**: 2026-01-30
- **作者**: Claude Opus 4.5
- **状态**: 待实施

---

## 问题概述

用户反馈了4个问题：

| 序号 | 问题描述 | 严重程度 |
|------|----------|----------|
| 1 | 图片加载成功后，重启应用还要继续加载 | **高** |
| 2 | 新生成的图片自动添加到画布 | **中** |
| 3 | 新生成的图片在资源库点击"+"添加到画布无效 | **高** |
| 4 | 登录状态没有记载，每次重启应用登录状态就没了 | **高** |

**用户补充**：图片生成成功后，自动添加到了画布，且资源库也正常显示了图片，说明图片已经下载成功。

---

## 问题1：图片缓存失效

### 根本原因

**Swift 的 `String.hash` 在每次应用启动时都会改变**（安全特性）

```swift
// ImageStorageService.swift 第 233 行
let hash = remoteURL.absoluteString.hash  // 每次启动值不同！
let fileName = "cached_\(abs(hash)).jpg"
```

**问题流程**：
```
第一次启动：URL → hash = 12345 → 文件名 "cached_12345.jpg"
重启应用：同一个 URL → hash = 67890 → 查找 "cached_67890.jpg" → 文件不存在 → 重新下载
```

### 修复方案

**使用 CryptoKit SHA256 生成稳定的缓存键**

#### 修改文件：`ImageStorageService.swift`

**1. 添加 import 和扩展**（文件顶部，约第 10 行后）

```swift
import CryptoKit

extension String {
    /// 生成稳定的 SHA256 哈希值（用于缓存键）
    var stableCacheKey: String {
        let inputData = Data(self.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined().prefix(16).description
    }
}
```

**2. 修改 `downloadAndSaveImageWithRelativePath` 方法**（约第 233 行）

```swift
// 修改前
let hash = remoteURL.absoluteString.hash
let fileName = "cached_\(abs(hash)).jpg"

// 修改后
let hash = remoteURL.absoluteString.stableCacheKey
let fileName = "cached_\(hash).jpg"
```

**3. 修改 `getCachedURL` 方法**（约第 638 行）

```swift
// 修改前
private func getCachedURL(for remoteURL: URL) -> URL? {
    let hash = remoteURL.absoluteString.hash
    let fileName = "cached_\(abs(hash)).jpg"
    // ...
}

// 修改后
private func getCachedURL(for remoteURL: URL) -> URL? {
    let hash = remoteURL.absoluteString.stableCacheKey
    let fileName = "cached_\(hash).jpg"
    let cachedURL = storageDirectory.appendingPathComponent(fileName)

    if fileExists(at: cachedURL) {
        return cachedURL
    }
    return nil
}
```

### 测试用例

1. 生成图片 → 完全关闭 App → 重新打开 → 验证图片立即显示（无需重新加载）

---

## 问题2：新生成图片自动添加到画布

### 根本原因

`confirmImageToImageGenerate()` 方法中有自动添加代码（第 628-629 行）：

```swift
canvasView.addLayer(generatedLayer)
canvasDocument.addLayer(generatedLayer)
```

### 修复方案

**删除图生图流程中的自动添加代码**

#### 修改文件：`NativeEditorViewModel.swift`

**修改 `confirmImageToImageGenerate` 方法**（约第 618-632 行）

```swift
// 删除以下代码（第 618-629 行）
let maxZ = canvasDocument.maxZIndex
let contentRect = canvasView.contentRect(forViewportRect: stateManager.magicFrame)

let generatedLayer = LayerNode.aiGenerated(
    url: localImagePath ?? response.imageUrl,
    frame: contentRect,
    zIndex: maxZ + 1
)

canvasView.addLayer(generatedLayer)
canvasDocument.addLayer(generatedLayer)

// 保留以下代码
prompt = ""
stateManager.hideMagicFrame()
```

### 测试用例

1. 执行图生图 → 验证图片只出现在资源库，画布上没有新图片
2. 在资源库点击"+"按钮 → 验证图片正常添加到画布

---

## 问题3：资源库添加到画布无效

### 根本原因（更新）

**经过进一步排查，发现真正的问题是触控区域被图片遮挡**

用户发现的关键线索：资源库的图片如果长度太长的话，会影响"+"添加按钮的点击，导致触发不灵敏。

#### 代码位置
`src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift` 第 1313-1390 行 `NativeAssetCardView`

#### 布局结构
```swift
VStack(spacing: 8) {
    // 图片预览 - 固定高度 150
    CachedAsyncImage(urlString: asset.url, localPath: asset.localPath, contentMode: .fill)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onTap)

    // 操作按钮 - 在图片下方
    if isSelected && !asset.isLoading {
        HStack(spacing: 12) {
            Button { onAddToCanvas() } ...  // "+" 按钮
            Button { onDownload() } ...     // 下载按钮
            Button { onDelete() } ...       // 删除按钮
        }
        .padding(.vertical, 8)
    }
}
```

#### 问题分析

1. **`contentMode: .fill` 的行为**：
   - 图片会填充整个容器，保持宽高比
   - 对于竖图（高度 > 宽度），图片会在**垂直方向**超出容器边界
   - 对于横图（宽度 > 高度），图片会在**水平方向**超出容器边界

2. **`.clipShape()` 只裁剪视觉，不裁剪触控区域**：
   - `clipShape` 只影响渲染，不影响 hit testing
   - 超出容器的图片部分虽然看不见，但仍然可以接收触控事件

3. **`.onTapGesture` 的触控区域**：
   - 添加在 `CachedAsyncImage` 上的 `onTapGesture` 会覆盖整个图片的实际尺寸
   - 当图片超出可见区域时，触控区域也会超出

4. **为什么新图片有问题，旧图片没问题**：
   - 新生成的图片可能是竖图或非标准比例
   - 旧图片可能恰好是接近 4:3 或更宽的横图，超出部分较少
   - AI 生成的图片比例不固定，可能产生各种比例的图片

#### 问题示意图

```
正常情况（横图，宽高比 > 容器）：
┌─────────────────────────┐
│  ┌───────────────────┐  │  <- 图片在水平方向超出
│  │                   │  │     但超出部分在容器外
│  │      图片         │  │     不影响下方按钮
│  │                   │  │
│  └───────────────────┘  │
├─────────────────────────┤
│    [+]  [↓]  [删除]     │  <- 按钮正常可点击
└─────────────────────────┘

问题情况（竖图，宽高比 < 容器）：
┌─────────────────────────┐
│  ┌───────────────────┐  │
│  │                   │  │
│  │      图片         │  │
│  │                   │  │
│  └───────────────────┘  │
│  │   图片超出部分    │  │  <- 图片在垂直方向超出
│  │   (不可见但可触控) │  │     遮挡了下方按钮
├──┼───────────────────┼──┤
│  │ [+]  [↓]  [删除]  │  │  <- 按钮被图片触控区域遮挡
└──┴───────────────────┴──┘
```

### 修复方案

**使用 `.clipped()` 裁剪触控区域**

在 `CachedAsyncImage` 外层添加 `.clipped()` 修饰符，这会同时裁剪视觉和触控区域。

#### 修改文件：`NativeEditorView.swift`

**修改位置**：`NativeAssetCardView` 第 1325-1337 行

**修改前**：
```swift
CachedAsyncImage(urlString: asset.url, localPath: asset.localPath, contentMode: .fill)
    .frame(height: 150)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
    )
    .overlay {
        if asset.isLoading {
            AssetLoadingView()
        }
    }
    .onTapGesture(perform: onTap)
```

**修改后**：
```swift
CachedAsyncImage(urlString: asset.url, localPath: asset.localPath, contentMode: .fill)
    .frame(height: 150)
    .clipped()  // 关键修复：裁剪触控区域
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
        RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
    )
    .overlay {
        if asset.isLoading {
            AssetLoadingView()
        }
    }
    .onTapGesture(perform: onTap)
```

**修复原理**：
- `.clipped()` 会同时裁剪视觉和触控区域
- `.clipShape()` 只裁剪视觉（用于圆角效果）
- 两者配合使用，既保持圆角视觉效果，又限制触控区域

### 测试用例

#### 测试准备
1. 生成一张竖图（高度 > 宽度）
2. 生成一张横图（宽度 > 高度）
3. 生成一张正方形图片

#### 测试步骤
1. 选中竖图，点击"+"按钮，验证能否正常添加到画布
2. 选中横图，点击"+"按钮，验证能否正常添加到画布
3. 选中正方形图片，点击"+"按钮，验证能否正常添加到画布
4. 下载按钮和删除按钮也能正常响应点击

#### 预期结果
- 所有情况下，"+"按钮都能正常响应点击
- 下载按钮和删除按钮也能正常响应点击

---

## 问题4：登录状态不持久

### 根本原因

1. **Keychain 缺少 `kSecAttrAccessible` 配置**：设备重启后首次解锁前可能无法访问
2. **Token 保存没有检查返回值**：保存失败时没有任何提示
3. **异常处理过于宽泛**：任何异常都返回"未登录"

### 修复方案

**修复 Keychain 配置和错误处理**

#### 修改文件：`KeychainManager.swift`

**修改 `save` 方法**

```swift
func save(_ key: String, value: String) -> Bool {
    guard let data = value.data(using: .utf8) else {
        print("[KeychainManager] 保存失败：无法将字符串转换为 Data")
        return false
    }

    // 先删除旧数据
    let deleteQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key
    ]
    SecItemDelete(deleteQuery as CFDictionary)

    // 添加新数据
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock  // 关键配置
    ]

    let status = SecItemAdd(query as CFDictionary, nil)

    if status != errSecSuccess {
        print("[KeychainManager] 保存失败: \(key), 错误码: \(status)")
        return false
    }

    print("[KeychainManager] 保存成功: \(key)")
    return true
}
```

**修改 `get` 方法**

```swift
func get(_ key: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var dataTypeRef: AnyObject?
    var status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

    // 重试机制：某些情况下首次查询可能失败
    if status == errSecInteractionNotAllowed {
        print("[KeychainManager] 首次查询被拒绝，等待后重试...")
        Thread.sleep(forTimeInterval: 0.1)
        status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
    }

    guard status == errSecSuccess,
          let data = dataTypeRef as? Data,
          let value = String(data: data, encoding: .utf8) else {
        if status != errSecItemNotFound {
            print("[KeychainManager] 读取失败: \(key), 错误码: \(status)")
        }
        return nil
    }

    return value
}
```

#### 修改文件：`AuthManager.swift`

**修改 `checkAuthentication` 方法**

```swift
func checkAuthentication() async {
    print("[AuthManager] 开始检查认证状态...")

    // 检查 Keychain 中是否有 Token
    let hasAccessToken = keychainManager.get("access_token") != nil
    let hasRefreshToken = keychainManager.get("refresh_token") != nil
    let hasExpiresAt = keychainManager.get("token_expires_at") != nil

    print("[AuthManager] Keychain 状态:")
    print("  - access_token: \(hasAccessToken)")
    print("  - refresh_token: \(hasRefreshToken)")
    print("  - token_expires_at: \(hasExpiresAt)")

    if authService.isLoggedIn() {
        print("[AuthManager] Token 有效，用户已登录")
        isAuthenticated = true
        isGuestMode = false
        await loadCurrentUser()
    } else if hasRefreshToken {
        print("[AuthManager] Token 已过期，尝试刷新...")
        do {
            let refreshed = try await authService.refreshToken()
            if refreshed {
                print("[AuthManager] Token 刷新成功")
                isAuthenticated = true
                isGuestMode = false
                await loadCurrentUser()
            } else {
                print("[AuthManager] Token 刷新失败，需要重新登录")
                isAuthenticated = false
                isGuestMode = false
            }
        } catch {
            print("[AuthManager] Token 刷新异常: \(error)")
            isAuthenticated = false
            isGuestMode = false
        }
    } else {
        print("[AuthManager] 没有有效的登录凭证")
        isAuthenticated = false
        isGuestMode = false
        currentUser = nil
    }

    isInitialized = true
    print("[AuthManager] 认证检查完成: isAuthenticated=\(isAuthenticated)")
}
```

### 测试用例

1. 登录 → 完全关闭 App → 重新打开 → 验证自动恢复登录状态
2. 查看控制台日志，确认 Keychain 读写正常

---

## 实施计划

### 优先级排序

| 优先级 | 问题 | 修复文件 | 修改量 |
|--------|------|----------|--------|
| **P0** | 资源库添加无效（触控区域问题） | `NativeEditorView.swift` | 1 行 |
| **P0** | 图片缓存失效 | `ImageStorageService.swift` | 约 15 行 |
| **P0** | 登录状态不持久 | `KeychainManager.swift`, `AuthManager.swift` | 约 50 行 |
| **P2** | 自动添加到画布 | `NativeEditorViewModel.swift` | 删除约 10 行 |

### 修改文件清单

1. `NativeEditorView.swift` - 在 `NativeAssetCardView` 中添加 `.clipped()` 修饰符
2. `ImageStorageService.swift` - 添加 SHA256 扩展，修改缓存键生成
3. `KeychainManager.swift` - 添加 `kSecAttrAccessible` 配置，增强日志
4. `AuthManager.swift` - 增强认证检查逻辑和日志
5. `NativeEditorViewModel.swift` - 删除自动添加代码

### 验证检查清单

- [ ] 资源库添加：点击"+"能正常添加到画布（竖图、横图、正方形图都测试）
- [ ] 图片缓存：重启后能从缓存加载
- [ ] 登录状态：重启后保持登录
- [ ] 图生图：不再自动添加到画布

---

## 参考资料

1. [Swift String.hash 不稳定问题](https://stackoverflow.com/questions/35882103/hash-value-of-string-that-would-be-stable-across-ios-releases)
2. [CryptoKit SHA256 使用指南](https://ssojet.com/hashing/sha-256-in-swift)
3. [Keychain kSecAttrAccessible 配置](https://softwarepatternslexicon.com/swift/security-patterns/secure-storage-with-keychain-access/)
