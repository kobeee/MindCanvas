# 设置页与编辑器修复方案 v1.0

## 文档信息

- **版本**: 1.0
- **日期**: 2026-01-25
- **状态**: 待实施

---

## 问题概述

本文档针对以下4个问题提供修复方案：

| 序号 | 问题描述 | 影响范围 | 优先级 |
|------|----------|----------|--------|
| 1 | 游客模式设置页UI不协调 | SettingsView.swift | P0 |
| 2 | 登录成功后页面未自动关闭 | LoginView.swift | P0 |
| 3 | 配额累计逻辑确认 | auth_service.py | P1 |
| 4 | 图生图键盘遮挡截图 | NativeEditorView.swift | P0 |

---

## 问题1：游客模式设置页UI优化

### 现状分析

当前游客模式头部存在以下问题：

```
┌─────────────────────────────────────┐
│           [灰色圆形头像]              │
│            游客模式                  │
│   需要配置 API Key 才能使用生图功能    │  ← 多余提示
│         [立即登录] 按钮               │  ← 样式突兀
└─────────────────────────────────────┘
```

**问题点**：
1. "需要配置 API Key 才能使用生图功能" 提示多余，与登录无直接关系
2. "立即登录"按钮使用实心蓝色背景，在灰色头像下方显得突兀
3. 导航标题"设置"随Form滚动消失，违反iOS设计规范

### 修复方案

#### 1.1 移除多余提示文案

删除 `guestModeHeader` 中的 API Key 提示行。

#### 1.2 优化登录按钮样式

采用轻量级文字链接样式，更符合设置页的整体风格：

```swift
// 修改前
Button {
    showingLoginView = true
} label: {
    Text("立即登录")
        .font(Theme.Fonts.bodyBold)
        .foregroundStyle(.white)
        .frame(maxWidth: 200)
        .frame(height: Theme.Sizes.buttonHeight)
        .background(Theme.Colors.brandBlue)
        .cornerRadius(Theme.Shapes.buttonCornerRadius)
}

// 修改后
Button {
    showingLoginView = true
} label: {
    HStack(spacing: 4) {
        Text("登录")
            .font(Theme.Fonts.bodyBold)
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
    }
    .foregroundStyle(Theme.Colors.brandBlue)
}
```

#### 1.3 固定导航标题

使用 `.navigationBarTitleDisplayMode(.inline)` 确保标题始终可见：

```swift
NavigationStack {
    VStack(spacing: 0) {
        profileHeader

        Form {
            // sections...
        }
    }
    .background(Theme.Colors.appBackground)
    .navigationTitle("设置")
    .navigationBarTitleDisplayMode(.inline)  // 添加此行
    // ...
}
```

### 修复后效果

```
┌─────────────────────────────────────┐
│              设置                    │  ← 固定标题栏
├─────────────────────────────────────┤
│           [灰色圆形头像]              │
│            游客模式                  │
│           登录 >                    │  ← 轻量级链接
└─────────────────────────────────────┘
```

### 修改文件

- `src/MindCanvas/MindCanvas/Views/Settings/SettingsView.swift`

### 代码变更

```swift
// SettingsView.swift

// 1. 修改 body 中的 navigationBarTitleDisplayMode
var body: some View {
    NavigationStack {
        VStack(spacing: 0) {
            profileHeader

            Form {
                if authManager.isAuthenticated {
                    accountSection
                }

                appSection
                helpSection
                aboutSection

                if authManager.isAuthenticated {
                    logoutSection
                }
            }
        }
        .background(Theme.Colors.appBackground)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)  // 新增
        // ... 其他修饰符
    }
}

// 2. 修改 guestModeHeader
private var guestModeHeader: some View {
    VStack(spacing: Theme.Spacing.lg) {
        Circle()
            .fill(Theme.Colors.secondaryText.opacity(0.2))
            .frame(width: Theme.Sizes.avatarLarge, height: Theme.Sizes.avatarLarge)
            .overlay {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

        VStack(spacing: Theme.Spacing.sm) {
            Text("游客模式")
                .font(Theme.Fonts.title2)
                .foregroundStyle(Theme.Colors.primaryText)

            // 移除 API Key 提示

            Button {
                showingLoginView = true
            } label: {
                HStack(spacing: 4) {
                    Text("登录")
                        .font(Theme.Fonts.bodyBold)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.Colors.brandBlue)
            }
        }
    }
}
```

---

## 问题2：登录成功后页面未自动关闭

### 现状分析

