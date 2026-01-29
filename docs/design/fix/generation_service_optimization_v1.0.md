# 生图服务优化方案 v1.0

## 文档信息

| 项目 | 内容 |
|------|------|
| 版本 | v1.0 |
| 日期 | 2026-01-29 |
| 状态 | 待实施 |
| 优先级 | P0 |

---

## 一、问题概述

### 1.1 用户反馈

1. **错误信息不友好**：返回503、timeout、60s等技术性错误，体验差
2. **图片下载异常**：后端生成成功，但iOS端下载过程出现问题
   - 生成动画结束后，切换到转圈圈
   - 转圈圈没有填满资源栏格子，看起来是"一条东西在格子正中间"
   - 最终显示兜底图片

### 1.2 问题分类

| 类别 | 问题 | 严重程度 |
|------|------|---------|
| UI体验 | CachedAsyncImage loading状态没有填满格子 | P0 |
| 用户体验 | 错误信息直接暴露技术细节 | P0 |
| 稳定性 | iOS轮询超时 < 后端处理超时 | P1 |
| 可靠性 | 图片下载失败无重试 | P2 |

---

## 二、深度分析

### 2.1 图片下载loading状态问题（核心问题）

#### 问题现象

用户描述："生成动画结束后，切换到转圈圈，但转圈圈没有填满格子，看起来是一条东西在格子正中间"

#### 根因分析

**状态流转图**：

```
[1] asset.isLoading = true
    ↓
    显示 AssetLoadingView（呼吸动画）
    - 有背景色 Color(white: 0.97)
    - 有 .frame(height: 150)
    - 填满整个格子
    ↓
[2] 后端返回 imageUrl，asset.isLoading = false
    ↓
    AssetLoadingView 消失（因为 if asset.isLoading 条件不满足）
    ↓
[3] CachedAsyncImage 开始加载图片
    内部 isLoading = true
    ↓
    显示 ProgressView()
    - 没有背景色！
    - 没有填满frame！
    - 只是一个小转圈圈
    ↓
[4] 用户看到"一条东西在格子正中间"
```

**代码对比**：

```swift
// AssetLoadingView（呼吸动画）- 有背景，填满格子
var body: some View {
    GeometryReader { geometry in
        ZStack {
            Color(white: 0.97)  // 有背景色
            // ... 星星动画
        }
    }
    .frame(height: 150)  // 有固定高度
    .clipShape(RoundedRectangle(cornerRadius: 8))
}

// CachedAsyncImage loading状态 - 无背景，不填满
else {
    ProgressView()  // 只有一个小转圈圈！
}
```

**视觉对比**：

```
AssetLoadingView（呼吸动画）          CachedAsyncImage（loading状态）
┌─────────────────────────┐          ┌─────────────────────────┐
│  ████████████████████   │          │                         │
│  ████████████████████   │          │                         │
│  ████  生成中  ████████  │    →     │         ⟳              │
│  ████████████████████   │          │                         │
│  ████████████████████   │          │                         │
└─────────────────────────┘          └─────────────────────────┘
   有背景色，填满150pt                  只有一个小转圈圈，无背景
```

#### 相关代码位置

| 文件 | 行号 | 说明 |
|------|------|------|
| `NativeEditorView.swift` | 1348-1352 | AssetLoadingView 覆盖条件 |
| `NativeEditorView.swift` | 1228-1325 | AssetLoadingView 实现 |
| `CachedAsyncImage.swift` | 38-40 | loading状态只显示ProgressView |

---

### 2.2 错误信息问题

#### 问题现象

用户看到的错误信息包含技术术语：
- "HTTP 错误 (503): ..."
- "生成失败: Google API internal error: 503"
- "生成失败: Request timed out after 180s"

#### 根因分析

**错误传递链**：

```
Google API 返回 503
    ↓
google_api.py: raise InternalServerError(f"Google API internal error: {status_code}")
    ↓
task_service.py: _update_task_status(status="failed", error_message=str(e))
    ↓
数据库保存原始错误信息
    ↓
iOS 轮询获取 TaskStatusResponse.errorMessage
    ↓
RealGenerationService: throw APIError.generationFailed(statusResponse.errorMessage)
    ↓
APIError.errorDescription: "生成失败: {原始错误信息}"
    ↓
用户看到: "生成失败: Google API internal error: 503"
```

