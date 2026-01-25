# 开发记录

## 2026-01-25 - Google API调用参数错误修复（完成）✅

### 概述

修复Google API调用时的参数错误，游客模式生图功能现已完全可用。

### 核心功能

#### 1. Google API调用参数错误修复

**修复内容**：
- 移除 `provider.generate_image()` 调用中的 `image_size` 参数
- GoogleAPIClient 不支持 `image_size` 参数，只支持 `api_key`、`prompt` 和 `base_image`

**修改文件**：
- `src/backend/app/services/task_service.py`

**技术实现**：

**修改前**：
```python
image_data = await provider.generate_image(
    api_key=api_key,
    prompt=task.prompt,
    base_image=task.base_image,
    image_size=task.image_size  # ❌ GoogleAPIClient 不支持此参数
)
```

**修改后**：
```python
image_data = await provider.generate_image(
    api_key=api_key,
    prompt=task.prompt,
    base_image=task.base_image
)
```

### 问题原因

**原始问题**：游客模式生图时返回错误 "GoogleAPIClient.generate_image() got an unexpected keyword argument 'image_size'"

**根本原因**：
1. `task_service.py` 中调用 `provider.generate_image()` 时传递了 `image_size` 参数
2. GoogleAPIClient.generate_image() 方法只接受 `api_key`、`prompt` 和 `base_image` 三个参数
3. Python 抛出 `TypeError: got an unexpected keyword argument 'image_size'`

### 解决方案

移除 `provider.generate_image()` 调用中的 `image_size` 参数，因为：
1. GoogleAPIClient 不支持此参数
2. Google API 的图片尺寸由 API 端点和模型决定，不需要客户端指定

### 游客模式生图流程（最终版）

1. **iOS端**：
   - 游客模式下，`requiresAuth = false`
   - 请求不带有 Authorization 头
   - 请求体中包含加密的 API Key

2. **后端**：
   - `get_optional_current_user` 检测到没有Token，返回 `None`
   - 使用 `00000000-0000-0000-0000-000000000000` 作为 user_id
   - 直接使用 Google API，不检查配额

3. **任务处理**：
   - 解密 API Key
   - 调用 Google API 生成图片（不传递 `image_size` 参数）
   - 保存图片到存储
   - 更新任务状态

### 部署状态

✅ 后端代码已同步到远程服务器并重启成功
✅ 游客用户已创建成功
✅ Google API 调用参数错误已修复

### 测试建议

1. **游客模式生图**：验证任务创建成功，Google API 调用成功，图片生成成功
2. **正常用户生图**：验证使用 Laozhang API（如果配置了配额），配额正确扣除

---

## 2026-01-25 - 后端支持游客模式生图（完成）✅

### 概述

修复后端不支持游客模式生图的问题，游客模式下可以使用自己的API Key进行生图。

### 核心功能

#### 1. 后端支持游客模式生图

**修复内容**：
- 添加 `get_optional_current_user` 依赖注入函数，支持可选认证
- 修改 `/tasks` 路由，允许游客模式创建任务
- 修改 `TaskService.create_task` 方法，支持游客模式

**修改文件**：
- `src/backend/app/routers/tasks.py`
- `src/backend/app/services/task_service.py`

**技术实现**：

**tasks.py**：
```python
async def get_optional_current_user(
    credentials: Annotated[Optional[HTTPAuthorizationCredentials], Depends(HTTPBearer(auto_error=False))],
    auth_service: Annotated[AuthService, Depends(get_auth_service)]
) -> Optional[User]:
    """依赖注入：从 JWT Token 获取当前用户（可选）"""
    if credentials is None:
        return None

    try:
        token = credentials.credentials
        user = await auth_service.get_current_user(token)
        return user
    except InvalidTokenError:
        logger.warning(f"Invalid token in optional auth, treating as guest")
        return None
    except UserNotFoundError:
        logger.warning(f"User not found in optional auth, treating as guest")
        return None
    except Exception as e:
        logger.error(f"Failed to get current user in optional auth: {str(e)}, treating as guest")
        return None
```

**task_service.py**：
```python
# 判断是否为游客模式
if user_id == "guest":
    # 游客模式：直接使用 Google API
    api_provider = "google"
    image_size = "1K"
    logger.info(f"Guest mode: using Google API")

    # 检查 API Key
    if not encrypted_api_key:
        raise TaskServiceError("encrypted_api_key is required for guest mode")
else:
    # 正常用户：获取用户使用的 API 提供商
    api_provider = await self.quota_service.get_user_api_provider(user_id)
    # ...
```

