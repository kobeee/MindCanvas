# Laozhang API 配额提醒 iOS 端集成方案

## 1. 概述

### 1.1 背景

用户在使用生图功能时，需要配置 Google API Key。为了提供更好的用户体验，后端新增了免费额度功能，部分邮箱用户可以享受 10 次免费生图额度。

### 1.2 目标

在 iOS 端实现以下功能：

1. **配额查询**：查询用户是否有免费额度
2. **智能提示**：根据用户配额状态显示不同的提示信息
3. **无缝集成**：不影响现有功能，保持 UI 风格一致性

### 1.3 设计原则

- **最小改动**：只修改必要的代码，不影响其他功能
- **UI 一致性**：保持与现有设计风格一致
- **用户体验**：提供清晰的提示信息，引导用户正确使用

---

## 2. 功能分析

### 2.1 现有流程

1. 用户进入编辑器
2. 输入提示词
3. 点击"生成"按钮
4. 检查 API Key 是否配置
5. 如果未配置，提示用户配置 API Key
6. 如果已配置，调用生图接口

### 2.2 新增流程

1. 用户进入编辑器
2. 查询用户配额信息
3. 输入提示词
4. 点击"生成"按钮
5. 检查用户配额状态
   - 如果有免费额度，提示用户可以使用免费额度
   - 如果没有免费额度且未配置 API Key，提示用户配置 API Key
   - 如果没有免费额度但已配置 API Key，直接使用 API Key 生图
6. 调用生图接口

### 2.3 配额状态分类

| 状态 | 条件 | 提示信息 | 操作 |
|:---|:---|:---|:---|
| **有免费额度** | `has_free_quota = true` 且 `remaining_quota > 0` | "您还有 X 次免费额度" | 可以直接生图 |
| **免费额度已用完** | `has_free_quota = true` 但 `remaining_quota = 0` | "免费额度已用完，请配置 API Key" | 引导配置 API Key |
| **无免费额度** | `has_free_quota = false` | "请配置 API Key" | 引导配置 API Key |
| **使用 Google API** | `api_provider = "google"` | "使用您的 API Key 生图" | 直接生图 |

---

## 3. 技术实现

### 3.1 后端接口

**接口**：`GET /api/v1/users/me/quota`

**认证**：JWT Token

**响应**：
```json
{
  "api_provider": "laozhang",
  "has_free_quota": true,
  "max_quota": 10,
  "used_quota": 3,
  "remaining_quota": 7,
  "subscription_tier": "free"
}
```

### 3.2 iOS 端实现

#### 3.2.1 配额查询服务

**文件**：`src/MindCanvas/MindCanvas/Services/QuotaService.swift`

```swift
import Foundation

/// 配额信息
struct QuotaInfo: Codable {
    let apiProvider: String
    let hasFreeQuota: Bool
    let maxQuota: Int
    let usedQuota: Int
    let remainingQuota: Int
    let subscriptionTier: String
    
    enum CodingKeys: String, CodingKey {
        case apiProvider = "api_provider"
        case hasFreeQuota = "has_free_quota"
        case maxQuota = "max_quota"
        case usedQuota = "used_quota"
        case remainingQuota = "remaining_quota"
        case subscriptionTier = "subscription_tier"
    }
}

/// 配额服务
class QuotaService {
    static let shared = QuotaService()
    
    private init() {}
    
    /// 查询用户配额
    func fetchQuota() async throws -> QuotaInfo {
        let url = URL(string: "\(APIClient.shared.baseURL)/api/v1/users/me/quota")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // 添加 JWT Token
        if let token = AuthManager.shared.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw APIError.networkError
        }
        
        let quotaInfo = try JSONDecoder().decode(QuotaInfo.self, from: data)
        return quotaInfo
    }
}
```

#### 3.2.2 编辑器视图模型更新

**文件**：`src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`

**新增属性**：
```swift
// MARK: - 配额管理

/// 用户配额信息
var quotaInfo: QuotaInfo?

/// 是否正在加载配额信息
var isLoadingQuota = false

/// 配额提示信息
var quotaHintMessage: String?
```

