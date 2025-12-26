# API Key 配置页面设计方案

## 概述

为 MindCanvas 添加 Google Nano Banana Pro 原生 API Key 配置功能，提供安全、优雅、符合 iOS 最佳实践的用户体验。

## 设计目标

1. **安全性**：API Key 使用 Keychain 安全存储，避免明文存储
2. **用户体验**：提供明文/密文切换功能，方便用户输入和验证
3. **一致性**：与现有设置页面风格保持一致
4. **专业性**：符合 iOS Human Interface Guidelines 和项目设计规范

## 技术方案

### 1. 架构设计

```
SettingsView (现有)
└── NavigationLink → APIConfigView (新增)
    ├── SecureAPIKeyField (新增组件)
    │   ├── TextField (输入框)
    │   ├── ToggleButton (明文/密文切换)
    │   └── Validation (验证逻辑)
    └── Description Text (说明文字)
```

### 2. 文件结构

| 文件路径 | 说明 |
|---------|------|
| `Views/Settings/APIConfigView.swift` | API Key 配置主视图 |
| `Views/Settings/Components/SecureAPIKeyField.swift` | 安全密钥输入组件 |
| `Infrastructure/KeychainManager.swift` | 扩展：添加 API Key 存储方法 |

### 3. 核心组件设计

#### 3.1 SecureAPIKeyField 组件

**功能特性**：
- ✅ 支持明文/密文切换（眼睛图标）
- ✅ 自动验证 API Key 格式
- ✅ 实时显示验证状态
- ✅ 支持复制功能
- ✅ 符合项目 Theme 规范

**UI 设计**：
```
┌─────────────────────────────────────────────┐
│  🔑 Google Nano Banana Pro API Key          │  ← 标题
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ ••••••••••••••••••••••••••••••••••  👁  │  ← 输入框 + 切换按钮
│  └─────────────────────────────────────┘   │
│                                             │
│  请输入您的 Google Nano Banana Pro 原生    │  ← 说明文字
│  API Key，用于启用 AI 图像生成功能。         │
│                                             │
│  ✓ API Key 格式正确                         │  ← 验证状态
│                                             │
│  [保存] [取消]                              │  ← 操作按钮
└─────────────────────────────────────────────┘
```

**状态管理**：
```swift
@State private var apiKey: String = ""
@State private var isSecure: Bool = true
@State private var isValid: Bool = false
@State private var isSaved: Bool = false
```

#### 3.2 KeychainManager 扩展

**新增方法**：
```swift
// 保存 API Key
func saveAPIKey(_ apiKey: String) -> Bool

// 获取 API Key
func getAPIKey() -> String?

// 删除 API Key
func deleteAPIKey() -> Bool

// 检查是否已配置 API Key
func hasAPIKey() -> Bool
```

**安全规范**：
- 使用 `kSecAttrAccount = "google_nano_banana_pro_api_key"` 作为唯一标识
- 使用 `kSecAttrService = "com.mindcanvas.app"` 保持与现有 token 一致
- 所有操作都在后台线程执行，避免阻塞 UI

### 4. UI 实现细节

#### 4.1 SecureAPIKeyField 组件代码结构

```swift
struct SecureAPIKeyField: View {
    @Binding var apiKey: String
    @State private var isSecure: Bool = true
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // 左侧图标
            Image(systemName: "key.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Colors.brandBlue)

            // 输入框
            if isSecure {
                SecureField("请输入 API Key", text: $apiKey)
                    .focused($isFocused)
            } else {
                TextField("请输入 API Key", text: $apiKey)
                    .focused($isFocused)
                    .textContentType(.password)
            }

            // 明文/密文切换按钮
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSecure.toggle()
                }
            } label: {
                Image(systemName: isSecure ? "eye.slash" : "eye")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .padding()
        .frame(height: Theme.Sizes.buttonHeight)
        .background(Theme.Colors.cardBackground)
        .cornerRadius(Theme.Shapes.buttonCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                .stroke(isFocused ? Theme.Colors.brandBlue : Color.clear, lineWidth: 2)
        )
    }
}
```

#### 4.2 APIConfigView 主视图代码结构