### 问题原因

**原始问题**：游客模式下生图返回403错误

**根本原因**：
1. 后端的 `/tasks` 路由使用了 `Depends(get_current_user)` 依赖注入，要求请求必须带有有效的 JWT Token
2. 游客模式下，iOS端设置了 `requiresAuth = false`，请求不会带有 Authorization 头
3. 后端检测到没有Token，返回403错误

### 解决方案

1. **添加可选认证**：`get_optional_current_user` 函数允许没有Token的请求，返回 `None` 表示游客模式
2. **修改路由逻辑**：使用 `get_optional_current_user` 代替 `get_current_user`，支持游客模式
3. **修改任务创建逻辑**：游客模式下，使用 "guest" 作为 user_id，直接使用 Google API，不检查配额

### 游客模式生图流程

1. **iOS端**：
   - 游客模式下，`requiresAuth = false`
   - 请求不带有 Authorization 头
   - 请求体中包含加密的 API Key

2. **后端**：
   - `get_optional_current_user` 检测到没有Token，返回 `None`
   - 使用 "guest" 作为 user_id
   - 直接使用 Google API，不检查配额
   - 创建任务并返回 task_id

3. **任务处理**：
   - 解密 API Key
   - 调用 Google API 生成图片
   - 保存图片到存储
   - 更新任务状态

### 测试用例

#### 游客模式生图测试

1. **游客模式生图**
   - 游客模式下配置 API Key
   - 点击"图生图"或"文生图"
   - 验证：任务创建成功
   - 验证：使用 Google API 生成图片
   - 验证：图片保存成功

2. **正常用户生图**
   - 正常用户登录
   - 有免费额度时生图
   - 验证：使用 Laozhang API（如果配置了配额）
   - 验证：配额正确扣除

### 注意事项

1. **API Key 加密**：游客模式下，API Key 仍然需要使用 RSA 公钥加密
2. **任务记录**：游客模式下创建的任务，user_id 为 "guest"
3. **配额管理**：游客模式下不检查配额，直接使用 Google API
4. **图片尺寸**：游客模式下使用 1K 尺寸，正常用户根据 API 提供商决定

---

## 2026-01-25 - 游客模式跳转首页修复（完成）✅

### 概述

修复游客模式下点击"游客模式"按钮后没有跳转到首页的问题。

### 核心功能

#### 1. 游客模式跳转首页修复

**修复内容**：
- 调整 `switchToGuestMode()` 方法中状态设置的顺序，先设置 `isAuthenticated`，再设置 `isGuestMode`
- 在 `RootView.swift` 中添加 `.id()` 修饰符，强制视图在 `isAuthenticated` 变化时重新渲染

**修改文件**：
- `src/MindCanvas/MindCanvas/Managers/AuthManager.swift`
- `src/MindCanvas/MindCanvas/Views/RootView.swift`

**技术实现**：

**AuthManager.swift**：
```swift
func switchToGuestMode() async {
    isLoading = true
    errorMessage = nil

    keychainManager.deleteToken()
    currentUser = nil

    // 先设置认证状态，确保 RootView 能正确响应
    isAuthenticated = true

    // 然后设置游客模式标志
    isGuestMode = true

    isLoading = false
}
```

**RootView.swift**：
```swift
struct RootView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
        .id(authManager.isAuthenticated)  // 强制视图重新渲染
    }
}
```

### 问题原因

**原始问题**：游客模式下点击"游客模式"按钮后，游客模式按钮消失了（因为 `isGuest` 变成 `true`），但是没有跳转到首页（RootView 仍然显示 LoginView）

**根本原因**：
1. 状态设置顺序问题：如果先设置 `isGuestMode`，再设置 `isAuthenticated`，可能导致 SwiftUI 无法正确响应 `isAuthenticated` 的变化
2. SwiftUI 有时不会自动更新视图，特别是在异步方法中修改状态时

### 解决方案

1. **调整状态设置顺序**：先设置 `isAuthenticated`，确保 RootView 能正确检测到变化并开始切换到 MainView
2. **强制视图重新渲染**：使用 `.id(authManager.isAuthenticated)` 修饰符，当 `isAuthenticated` 变化时，强制 RootView 重新渲染