**新增方法**：
```swift
// MARK: - 配额管理

/// 加载用户配额信息
func loadQuota() async {
    isLoadingQuota = true
    
    do {
        let info = try await QuotaService.shared.fetchQuota()
        quotaInfo = info
        updateQuotaHint()
    } catch {
        print("加载配额信息失败: \(error)")
        // 失败不影响生图功能，静默处理
    }
    
    isLoadingQuota = false
}

/// 更新配额提示信息
private func updateQuotaHint() {
    guard let info = quotaInfo else {
        quotaHintMessage = nil
        return
    }
    
    if info.apiProvider == "laozhang" {
        if info.hasFreeQuota && info.remainingQuota > 0 {
            quotaHintMessage = "您还有 \(info.remainingQuota) 次免费额度"
        } else if info.hasFreeQuota && info.remainingQuota == 0 {
            quotaHintMessage = "免费额度已用完，请配置 API Key"
        } else {
            quotaHintMessage = nil
        }
    } else {
        quotaHintMessage = nil
    }
}

/// 检查是否可以生图
func checkCanGenerate() -> Bool {
    // 检查 API Key
    let hasAPIKey = KeychainManager.shared.hasAPIKey()
    
    // 检查免费额度
    let hasFreeQuota = quotaInfo?.hasFreeQuota == true && (quotaInfo?.remainingQuota ?? 0) > 0
    
    return hasAPIKey || hasFreeQuota
}

/// 获取生图提示信息
func getGenerationHint() -> String? {
    // 检查 API Key
    let hasAPIKey = KeychainManager.shared.hasAPIKey()
    
    // 检查免费额度
    let hasFreeQuota = quotaInfo?.hasFreeQuota == true && (quotaInfo?.remainingQuota ?? 0) > 0
    
    if hasFreeQuota {
        return quotaHintMessage
    } else if !hasAPIKey {
        return "请先在设置中配置 API Key"
    }
    
    return nil
}
```

**修改初始化方法**：
```swift
init(project: Project) {
    self.project = project
    self.projectName = project.name
    
    // 初始化画布文档
    self.canvasDocument = CanvasDocument(projectID: project.id)
    
    // TODO: 从持久化存储加载画布文档
    
    // 加载配额信息
    Task {
        await loadQuota()
    }
}
```

#### 3.2.3 编辑器视图更新

**文件**：`src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift`

**新增配额提示 UI**：
```swift
// 配额提示
if let quotaHint = viewModel.quotaHintMessage, !viewModel.isGenerating {
    HStack(spacing: 8) {
        Image(systemName: "gift.fill")
            .foregroundColor(Theme.Colors.brandBlue)
        Text(quotaHint)
            .font(.caption)
            .foregroundColor(Theme.Colors.secondaryText)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(
        RoundedRectangle(cornerRadius: 8)
            .fill(Theme.Colors.brandBlue.opacity(0.1))
    )
    .padding(.horizontal)
}
```

**修改生图按钮禁用逻辑**：
```swift
// 生成按钮
Button {
    Task {
        await viewModel.generateImage()
    }
} label: {
    HStack {
        Image(systemName: "sparkles")
        Text("生成")
    }
}
.disabled(viewModel.isGenerating || !viewModel.checkCanGenerate())
.foregroundStyle(viewModel.checkCanGenerate() ? Theme.Colors.brandBlue : Theme.Colors.secondaryText)
```

**修改 API Key 提示逻辑**：
```swift
// API Key 或配额提示
if let hint = viewModel.getGenerationHint(), !viewModel.isGenerating {
    HStack(spacing: 8) {
        Image(systemName: viewModel.quotaInfo?.hasFreeQuota == true ? "gift.fill" : "key.fill")
            .foregroundColor(Theme.Colors.brandBlue)
        Text(hint)
            .font(.caption)
            .foregroundColor(Theme.Colors.secondaryText)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(
        RoundedRectangle(cornerRadius: 8)
            .fill(Theme.Colors.brandBlue.opacity(0.1))
    )
    .padding(.horizontal)
}
```

#### 3.2.4 生成方法更新

**文件**：`src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`

**修改 `generateImage()` 方法**：
```swift
func generateImage() async {
    // 检查是否可以生图
    guard checkCanGenerate() else {
        flowHintMessage = getGenerationHint()
        return
    }
    
    // 检查提示词
    guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        flowHintMessage = "请输入提示词"
        return
    }
    
    isGenerating = true
    flowHintMessage = nil
    
    do {
        // 检查是否有免费额度
        let hasFreeQuota = quotaInfo?.hasFreeQuota == true && (quotaInfo?.remainingQuota ?? 0) > 0
        
        if hasFreeQuota {
            // 使用免费额度，不需要 API Key
            print("使用免费额度生图")
            // 调用生图服务（不需要 API Key）
            try await generationService.generateImage(prompt: prompt, apiKey: nil)
        } else {
            // 使用 API Key 生图
            print("使用 API Key 生图")
            try await generationService.generateImage(prompt: prompt)
        }
        
        // 重新加载配额信息
        await loadQuota()
        
    } catch {
        flowHintMessage = error.localizedDescription
    }
    
    isGenerating = false
}
```

#### 3.2.5 生图服务更新

**文件**：`src/MindCanvas/MindCanvas/Services/RealGenerationService.swift`

**修改 `generateImage()` 方法**：
```swift
func generateImage(prompt: String, apiKey: String? = nil) async throws {
    // 如果未提供 API Key，从 Keychain 获取
    let finalApiKey: String
    
    if let apiKey = apiKey {
        finalApiKey = apiKey
    } else {
        guard let key = KeychainManager.shared.getAPIKey() else {
            throw APIError.invalidAPIKey
        }
        finalApiKey = key
    }
    
    // 使用 RSA 公钥加密 API Key
    let rsaService = RSAEncryptionService()
    let encryptedApiKey = try await rsaService.encrypt(finalApiKey)
    
    // 构建请求
    let requestBody = GenerateRequest(
        prompt: prompt,
        encryptedApiKey: encryptedApiKey
    )
    
    // 发送请求
    let response = try await APIClient.shared.request(
        endpoint: "/api/v1/generate/tasks",
        method: .POST,
        body: requestBody
    )
    
    // 处理响应
    // ...
}
```