```swift
struct APIConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var isSecure: Bool = true
    @State private var isSaved: Bool = false
    @State private var showingAlert: Bool = false
    @State private var alertMessage: String = ""

    var body: some View {
        NavigationStack {
            Form {
                apiKeySection
                descriptionSection
                validationSection
            }
            .navigationTitle("API 配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveAPIKey()
                    }
                    .disabled(apiKey.isEmpty)
                }
            }
            .alert("提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureAPIKeyField(
                apiKey: $apiKey,
                isSecure: $isSecure
            )
        } header: {
            Text("Google Nano Banana Pro API Key")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.primaryText)
        } footer: {
            if isSaved {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                    Text("已保存")
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
    }

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                descriptionRow(
                    icon: "info.circle",
                    title: "用途说明",
                    description: "用于启用 AI 图像生成功能，支持高质量图像创作。"
                )

                descriptionRow(
                    icon: "link",
                    title: "获取方式",
                    description: "访问 Google AI Studio 获取您的 API Key。"
                )

                descriptionRow(
                    icon: "checkmark.shield",
                    title: "安全保障",
                    description: "API Key 将安全存储在设备 Keychain 中，不会上传到服务器。"
                )
            }
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private var validationSection: some View {
        Section {
            if !apiKey.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: isValidFormat ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isValidFormat ? Theme.Colors.success : Theme.Colors.warning)

                    Text(isValidFormat ? "API Key 格式正确" : "API Key 格式可能不正确")
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(isValidFormat ? Theme.Colors.success : Theme.Colors.warning)
                }
            }
        }
    }

    private var isValidFormat: Bool {
        // Google API Key 格式验证：以 "AIza" 开头，长度约 39 字符
        let pattern = "^AIza[A-Za-z0-9_-]{35}$"
        return apiKey.range(of: pattern, options: .regularExpression) != nil
    }

    private func descriptionRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.brandBlue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(Theme.Colors.primaryText)

                Text(description)
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty else {
            alertMessage = "请输入 API Key"
            showingAlert = true
            return
        }

        if !isValidFormat {
            alertMessage = "API Key 格式不正确，请检查后重试"
            showingAlert = true
            return
        }

        let success = KeychainManager.shared.saveAPIKey(apiKey)
        if success {
            isSaved = true
            dismiss()
        } else {
            alertMessage = "保存失败，请重试"
            showingAlert = true
        }
    }
}
```

#### 4.3 KeychainManager 扩展代码

```swift
// MARK: - API Key Management

extension KeychainManager {
    private let apiKeyAccount = "google_nano_banana_pro_api_key"

    func saveAPIKey(_ apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data
        ]

        // 先删除旧的
        SecItemDelete(query as CFDictionary)

        // 添加新的
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }

        return apiKey
    }

    func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    func hasAPIKey() -> Bool {
        return getAPIKey() != nil
    }
}
```

### 5. 修改现有文件

#### 5.1 更新 SettingsView.swift

**位置**：`Views/Settings/SettingsView.swift`

**修改内容**：
- 将 "API 配置" NavigationLink 的目标从占位符文本改为 `APIConfigView()`

**修改前**：
```swift
NavigationLink {
    Text("API 配置页面")
} label: {
    Label("API 配置", systemImage: "key.fill")
        .foregroundStyle(Theme.Colors.primaryText)
}
```

**修改后**：
```swift
NavigationLink {
    APIConfigView()
} label: {
    Label("API 配置", systemImage: "key.fill")
        .foregroundStyle(Theme.Colors.primaryText)
}
```

### 6. 项目文件添加到 Xcode

**需要添加到 Xcode 项目的文件**：

| 文件 | Group |
|-----|-------|
| `APIConfigView.swift` | `Views > Settings` |
| `SecureAPIKeyField.swift` | `Views > Settings > Components` (新建 Group) |

**操作步骤**：
1. 在 Xcode 中打开 `MindCanvas.xcodeproj`
2. 在 `MindCanvas > Views > Settings` 上右键
3. 选择 "Add Files to MindCanvas..."
4. 选择 `APIConfigView.swift`，确保 "Copy items if needed" 未勾选
5. 在 `Settings` Group 上右键，选择 "New Group"，命名为 `Components`
6. 在 `Components` Group 上右键，添加 `SecureAPIKeyField.swift`