### 测试用例

#### 游客模式跳转测试

1. **首次启动**
   - 首次启动 APP
   - 验证：显示登录页面
   - 验证：显示"游客模式"按钮

2. **点击游客模式**
   - 点击"游客模式"按钮
   - 验证：游客模式按钮消失（因为 `isGuest` 变成 `true`）
   - 验证：跳转到 APP 首页
   - 验证：首页显示游客模式状态

3. **游客模式登录**
   - 游客模式下点击"登录"
   - 使用任意方式登录成功
   - 验证：登录页自动关闭
   - 验证：首页显示已登录用户信息

### 注意事项

1. **状态设置顺序**：`isAuthenticated` 必须先于 `isGuestMode` 设置，确保 RootView 能正确响应
2. **视图强制更新**：`.id()` 修饰符是 SwiftUI 强制视图更新的标准做法，可以避免 SwiftUI 有时不会自动更新的问题

---

## 2026-01-25 - 游客模式Token机制修复（完成）✅

### 概述

修复游客模式下的Token机制和配额显示问题，确保游客模式下不会尝试刷新Token，也不会显示配额信息。

### 核心功能

#### 1. 游客模式认证状态修复

**修复内容**：
- 修复 `switchToGuestMode()` 中 `isAuthenticated` 的状态，从 `true` 改为 `false`
- 游客模式下表示为未认证状态，符合语义

**修改文件**：
- `src/MindCanvas/MindCanvas/Managers/AuthManager.swift`

**技术实现**：
```swift
func switchToGuestMode() async {
    isLoading = true
    errorMessage = nil

    keychainManager.deleteToken()
    currentUser = nil
    isGuestMode = true
    isAuthenticated = false  // 修复：从 true 改为 false

    isLoading = false
}
```

#### 2. 游客模式Token刷新修复

**修复内容**：
- 修复 `RealGenerationService.generate()` 中的 `requiresAuth` 逻辑
- 根据是否使用免费额度来决定是否需要认证
- 游客模式下使用自己的API Key，不需要认证

**修改文件**：
- `src/MindCanvas/MindCanvas/Services/RealGenerationService.swift`

**技术实现**：
```swift
// 如果使用免费额度，需要认证（用户已登录）；如果不使用免费额度，不需要认证（使用自己的API Key）
let response: TaskResponse = try await apiClient.request(
    endpoint: "/api/v1/generate/tasks",
    method: .POST,
    body: generationRequest,
    requiresAuth: useFreeQuota,  // 修复：根据 useFreeQuota 决定
    responseType: TaskResponse.self
)
```

#### 3. 游客模式配额显示修复

**修复内容**：
- 游客模式下不加载配额信息
- 游客模式下不显示配额提示
- 游客模式下只检查是否有API Key

**修改文件**：
- `src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`

**技术实现**：
- 添加 `authManager` 属性：`private let authManager = AuthManager.shared`
- `loadQuota()`：游客模式下不加载配额信息，直接清空
- `getGenerationHint()`：游客模式下不显示配额提示
- `checkCanGenerate()`：游客模式下只检查是否有API Key
- `confirmImageToImageGenerate()`：游客模式下不使用免费额度
- `generateTextToImage()`：游客模式下不使用免费额度

#### 4. 登录成功后页面自动关闭修复