---

## 4. UI 设计

### 4.1 配额提示样式

**位置**：生成按钮上方

**样式**：
- 背景色：`Theme.Colors.brandBlue.opacity(0.1)`
- 文字颜色：`Theme.Colors.secondaryText`
- 图标：`gift.fill`
- 圆角：8pt
- 内边距：水平 16pt，垂直 8pt

**示例**：
```
┌─────────────────────────────────┐
│  🎁 您还有 7 次免费额度          │
└─────────────────────────────────┘
```

### 4.2 API Key 提示样式

**位置**：生成按钮上方

**样式**：
- 背景色：`Theme.Colors.brandBlue.opacity(0.1)`
- 文字颜色：`Theme.Colors.secondaryText`
- 图标：`key.fill`
- 圆角：8pt
- 内边距：水平 16pt，垂直 8pt

**示例**：
```
┌─────────────────────────────────┐
│  🔑 请先在设置中配置 API Key      │
└─────────────────────────────────┘
```

### 4.3 生成按钮状态

| 状态 | 文字 | 图标 | 背景色 | 文字颜色 | 可点击 |
|:---|:---|:---|:---|:---|:---|
| **正常** | 生成 | sparkles | 透明 | brandBlue | 是 |
| **禁用** | 生成 | sparkles | 透明 | secondaryText | 否 |
| **生成中** | 生成中 | sparkles | 透明 | brandBlue | 否 |

---

## 5. 测试方案

### 5.1 功能测试

1. **有免费额度用户**：
   - 进入编辑器，显示配额提示
   - 点击生成按钮，成功生图
   - 配额扣减正确

2. **免费额度已用完用户**：
   - 进入编辑器，显示"免费额度已用完"提示
   - 点击生成按钮，提示配置 API Key
   - 配置 API Key 后，可以生图

3. **无免费额度用户**：
   - 进入编辑器，不显示配额提示
   - 点击生成按钮，提示配置 API Key
   - 配置 API Key 后，可以生图

4. **已有 API Key 用户**：
   - 进入编辑器，不显示配额提示
   - 点击生成按钮，直接生图

### 5.2 边界测试

1. **网络错误**：
   - 配额查询失败，不影响生图功能
   - 静默处理错误

2. **并发请求**：
   - 多次点击生成按钮，只处理一次
   - 配额扣减正确

3. **配额为 0**：
   - 显示"免费额度已用完"提示
   - 引导配置 API Key

---

## 6. 实施清单

### 6.1 代码修改

- [ ] 创建 `src/MindCanvas/MindCanvas/Services/QuotaService.swift`
- [ ] 修改 `src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`
- [ ] 修改 `src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift`
- [ ] 修改 `src/MindCanvas/MindCanvas/Services/RealGenerationService.swift`

### 6.2 测试

- [ ] 功能测试
- [ ] 边界测试
- [ ] UI 测试

### 6.3 文档

- [ ] 更新用户手册
- [ ] 更新开发文档

---

## 7. 风险和注意事项

### 7.1 风险

1. **网络延迟**：
   - 配额查询可能增加网络延迟
   - 建议：异步加载，不阻塞 UI

2. **配额不一致**：
   - 前端缓存的配额可能与后端不一致
   - 建议：每次生图前重新查询配额

3. **用户体验**：
   - 频繁的配额提示可能影响用户体验
   - 建议：只在配额变化时显示提示

### 7.2 注意事项

1. **不影响现有功能**：
   - 所有改动都是增量式的
   - 不修改现有 API Key 配置流程

2. **UI 风格一致性**：
   - 使用现有的主题颜色和样式
   - 保持与现有设计风格一致

3. **错误处理**：
   - 配额查询失败不影响生图功能
   - 静默处理错误，不显示错误提示

---

## 8. 总结

### 8.1 核心改动

1. **新增配额查询服务**：`QuotaService`
2. **编辑器视图模型更新**：添加配额相关属性和方法
3. **编辑器视图更新**：添加配额提示 UI
4. **生图服务更新**：支持无 API Key 生图

### 8.2 技术亮点

1. **异步加载**：配额信息异步加载，不阻塞 UI
2. **智能提示**：根据配额状态显示不同的提示信息
3. **无缝集成**：不影响现有功能，保持 UI 风格一致

### 8.3 实施优先级

**P0（必须）**：
- 配额查询服务
- 编辑器视图模型更新
- 编辑器视图更新

**P1（重要）**：
- 生图服务更新
- 测试

**P2（可选）**：
- 配额历史记录
- 配额购买入口