**相关代码**：

```swift
// APIError.swift
case generationFailed(String)

var errorDescription: String? {
    switch self {
    case .generationFailed(let message):
        return "生成失败: \(message)"  // 直接拼接后端原始错误
    // ...
    }
}
```

```python
# google_api.py
elif response.status_code >= 500:
    raise InternalServerError(f"Google API internal error: {response.status_code}")

except httpx.TimeoutException:
    raise GoogleAPIError(f"Request timed out after {self.timeout}s")
```

---

### 2.3 超时配置问题

#### 问题现象

iOS端可能在后端还在处理时就超时。

#### 根因分析

| 组件 | 超时时间 | 说明 |
|------|---------|------|
| iOS轮询 | 60秒 | `maxAttempts: 60`，每秒轮询一次 |
| iOS网络请求 | 30秒/60秒 | request/resource超时 |
| 后端Google API | 180秒 | httpx超时配置 |
| 后端Laozhang API | 180秒 | httpx超时配置 |

**问题**：iOS端60秒超时 < 后端180秒处理时间

**场景**：
1. 用户发起生成请求
2. 后端开始调用Google API
3. Google API响应慢（如100秒）
4. iOS端60秒后超时，显示"生成超时"
5. 但后端仍在处理，最终生成成功
6. 用户看到超时错误，但图片实际已生成

---

### 2.4 重试机制缺失

#### 问题现象

网络抖动、临时503等可恢复错误直接失败，用户需要手动重试。

#### 根因分析

**后端**：
```python
# task_service.py - 无重试逻辑
try:
    image_data = await provider.generate_image(...)
except Exception as e:
    await self._update_task_status(task_id, "failed", error_message=str(e))
    # 直接失败，无重试
```

**iOS端**：
```swift
// APIClient.swift - 只有401重试
if httpResponse.statusCode == 401 && requiresAuth && retryCount == 0 {
    // 只对401认证错误重试
    if try await tokenManager.refreshAccessToken() {
        return try await request(..., retryCount: retryCount + 1)
    }
}
// 其他错误（503、429等）不重试
```

---

## 三、修复方案

### 3.1 修复CachedAsyncImage loading状态（P0）

**目标**：让loading状态填满整个格子，与AssetLoadingView视觉一致

**修改文件**：`src/MindCanvas/MindCanvas/Views/Components/CachedAsyncImage.swift`

**修改内容**：

```swift
// 修改前（第38-40行）
else {
    ProgressView()
}

// 修改后
else {
    // 图片加载中 - 填满格子，与 AssetLoadingView 视觉一致
    ZStack {
        Color(white: 0.97)  // 与 AssetLoadingView 相同的背景色
        VStack(spacing: 8) {
            ProgressView()
                .scaleEffect(1.2)
            Text("加载中")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.5))
        }
    }
}
```

**效果**：

```
修改前                              修改后
┌─────────────────────────┐          ┌─────────────────────────┐
│                         │          │  ████████████████████   │
│                         │          │  ████████████████████   │
│         ⟳              │    →     │  ████  加载中  ████████  │
│                         │          │  ████████████████████   │
│                         │          │  ████████████████████   │
└─────────────────────────┘          └─────────────────────────┘
```

---

### 3.2 增强失败UI可见性（P0）

**目标**：失败状态更明显，用户能清楚知道加载失败

**修改文件**：`src/MindCanvas/MindCanvas/Views/Components/CachedAsyncImage.swift`

**修改内容**：

```swift
// 修改前（第30-37行）
else if hasFailed {
    Rectangle()
        .fill(Color.gray.opacity(0.1))
        .overlay {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(Color.gray)
        }
}

// 修改后
else if hasFailed {
    // 图片加载失败 - 更明显的失败提示
    ZStack {
        Color(white: 0.95)  // 稍深的背景色
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundStyle(Color.orange)
            Text("加载失败")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.5))
        }
    }
}
```