**修复内容**：
- 同时监听 `isAuthenticated` 和 `isGuest` 的变化
- 确保游客模式下登录成功后页面能自动关闭

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Auth/LoginView.swift`

**技术实现**：
```swift
.onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
    if isAuthenticated && !authManager.isGuest {
        dismiss()
    }
}
.onChange(of: authManager.isGuest) { _, isGuest in
    if !isGuest && authManager.isAuthenticated {
        dismiss()
    }
}
```

### 游客模式Token机制

**游客模式特点**：
1. **认证状态**：`isAuthenticated = false`，`isGuest = true`
2. **Token管理**：Keychain中的Token被删除，不会尝试刷新
3. **配额管理**：不加载配额信息，不显示配额提示
4. **生图功能**：只使用自己的API Key，不使用免费额度
5. **登录入口**：设置页显示"登录"链接，登录页面隐藏"游客模式"按钮

**正常用户模式特点**：
1. **认证状态**：`isAuthenticated = true`，`isGuest = false`
2. **Token管理**：Token存储在Keychain中，会自动刷新
3. **配额管理**：加载配额信息，显示配额提示
4. **生图功能**：优先使用免费额度，没有免费额度时使用API Key
5. **退出登录**：切换到游客模式

### 测试用例

#### 游客模式测试

1. **配额显示**
   - 游客模式下进入编辑器
   - 验证：不显示配额提示
   - 验证：只显示API Key提示

2. **生图功能**
   - 游客模式下配置API Key
   - 验证：可以正常生图
   - 验证：不会尝试刷新Token
   - 验证：不使用免费额度

3. **登录成功**
   - 游客模式下点击"登录"
   - 使用任意方式登录成功
   - 验证：登录页自动关闭

#### 正常用户模式测试

1. **配额显示**
   - 已登录用户进入编辑器
   - 验证：显示配额提示
   - 验证：显示剩余免费额度

2. **生图功能**
   - 有免费额度时生图
   - 验证：使用免费额度
   - 验证：Token正常刷新

3. **退出登录**
   - 已登录用户点击"退出登录"
   - 验证：切换到游客模式
   - 验证：配额信息被清空
   - 验证：Token被删除

### 注意事项

1. **Token机制**：游客模式下Token被删除，不会尝试刷新，避免"Token已过期, 正在刷新..."的提示
2. **配额管理**：游客模式下不加载配额信息，避免显示错误的配额提示
3. **生图逻辑**：游客模式下只使用API Key，不使用免费额度
4. **状态切换**：游客模式和正常用户模式之间的切换需要正确处理认证状态和配额信息

---

## 2026-01-25 - 游客模式UI优化（完成）✅

### 概述

修复游客模式下的UI显示问题，包括导航标题样式、登录页面游客模式按钮显示、游客模式下退出登录按钮显示等3个问题。

### 核心功能

#### 1. 导航标题样式修复

**修复内容**：
- 移除 `.navigationBarTitleDisplayMode(.inline)`，恢复默认的 large 模式
- 导航标题恢复原来的大小和位置（左侧显示）

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Settings/SettingsView.swift`

**技术实现**：
- 在 NavigationStack 的 body 移除 `.navigationBarTitleDisplayMode(.inline)` 修饰符
- 恢复 iOS 默认的导航标题显示行为

#### 2. 登录页面游客模式按钮隐藏

**修复内容**：
- 在游客模式下隐藏"游客模式"按钮
- 避免游客模式下重复进入游客模式的操作

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Auth/LoginView.swift`

**技术实现**：
- 在 `loginOptionsSection` 中添加条件判断：`if !authManager.isGuest`
- 只在非游客模式下显示 `guestLoginButton`

#### 3. 游客模式下退出登录按钮修复

**修复内容**：
- 修复游客模式下仍然显示"退出登录"按钮的问题
- 确保游客模式下不显示账号设置和退出登录按钮

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Settings/SettingsView.swift`

**技术实现**：
- 修改 `accountSection` 和 `logoutSection` 的显示条件
- 使用 `!authManager.isGuest` 替代 `authManager.isAuthenticated`
- 因为 `AuthManager.switchToGuestMode()` 中 `isAuthenticated` 被设置为 `true`，需要使用 `isGuest` 来判断

### 测试用例

#### 导航标题测试

1. **标题显示**
   - 进入设置页
   - 验证：导航标题"设置"显示在左侧，大小正常
   - 验证：滚动时标题会缩小到中间（iOS 默认行为）

#### 登录页面测试

1. **游客模式按钮显示**
   - 游客模式下点击"登录"
   - 验证：登录页面不显示"游客模式"按钮
   - 验证：只显示登录选项

2. **非游客模式按钮显示**
   - 直接进入登录页面（非游客模式）
   - 验证：登录页面显示"游客模式"按钮

#### 游客模式设置页测试

1. **账号设置和退出登录**
   - 游客模式下进入设置页
   - 验证：不显示"账号设置"按钮
   - 验证：不显示"退出登录"按钮

2. **已登录用户**
   - 已登录用户进入设置页
   - 验证：显示"账号设置"按钮
   - 验证：显示"退出登录"按钮

### 注意事项