### 7. 验证清单

开发完成后，需要验证以下功能：

- [ ] 设置页面中 "API 配置" 导航链接正常工作
- [ ] 进入 API 配置页面，标题显示正确
- [ ] 输入框默认为密文模式（显示 •••）
- [ ] 点击眼睛图标可以切换明文/密文显示
- [ ] 输入 API Key 时，实时显示格式验证状态
- [ ] 点击"保存"按钮，API Key 正确保存到 Keychain
- [ ] 保存成功后，显示"已保存"标识
- [ ] 重新进入页面，已保存的 API Key 自动加载
- [ ] 点击"取消"按钮，返回设置页面
- [ ] 输入为空时，"保存"按钮禁用
- [ ] API Key 格式不正确时，显示警告提示
- [ ] 说明文字正确显示，格式清晰
- [ ] UI 样式与现有设置页面一致

### 8. 测试用例

#### 8.1 正常流程测试

**测试步骤**：
1. 打开应用，进入设置页面
2. 点击 "API 配置"
3. 输入有效的 Google API Key（例如：`AIzaSyExampleApiKeyForTesting1234567890`）
4. 点击眼睛图标，验证密文/明文切换
5. 点击"保存"按钮
6. 返回设置页面
7. 再次进入 "API 配置"，验证 API Key 已保存

**预期结果**：
- ✅ 所有操作流畅无卡顿
- ✅ API Key 正确保存和加载
- ✅ UI 显示正确

#### 8.2 异常流程测试

**测试用例 1：空输入**
1. 进入 API 配置页面
2. 不输入任何内容，直接点击"保存"

**预期结果**：
- ✅ "保存"按钮禁用或提示"请输入 API Key"

**测试用例 2：格式错误**
1. 输入错误的 API Key 格式（例如：`invalid_key`）
2. 点击"保存"

**预期结果**：
- ✅ 显示警告："API Key 格式不正确"

**测试用例 3：取消操作**
1. 输入 API Key
2. 点击"取消"

**预期结果**：
- ✅ 返回设置页面，未保存输入内容

#### 8.3 安全性测试

**测试步骤**：
1. 保存 API Key
2. 重启应用
3. 进入 API 配置页面
4. 尝试从 Keychain 读取 API Key

**预期结果**：
- ✅ API Key 正确读取
- ✅ API Key 未以明文形式存储在其他位置

### 9. 性能优化

**优化点**：
1. **异步验证**：API Key 格式验证在后台线程执行，避免阻塞 UI
2. **防抖处理**：输入时延迟验证（300ms），避免频繁触发验证
3. **内存管理**：使用 `@State` 而非 `@StateObject`，避免不必要的对象创建

**实现代码**：
```swift
@State private var debounceTask: Task<Void, Never>?

private func validateAPIKey(_ key: String) {
    debounceTask?.cancel()

    debounceTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        await MainActor.run {
            isValid = validateFormat(key)
        }
    }
}
```

### 10. 用户体验细节

#### 10.1 动画效果

- ✅ 明文/密文切换使用 `withAnimation(.easeInOut(duration: 0.2))` 实现流畅过渡
- ✅ 保存成功后显示绿色对勾动画
- ✅ 验证状态变化使用淡入淡出效果

#### 10.2 触觉反馈

- ✅ 点击眼睛图标时提供轻微触觉反馈
- ✅ 保存成功时提供成功触觉反馈

**实现代码**：
```swift
Button {
    let impact = UIImpactFeedbackGenerator(style: .light)
    impact.impactOccurred()
    withAnimation(.easeInOut(duration: 0.2)) {
        isSecure.toggle()
    }
} label: {
    Image(systemName: isSecure ? "eye.slash" : "eye")
}
```

#### 10.3 键盘处理

- ✅ 输入框获得焦点时自动弹出键盘
- ✅ 点击键盘"完成"按钮自动收起键盘
- ✅ 点击页面空白区域自动收起键盘

**实现代码**：
```swift
.onTapGesture {
    UIApplication.shared.endEditing()
}
```

### 11. 国际化支持（预留）

虽然当前版本只支持中文，但设计时预留了国际化支持：