---

### 3.3 错误信息友好化（P0）

**目标**：将技术错误转换为用户友好的提示

**新增文件**：`src/MindCanvas/MindCanvas/Infrastructure/ErrorMessageMapper.swift`

```swift
//
//  ErrorMessageMapper.swift
//  MindCanvas
//
//  错误信息映射器，将技术错误转换为用户友好的提示
//

import Foundation

struct ErrorMessageMapper {

    /// 将 APIError 转换为用户友好的错误信息
    static func userFriendlyMessage(for error: APIError) -> String {
        switch error {
        case .httpError(let statusCode, _):
            return httpErrorMessage(statusCode: statusCode)

        case .timeout:
            return "生成时间较长，请稍后在资源栏查看结果"

        case .generationFailed(let msg):
            return generationFailedMessage(originalMessage: msg)

        case .networkError:
            return "网络连接不稳定，请检查网络后重试"

        case .invalidAPIKey:
            return "API Key 无效，请检查配置"

        case .unauthorized:
            return "登录已过期，请重新登录"

        case .tokenExpired:
            return "登录已过期，请重新登录"

        default:
            return "操作失败，请稍后重试"
        }
    }

    /// HTTP 错误码映射
    private static func httpErrorMessage(statusCode: Int) -> String {
        switch statusCode {
        case 400:
            return "请求参数有误，请检查后重试"
        case 401:
            return "登录已过期，请重新登录"
        case 403:
            return "没有权限执行此操作"
        case 404:
            return "请求的资源不存在"
        case 429:
            return "请求过于频繁，请稍后重试"
        case 500:
            return "服务器开小差了，请稍后重试"
        case 502:
            return "服务暂时不可用，请稍后重试"
        case 503:
            return "服务暂时繁忙，请稍后重试"
        case 504:
            return "服务响应超时，请稍后重试"
        default:
            if statusCode >= 500 {
                return "服务器开小差了，请稍后重试"
            }
            return "网络请求失败，请检查网络后重试"
        }
    }

    /// 生成失败错误映射
    private static func generationFailedMessage(originalMessage: String) -> String {
        let lowercased = originalMessage.lowercased()

        // 超时相关
        if lowercased.contains("timeout") || lowercased.contains("timed out") {
            return "AI服务响应较慢，请稍后重试"
        }

        // 服务繁忙相关
        if lowercased.contains("503") || lowercased.contains("overloaded") || lowercased.contains("busy") {
            return "AI服务暂时繁忙，请稍后重试"
        }

        // 限流相关
        if lowercased.contains("rate limit") || lowercased.contains("429") || lowercased.contains("too many") {
            return "请求过于频繁，请稍后重试"
        }

        // API Key 相关
        if lowercased.contains("api key") || lowercased.contains("invalid key") || lowercased.contains("401") {
            return "API Key 无效，请检查配置"
        }

        // 内容审核相关
        if lowercased.contains("safety") || lowercased.contains("blocked") || lowercased.contains("policy") {
            return "内容不符合安全规范，请修改提示词后重试"
        }

        // 默认
        return "生成失败，请稍后重试"
    }
}
```

**修改文件**：`src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`

在错误处理处使用映射器：

```swift
// 修改前
catch {
    flowHintMessage = "生成失败：\(error.localizedDescription)"
}

// 修改后
catch let error as APIError {
    flowHintMessage = ErrorMessageMapper.userFriendlyMessage(for: error)
} catch {
    flowHintMessage = "生成失败，请稍后重试"
}
```

---

### 3.4 超时配置统一（P1）

**目标**：iOS轮询超时 > 后端处理超时，避免iOS提前超时

**修改文件**：`src/MindCanvas/MindCanvas/Services/RealGenerationService.swift`

**修改内容**：

```swift
// 修改前（第58行）
private func pollTaskStatus(taskId: String, maxAttempts: Int = 60) async throws -> GenerationResponse

// 修改后
private func pollTaskStatus(taskId: String, maxAttempts: Int = 200) async throws -> GenerationResponse
```

**配置对比**：