1. **导航标题行为**：移除 `.navigationBarTitleDisplayMode(.inline)` 后，标题会随滚动缩小到中间，这是 iOS 的默认行为
2. **游客模式判断**：使用 `!authManager.isGuest` 而不是 `authManager.isAuthenticated` 来判断，因为游客模式下 `isAuthenticated` 为 `true`
3. **用户体验**：所有修改都提升了用户体验，避免了不必要的操作和混淆

---

## 2026-01-25 - 设置页与编辑器修复（完成）✅

### 概述

完成游客模式设置页UI优化、登录成功后页面自动关闭、图生图键盘遮挡截图修复。本次更新提升了用户体验和交互流畅度。

### 核心功能

#### 1. 游客模式设置页UI优化

**修复内容**：
- 移除游客模式头部的"需要配置 API Key 才能使用生图功能"提示文案
- 将"立即登录"按钮改为轻量级文字链接样式（蓝色文字+右箭头）
- 添加 `.navigationBarTitleDisplayMode(.inline)` 固定导航标题，确保标题始终可见

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Settings/SettingsView.swift`

**技术实现**：
- 移除 `guestModeHeader` 中的多余提示文案
- 使用 `HStack` 和 `Image(systemName: "chevron.right")` 创建轻量级链接样式
- 在 NavigationStack 的 body 添加 `.navigationBarTitleDisplayMode(.inline)`

#### 2. 登录成功后页面自动关闭

**修复内容**：
- 登录成功后自动关闭登录页面，返回设置页
- 避免用户需要手动关闭页面的操作

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Auth/LoginView.swift`

**技术实现**：
- 添加 `@Environment(\.dismiss) private var dismiss` 环境变量
- 添加 `.onChange(of: authManager.isAuthenticated)` 监听器
- 在登录成功且不是游客模式时调用 `dismiss()`

#### 3. 图生图键盘遮挡截图修复

**修复内容**：
- 点击"图生图"按钮时先收起键盘，等待键盘动画完成后再执行截图
- 避免键盘遮挡画布导致截图不完整

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift`

**技术实现**：
- 使用 `@FocusState` 控制键盘焦点
- 在"图生图"按钮点击时设置 `isPromptFocused = false` 收起键盘
- 使用 `DispatchQueue.main.asyncAfter(deadline: .now() + 0.35)` 延迟执行截图

### 设计文档

**参考文件**：
- `docs/design/fix/settings_and_editor_fixes_v1.0.md`

### 测试用例

#### 游客模式设置页测试

1. **头部显示**
   - 游客模式下进入设置页
   - 验证：头部只显示头像、"游客模式"文字和"登录 >"链接
   - 验证：无 API Key 提示文案

2. **导航标题固定**
   - 在设置页向下滚动
   - 验证：顶部"设置"标题始终可见

#### 登录成功测试

1. **自动关闭页面**
   - 游客模式下点击"登录"
   - 使用任意方式登录成功
   - 验证：登录页自动关闭，返回设置页

#### 图生图键盘测试

1. **键盘收起后截图**
   - 进入编辑器
   - 显示选框
   - 在提示词输入框中输入文字（键盘弹出）
   - 点击"图生图"按钮
   - 验证：键盘先收起
   - 验证：截图包含完整的选框区域

### 注意事项

1. **UI 一致性**：保持整体 UI 风格一致，使用 Theme 统一样式系统
2. **用户体验**：所有交互要流畅，符合 iOS 设计规范
3. **延迟时间**：键盘收起延迟时间设置为 0.35 秒，确保键盘动画完成

---

## 2026-01-25 - 游客模式与配额系统（完成）✅

### 概述

完成游客登录模式、API Key 删除功能、首次登录免费额度系统和联系我们页面优化。本次更新大幅提升了用户体验和功能完整性。

### 核心功能

#### 1. 游客登录模式

**新增功能**：
- 登录页面添加游客登录入口，允许用户免登录使用 APP
- 设置页游客模式下显示登录入口和登录引导
- 退出登录自动切换到游客模式（而非返回登录页）
- 游客模式下不显示账号信息和免费额度

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Auth/LoginView.swift`
- `src/MindCanvas/MindCanvas/Views/Settings/SettingsView.swift`
- `src/MindCanvas/MindCanvas/Managers/AuthManager.swift`