LoginView 通过 sheet 呈现，但登录成功后没有自动 dismiss：

```swift
// SettingsView.swift
.sheet(isPresented: $showingLoginView) {
    LoginView()
}

// LoginView.swift - 缺少 dismiss 逻辑
private func performLogin(_ loginAction: () async throws -> Token) async {
    // ...
    isAuthenticated = true  // 设置了状态，但没有关闭 sheet
}
```

### 修复方案

在 LoginView 中监听 `authManager.isAuthenticated` 变化，自动关闭 sheet：

```swift
// LoginView.swift

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss  // 新增

    // ... 其他属性

    var body: some View {
        ZStack {
            // 主内容
            // ...
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && !authManager.isGuest {
                dismiss()
            }
        }
    }
}
```

### 修改文件

- `src/MindCanvas/MindCanvas/Views/Auth/LoginView.swift`

### 代码变更

```swift
// LoginView.swift

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss  // 新增
    @State private var email = ""
    // ... 其他状态

    var body: some View {
        ZStack {
            // 主内容
            VStack(spacing: Theme.Spacing.xxxl) {
                // ...
            }
            // ...

            // Toast 弹窗
            if showToast {
                toastView
                    // ...
            }
        }
        // 新增：监听登录状态变化，自动关闭
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && !authManager.isGuest {
                dismiss()
            }
        }
    }

    // ... 其他方法
}
```

---

## 问题3：配额累计逻辑确认

### 现状分析

通过分析 `auth_service.py` 代码，确认当前逻辑：

```python
# _find_or_create_user 方法
async def _find_or_create_user(self, provider: str, user_info: Dict[str, Any]) -> User:
    # ...

    # 创建新用户后
    email_quota_synced = await self._sync_email_quota_if_exists(new_user, email)

    # 如果没有邮箱配额，给予首次登录免费额度（3次）
    if not email_quota_synced:
        new_user.api_provider = "laozhang"
        new_user.free_quota = 3
        # ...

# _sync_email_quota_if_exists 方法
async def _sync_email_quota_if_exists(self, user: User, email: str) -> bool:
    # ...
    if quota_row and quota_row[0] > 0:
        user.api_provider = "laozhang"
        user.free_quota = quota_row[0]  # 直接覆盖，不是累加
        # ...
        return True
    return False
```

### 结论

**首次登录配额与邮箱注入配额不是累加关系，而是覆盖关系**：

| 场景 | 首次登录额度 | 邮箱配额 | 最终额度 |
|------|-------------|----------|----------|
| 新用户，无邮箱配额 | 3 | 0 | 3 |
| 新用户，有邮箱配额10 | - | 10 | 10 |
| 老用户，有邮箱配额20 | - | 20 | 20 |

**逻辑说明**：
1. 邮箱配额注入优先级高于首次登录额度
2. 如果用户邮箱在 `email_quota_configs` 表中有配置，直接使用配置的额度
3. 只有在没有邮箱配额配置时，才给予首次登录的3次免费额度
4. 邮箱配额会覆盖用户当前的 `free_quota`，不会累加

### 建议

当前逻辑是合理的，无需修改。如果需要累加逻辑，需要修改 `_sync_email_quota_if_exists` 方法：

```python
# 如果需要累加（当前不需要）
if quota_row and quota_row[0] > 0:
    user.api_provider = "laozhang"
    user.free_quota = (user.free_quota or 0) + quota_row[0]  # 累加
```

---

## 问题4：图生图键盘收起问题

### 现状分析

当前流程：
1. 用户在右侧控制面板的 TextEditor 中输入提示词
2. 键盘弹出
3. 用户点击"图生图"按钮
4. 系统截取选框区域
5. **问题**：键盘遮挡了部分画布，导致截图不完整

```
┌─────────────────────────────────────────────────┐
│  资源库  │      画布区域      │   控制面板      │
│         │                    │  [TextEditor]   │
│         │   ┌──────────┐     │                 │
│         │   │ 选框区域  │     │  [图生图按钮]   │
│         │   └──────────┘     │                 │
├─────────┴────────────────────┴─────────────────┤
│              键盘（遮挡画布下半部分）              │
└─────────────────────────────────────────────────┘
```

### 修复方案

在点击"图生图"按钮时，先收起键盘，等待键盘完全收起后再执行截图：

#### 4.1 添加键盘收起方法

```swift
// 在 NativeControlPanel 中添加
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
```

#### 4.2 修改图生图按钮点击逻辑