**字符串常量定义**：
```swift
enum APIConfigStrings {
    static let title = "API 配置"
    static let save = "保存"
    static let cancel = "取消"
    static let placeholder = "请输入 API Key"
    static let saved = "已保存"
    static let formatValid = "API Key 格式正确"
    static let formatInvalid = "API Key 格式可能不正确"
    static let emptyError = "请输入 API Key"
    static let formatError = "API Key 格式不正确，请检查后重试"
    static let saveError = "保存失败，请重试"
}
```

### 12. 后续扩展

#### 12.1 多 API Key 支持

未来可能需要支持多个 AI 服务提供商：

```swift
enum AIProvider: String, CaseIterable {
    case googleNanoBananaPro = "Google Nano Banana Pro"
    case openAI = "OpenAI"
    case anthropic = "Anthropic"

    var icon: String {
        switch self {
        case .googleNanoBananaPro: return "key.fill"
        case .openAI: return "brain.head.profile"
        case .anthropic: return "sparkles"
        }
    }
}
```

#### 12.2 API Key 测试功能

添加"测试连接"按钮，验证 API Key 是否有效：

```swift
Button {
    testAPIKey()
} label: {
    HStack {
        Image(systemName: "network")
        Text("测试连接")
    }
}
```

#### 12.3 API Key 过期提醒

定期检查 API Key 是否过期，提醒用户更新：

```swift
func checkAPIKeyExpiry() {
    // 检查 API Key 是否过期
    // 如果过期，显示提醒
}
```

### 13. 设计亮点

#### 13.1 符合 iOS 最佳实践

- ✅ 使用 `SecureField` 处理敏感信息
- ✅ 使用 Keychain 安全存储
- ✅ 使用 NavigationStack 进行页面导航
- ✅ 使用 Form + Section 组织内容
- ✅ 使用 ToolbarItem 添加导航栏按钮

#### 13.2 一致的 UI 风格

- ✅ 使用项目的 Theme 系统（颜色、字体、间距、图标）
- ✅ 与现有设置页面风格保持一致
- ✅ 使用项目定义的圆角、阴影等样式

#### 13.3 优秀的用户体验

- ✅ 明文/密文切换，方便输入和验证
- ✅ 实时格式验证，即时反馈
- ✅ 详细的说明文字，降低学习成本
- ✅ 流畅的动画效果，提升视觉体验
- ✅ 触觉反馈，增强交互感知

#### 13.4 安全性设计

- ✅ Keychain 安全存储
- ✅ 密文默认显示
- ✅ 格式验证，防止错误输入
- ✅ 不上传到服务器，本地存储

### 14. 技术要点总结

| 要点 | 实现方式 |
|-----|---------|
| 安全存储 | KeychainManager 扩展 |
| 明文/密文切换 | SecureField + TextField + 状态切换 |
| 格式验证 | 正则表达式 |
| UI 一致性 | Theme 系统 |
| 页面导航 | NavigationStack + NavigationLink |
| 状态管理 | @State + @Binding |
| 动画效果 | withAnimation |
| 触觉反馈 | UIImpactFeedbackGenerator |
| 键盘处理 | UIApplication.shared.endEditing() |

### 15. 开发注意事项

1. **不要修改现有功能**：只添加新功能，不影响现有设置页面功能
2. **保持代码简洁**：遵循项目规范，避免过度设计
3. **添加必要注释**：关键逻辑添加注释，便于维护
4. **测试覆盖**：确保所有功能都被测试覆盖
5. **性能优化**：避免不必要的计算和渲染
6. **错误处理**：所有可能的错误都要有处理逻辑

### 16. 参考资源

- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui/)
- [Keychain Services API](https://developer.apple.com/documentation/security/keychain_services)
- [iOS Security Best Practices](https://developer.apple.com/documentation/security/password_autofill/)

## 总结

本设计方案提供了一个完整、安全、优雅的 API Key 配置功能实现方案。通过使用 Keychain 安全存储、明文/密文切换、实时格式验证等技术，确保了功能的安全性和易用性。同时，严格遵循 iOS 最佳实践和项目设计规范，保证了 UI 的一致性和专业性。

执行人员可以根据本方案直接进行开发，所有细节都已明确，无需额外决策。