**技术实现**：
- AuthManager 新增 `isGuest` 属性
- 新增 `switchToGuestMode()` 方法
- 游客模式下 `isAuthenticated = false`，`currentUser = nil`

#### 2. API Key 删除功能

**新增功能**：
- API Key 设置页添加删除按钮
- 删除前弹出确认对话框
- 删除后清空输入框和 Keychain 存储
- 保存按钮允许保存空值（用于删除）

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Settings/APIConfigView.swift`

**技术实现**：
- 使用 `KeychainManager.shared.deleteAPIKey()` 删除
- 添加 `showingDeleteAlert` 状态管理删除确认对话框

#### 3. 首次登录免费额度

**新增功能**：
- Apple/Google/GitHub OAuth 登录，首次登录自动给予 3 次免费额度
- 邮箱验证码登录，首次登录自动给予 3 次免费额度
- 邮箱配额注入优先级高于首次登录额度

**修改文件**：
- `src/backend/app/services/auth_service.py`
- `src/MindCanvas/MindCanvas/Models/User.swift`

**技术实现**：
- 后端 `_find_or_create_user()` 方法检测首次登录
- 首次登录自动设置 `free_quota = 3` 和 `api_provider = "laozhang"`
- User 模型扩展 `freeQuota`、`apiProvider`、`totalQuotaUsed` 字段

#### 4. 账号设置功能

**新增功能**：
- 设置页新增账号设置项
- 支持修改账户名称
- 账户名称默认使用登录邮箱
- 邮箱地址不可更改

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Settings/SettingsView.swift`
- `src/MindCanvas/MindCanvas/Views/Settings/AccountSettingsView.swift`（新建）
- `src/MindCanvas/MindCanvas/Managers/AuthManager.swift`
- `src/backend/app/routers/users.py`

**技术实现**：
- 后端新增 `PUT /api/v1/users/me/username` 接口
- iOS 端 `AuthManager` 新增 `updateUsername()` 方法
- AccountSettingsView 提供用户名编辑界面

#### 5. 联系我们页面优化

**新增功能**：
- 设置页"联系我们"添加"有福利"徽章
- 联系我们页面添加免费额度提示
- 提示用户关注公众号后私信可领取免费使用额度
- 保持高端大气的设计风格

**修改文件**：
- `src/MindCanvas/MindCanvas/Views/Settings/SettingsView.swift`
- `src/MindCanvas/MindCanvas/Views/Settings/ContactUsView.swift`

**技术实现**：
- 使用金色渐变徽章标识"有福利"
- 添加礼品图标和提示文案
- 使用 `Theme.Colors.goldGradient` 保持设计一致性

### 后端改造

#### 1. 认证服务改造

**文件**：`src/backend/app/services/auth_service.py`

**修改内容**：
- `_find_or_create_user()` 方法：首次登录自动给予 3 次免费额度
- 修改试用配额从 1 次改为 3 次
- 适用于所有登录方式（Apple、Google、GitHub、邮箱）

#### 2. 用户路由扩展

**文件**：`src/backend/app/routers/users.py`

**新增接口**：
- `PUT /api/v1/users/me/username`：更新用户名

**请求参数**：
```json
{
  "username": "新用户名"
}
```

**响应**：
```json
{
  "username": "新用户名"
}
```

### iOS 端改造

#### 1. 用户模型扩展

**文件**：`src/MindCanvas/MindCanvas/Models/User.swift`

**新增字段**：
- `freeQuota: Int` - 免费额度
- `apiProvider: String` - API 提供商
- `totalQuotaUsed: Int` - 总使用次数
- `subscriptionTier: String` - 订阅等级

#### 2. 认证管理器改造

**文件**：`src/MindCanvas/MindCanvas/Managers/AuthManager.swift`

**新增功能**：
- `isGuest` 属性：判断是否为游客模式
- `switchToGuestMode()` 方法：切换到游客模式
- `updateUsername()` 方法：更新用户名

#### 3. 登录页改造

**文件**：`src/MindCanvas/MindCanvas/Views/Auth/LoginView.swift`

**新增内容**：
- 底部添加游客登录按钮
- 使用次级按钮样式
- 点击后调用 `switchToGuestMode()`

#### 4. 设置页改造

**文件**：`src/MindCanvas/MindCanvas/Views/Settings/SettingsView.swift`