| 组件 | 修改前 | 修改后 |
|------|--------|--------|
| iOS轮询超时 | 60秒 | **200秒** |
| 后端Google API | 180秒 | 180秒（不变） |

---

### 3.5 图片下载重试（P2）

**说明**：生图请求失败不自动重试，直接透出友好化后的错误信息，让用户自己决定是否重试。只对图片下载失败进行自动重试。

**目标**：图片下载失败时自动重试一次

**修改文件**：`src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`

**修改内容**（在 `generateTextToImage` 和 `confirmImageToImageGenerate` 方法中）：

```swift
// 修改前
var localImageURL: String? = nil
if let imageURL = URL(string: response.imageUrl),
   let relativePath = await ImageStorageService.shared.downloadAndSaveImageWithRelativePath(from: imageURL) {
    localImageURL = relativePath
} else {
    print("[TextToImage] 警告：图片下载失败，将使用远程URL")
}

// 修改后
var localImageURL: String? = nil
for attempt in 0..<2 {
    if let imageURL = URL(string: response.imageUrl),
       let relativePath = await ImageStorageService.shared.downloadAndSaveImageWithRelativePath(from: imageURL) {
        localImageURL = relativePath
        break
    }
    if attempt == 0 {
        print("[TextToImage] 图片下载失败，2秒后重试...")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }
}
if localImageURL == nil {
    print("[TextToImage] 警告：图片下载失败，将使用远程URL")
}
```

---

## 四、修改文件清单

### iOS端

| 文件 | 修改类型 | 优先级 | 说明 |
|------|---------|--------|------|
| `CachedAsyncImage.swift` | 修改 | P0 | loading状态填满格子 + 失败UI增强 |
| `ErrorMessageMapper.swift` | 新增 | P0 | 错误信息映射器 |
| `NativeEditorViewModel.swift` | 修改 | P0 | 使用错误映射器 + 下载重试 |
| `RealGenerationService.swift` | 修改 | P1 | 增加轮询超时时间 |

### 后端（可选，暂不修改）

后端生图失败不做自动重试，直接返回错误信息，由iOS端友好化后展示给用户。

---

## 五、验证方案

### 5.1 测试场景

#### 场景1：正常生成流程

**步骤**：
1. 打开编辑器
2. 点击"文生图"或"图生图"
3. 输入提示词，点击生成

**预期**：
1. 资源栏显示呼吸动画（AssetLoadingView）
2. 生成完成后，如果图片还在下载，显示填满格子的loading状态
3. 图片加载完成后正常显示

#### 场景2：图片下载失败

**步骤**：
1. 生成图片
2. 在图片下载过程中断开网络

**预期**：
1. 自动重试一次
2. 重试失败后显示明显的失败UI（橙色警告图标 + "加载失败"文字）

#### 场景3：503错误

**步骤**：
1. 模拟后端返回503错误

**预期**：
1. 显示"服务暂时繁忙，请稍后重试"
2. 不显示"HTTP 错误 (503)"等技术信息

#### 场景4：超时场景

**步骤**：
1. 模拟Google API响应慢（>60秒）

**预期**：
1. iOS端不会在60秒时超时
2. 等待后端完成（最多200秒）

### 5.2 验证检查清单

- [ ] CachedAsyncImage loading状态填满格子
- [ ] CachedAsyncImage 失败状态显示橙色警告图标
- [ ] 503错误显示"服务暂时繁忙，请稍后重试"
- [ ] timeout错误显示"AI服务响应较慢，请稍后重试"
- [ ] iOS轮询超时时间为200秒
- [ ] 图片下载失败时自动重试一次

---

## 六、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 超时时间过长导致用户等待 | 用户体验 | 添加进度提示，告知用户正在处理 |
| 错误映射不完整 | 部分错误仍显示技术信息 | 添加默认兜底提示 |

---

## 七、后续优化建议

1. **添加生成进度提示**：在长时间生成时，显示预估剩余时间
2. **WebSocket推送**：替代轮询，减少网络请求
3. **离线重试队列**：网络恢复后自动重试失败的任务
4. **错误上报**：收集错误信息用于分析和优化