```swift
// NativeControlPanel.swift
Button {
    // 1. 先收起键盘
    UIApplication.shared.endEditing()

    // 2. 延迟执行，等待键盘动画完成（约0.3秒）
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        onImageToImageTapped()
    }
} label: {
    // ...
}
```

### 修改文件

- `src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift`

### 代码变更

```swift
// NativeEditorView.swift

// 在文件顶部或 NativeControlPanel 结构体内添加扩展
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// 修改 NativeControlPanel 中的 generateSection
private var generateSection: some View {
    VStack(spacing: 12) {
        // 配额提示或 API Key 提示
        if let hint = viewModel.getGenerationHint() {
            // ...
        }

        Button {
            // 先收起键盘
            UIApplication.shared.endEditing()

            // 延迟执行，等待键盘动画完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                onImageToImageTapped()
            }
        } label: {
            if viewModel.isGenerating {
                HStack {
                    ProgressView()
                        .tint(.white)
                    Text("生成中...")
                }
            } else {
                Label("图生图", systemImage: "wand.and.stars")
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(
            viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            viewModel.isGenerating ||
            !viewModel.stateManager.isMagicFrameVisible ||
            !viewModel.checkCanGenerate()
        )
        .frame(maxWidth: .infinity)
        .frame(height: 50)

        // 文生图按钮保持不变
        // ...
    }
}
```

### 替代方案（更优雅）

使用 `@FocusState` 来控制键盘：

```swift
// NativeControlPanel.swift

private struct NativeControlPanel: View {
    @Bindable var viewModel: NativeEditorViewModel
    let onImageToImageTapped: () -> Void
    let onTextToImageTapped: () -> Void

    @FocusState private var isPromptFocused: Bool

    var body: some View {
        // ...
    }

    private var generateSection: some View {
        VStack(spacing: 12) {
            // ...

            Button {
                // 使用 FocusState 收起键盘
                isPromptFocused = false

                // 延迟执行
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onImageToImageTapped()
                }
            } label: {
                // ...
            }
            // ...
        }
    }
}
```

**推荐使用 `@FocusState` 方案**，因为：
1. 更符合 SwiftUI 的声明式编程范式
2. 不依赖 UIKit 的 `UIApplication`
3. 代码更简洁，可维护性更好

---

## 实施计划

### 阶段1：UI修复（问题1、2）

| 任务 | 文件 | 预估工作量 |
|------|------|-----------|
| 移除API Key提示 | SettingsView.swift | 5分钟 |
| 优化登录按钮样式 | SettingsView.swift | 10分钟 |
| 固定导航标题 | SettingsView.swift | 5分钟 |
| 添加登录成功自动关闭 | LoginView.swift | 10分钟 |

### 阶段2：功能修复（问题4）

| 任务 | 文件 | 预估工作量 |
|------|------|-----------|
| 添加键盘收起逻辑 | NativeEditorView.swift | 15分钟 |
| 测试验证 | - | 20分钟 |

### 阶段3：文档更新

| 任务 | 文件 | 预估工作量 |
|------|------|-----------|
| 更新CHANGELOG | CHANGELOG.md | 10分钟 |

---

## 测试用例

### 问题1测试

1. **游客模式头部显示**
   - 启动APP，进入游客模式
   - 进入设置页
   - 验证：头部只显示头像、"游客模式"文字和"登录 >"链接
   - 验证：无API Key提示文案

2. **导航标题固定**
   - 在设置页向下滚动
   - 验证：顶部"设置"标题始终可见

### 问题2测试

1. **登录成功自动关闭**
   - 游客模式下点击"登录"
   - 使用任意方式登录成功
   - 验证：登录页自动关闭，返回设置页
   - 验证：设置页显示已登录用户信息

### 问题4测试

1. **键盘收起后截图**
   - 进入编辑器
   - 显示选框
   - 在提示词输入框中输入文字（键盘弹出）
   - 点击"图生图"按钮
   - 验证：键盘先收起
   - 验证：截图包含完整的选框区域

---

## 参考资料

- [SwiftUI Form NavigationStack sticky header](https://stackoverflow.com/questions/72772010/how-to-stop-large-navigation-title-sticking-to-scrollview-when-scrolling-down-in)
- [Dismissing the keyboard in SwiftUI](https://sentry.io/answers/dismiss-keyboard-swiftui/)
- [How to Dismiss Keyboard in SwiftUI](https://medium.com/@akash.patel2520/how-to-dismiss-keyboard-in-swiftui-d410f12d8a56)