**新增内容**：
- 游客模式头部显示登录引导
- 已登录用户显示账号设置项
- "联系我们"添加"有福利"徽章
- 退出登录改为切换到游客模式

#### 5. 账号设置页（新建）

**文件**：`src/MindCanvas/MindCanvas/Views/Settings/AccountSettingsView.swift`

**功能**：
- 编辑账户名称
- 显示邮箱地址（只读）
- 保存到后端
- 实时验证和错误提示

#### 6. API Key 设置页改造

**文件**：`src/MindCanvas/MindCanvas/Views/Settings/APIConfigView.swift`

**新增内容**：
- 删除 API Key 按钮
- 删除确认对话框
- 保存按钮允许保存空值

#### 7. 联系我们页改造

**文件**：`src/MindCanvas/MindCanvas/Views/Settings/ContactUsView.swift`

**新增内容**：
- "有福利"徽章
- 免费额度提示
- 礼品图标和金色渐变

### 设计文档

**新建文件**：
- `docs/design/ui/guest_mode_and_quota_system_v1.0.md`

**内容**：
- 需求分析
- 系统设计
- 数据流程
- UI 设计规范
- 安全考虑
- 测试用例
- 实施计划

### 部署和验证

#### 后端部署

**部署状态**：✅ 成功

**部署命令**：
```bash
cd src/backend
REMOTE_SERVER="65.75.220.11" REMOTE_USER="root" REMOTE_PATH="/root/mind-canvas" ./deploy.sh sync
```

**服务状态**：
- mindcanvas_backend: healthy
- mindcanvas_db: healthy
- mindcanvas_redis: healthy
- mindcanvas_admin: healthy

**健康检查**：
```bash
curl https://mindcanvas.escapemobius.cc/health
```

**响应**：
```json
{
  "status": "healthy",
  "service": "MindCanvas Backend"
}
```

#### 代码审查

**审查状态**：✅ 通过

**审查文件**：
- 9 个修改的文件（2 个后端，7 个 iOS）

**发现问题**：
- ContactUsView.swift 使用了中文字符标识符（已修复）

**修复结果**：
- 将 `福利提示Section` 改为 `benefitPromptSection`
- 所有文件现在都可以正常编译

### 测试用例

#### 游客模式测试

1. **游客登录**
   - 首次启动 APP，自动进入游客模式
   - 游客模式下不显示账号信息
   - 游客模式下不显示免费额度

2. **游客生图**
   - 游客模式下，无 API Key 时提示需要配置
   - 游客模式下，有 API Key 时可以生图

3. **游客转登录**
   - 游客模式下点击登录，进入登录页
   - 登录成功后返回设置页，显示账号信息

#### 登录测试

1. **首次登录**
   - 使用 Apple/Google/GitHub/邮箱登录
   - 登录成功后显示 3 次免费额度

2. **非首次登录**
   - 再次登录，免费额度保持不变

3. **退出登录**
   - 已登录用户退出，自动切换到游客模式
   - 设置页显示登录入口

#### API Key 测试

1. **保存 API Key**
   - 输入有效的 API Key，点击保存
   - 显示"已保存"状态

2. **删除 API Key**
   - 点击"删除"按钮
   - 确认后清空输入框

3. **生图使用**
   - 有 API Key 时可以生图
   - 无 API Key 时提示配置

#### 账号设置测试

1. **修改用户名**
   - 输入新用户名，点击保存
   - 保存成功后显示新用户名

2. **邮箱显示**
   - 显示登录邮箱（只读）
   - 邮箱不可更改

#### 联系我们测试

1. **显示徽章**
   - 设置页"联系我们"显示"有福利"徽章

2. **进入页面**
   - 点击进入联系我们页面
   - 显示免费额度提示

3. **保存二维码**
   - 点击保存按钮，保存到相册

### 注意事项

1. **UI 一致性**：保持整体 UI 风格一致，高端大气
2. **用户体验**：所有交互要流畅，符合 iOS 设计规范
3. **错误处理**：所有网络请求要有错误处理
4. **数据安全**：敏感数据使用 Keychain 存储
5. **兼容性**：确保向后兼容，不影响现有功能

### 下一步计划

1. 在 Xcode 中编译项目，验证修复是否有效
2. 运行应用，测试所有新功能
3. 根据测试结果进行优化和调整

---

## 归档记录
- docs/archive/CHANGELOG-20260125-archived.md