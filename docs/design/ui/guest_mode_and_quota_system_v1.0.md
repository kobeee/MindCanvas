# 游客模式与配额系统设计文档

## 概述

本文档描述 MindCanvas 应用的游客登录模式、API Key 管理、免费额度系统和联系我们功能的详细设计方案。

## 需求分析

### 1. 游客登录模式

**需求描述**：
- 登录页面增加游客登录模式，允许用户免登录使用 APP
- 设置页新增登录入口，唤起登录页，登录成功后返回设置页，刷新账号信息
- 设置页列表新增账号设置，可设置账户名称，默认使用登录邮箱
- 游客模式下的退出登录处理（最优解）

**最优解分析**：

根据 UX 最佳实践和用户心理分析，游客模式下的退出登录应该：

**方案 A：退出后回到登录页**
- 优点：清晰明确，用户知道可以重新登录或选择游客模式
- 缺点：增加操作步骤，可能降低用户体验

**方案 B：退出后自动切换到游客模式（推荐）**
- 优点：用户体验流畅，无需额外操作，符合"快速退出"的 UX 原则
- 缺点：需要处理数据迁移和清理

**推荐方案**：方案 B - 退出后自动切换到游客模式

**理由**：
1. 符合现代 APP 的 UX 最佳实践（如 Notion、Figma 等）
2. 减少用户操作步骤，提升用户体验
3. 游客模式本身就是一种"未登录"状态，自然过渡
4. 用户可以随时在设置页重新登录

### 2. API Key 设置优化

**需求描述**：
- 支持删除 API Key
- 当前问题：输入为空时不给保存，不合理

**设计方案**：
- 添加"删除 API Key"按钮
- 当 API Key 已保存时，显示删除按钮
- 删除后清空输入框和 Keychain 存储
- 保存按钮允许保存空值（用于删除）

### 3. 游客模式限制

**需求描述**：
- 游客模式不给免费额度
- 只能使用 API Key 才可以使用生图功能

**设计方案**：
- 游客用户的 `free_quota` 为 0
- `api_provider` 默认为 "google"
- 生图前检查：游客用户必须有 API Key 才能使用

### 4. 首次登录免费额度

**需求描述**：
- Apple/Google/GitHub OAuth 认证登录或邮箱验证码登录，首次登录给 3 次免费使用额度

**设计方案**：
- 在后端 `auth_service.py` 中检测首次登录
- 首次登录自动设置 `free_quota = 3` 和 `api_provider = "laozhang"`
- 邮箱配额注入优先级高于首次登录额度

### 5. 联系我们优化

**需求描述**：
- 联系我们那一栏加一个"有福利"的标识
- 点击进去是扫描二维码关注公众号
- 提示："关注后私信可领取免费使用额度"

**设计方案**：
- 设置页"联系我们"项添加"有福利"徽章
- 联系我们页面添加免费额度提示
- 保持高端大气的 UI 设计

## 系统设计

### 后端改造

#### 1. 用户模型扩展

**文件**：`src/backend/app/models/user.py`

**修改内容**：
- 无需修改，现有模型已支持所需字段

#### 2. 认证服务改造

**文件**：`src/backend/app/services/auth_service.py`

**修改内容**：
- `_find_or_create_user` 方法：首次登录自动给予 3 次免费额度
- 添加 `is_first_login` 检测逻辑

#### 3. 配额服务改造

**文件**：`src/backend/app/services/quota_service.py`

**修改内容**：
- 无需修改，现有逻辑已支持

#### 4. 用户路由扩展

**文件**：`src/backend/app/routers/users.py`

**修改内容**：
- 添加更新用户名的接口

### iOS 端改造

#### 1. 用户模型扩展

**文件**：`src/MindCanvas/MindCanvas/Models/User.swift`

**修改内容**：
- 添加 `freeQuota`、`apiProvider` 等字段

#### 2. 认证管理器改造

**文件**：`src/MindCanvas/MindCanvas/Managers/AuthManager.swift`

**修改内容**：
- 添加 `isGuest` 属性
- 添加游客模式切换逻辑
- 添加用户名更新功能

#### 3. 登录页改造

**文件**：`src/MindCanvas/MindCanvas/Views/Auth/LoginView.swift`

**修改内容**：
- 添加游客登录按钮
- 添加返回设置页的逻辑

#### 4. 设置页改造

**文件**：`src/MindCanvas/MindCanvas/Views/Settings/SettingsView.swift`

**修改内容**：
- 添加登录入口（游客模式下显示）
- 添加账号设置项
- "联系我们"添加"有福利"徽章
- 退出登录改为切换到游客模式

#### 5. API Key 设置页改造

**文件**：`src/MindCanvas/MindCanvas/Views/Settings/APIConfigView.swift`

**修改内容**：
- 添加删除 API Key 按钮
- 保存按钮允许保存空值

#### 6. 联系我们页改造

**文件**：`src/MindCanvas/MindCanvas/Views/Settings/ContactUsView.swift`

**修改内容**：
- 添加免费额度提示

#### 7. 新建账号设置页

**文件**：`src/MindCanvas/MindCanvas/Views/Settings/AccountSettingsView.swift`

**新建内容**：
- 账户名称编辑
- 保存逻辑

#### 8. 新建游客模式视图

**文件**：`src/MindCanvas/MindCanvas/Views/Auth/GuestModeView.swift`

**新建内容**：
- 游客模式提示
- 登录引导

### 数据流程

#### 游客模式流程

```
用户启动 APP
    ↓
检查本地存储的登录状态
    ↓
如果未登录 → 创建游客用户（isGuest = true）
    ↓
进入主界面（游客模式）
    ↓
生图时检查：必须有 API Key
```

#### 登录流程

```
用户在设置页点击"登录"
    ↓
唤起登录页
    ↓
用户选择登录方式（Apple/Google/GitHub/邮箱）
    ↓
后端验证并返回 Token
    ↓
首次登录：自动给予 3 次免费额度
    ↓
iOS 端保存 Token，切换到已登录状态
    ↓
返回设置页，刷新账号信息
```

#### 退出登录流程

```
用户在设置页点击"退出登录"
    ↓
弹出确认对话框
    ↓
用户确认
    ↓
清除本地 Token 和用户数据
    ↓
创建游客用户（isGuest = true）
    ↓
刷新设置页（显示登录入口）
```

#### API Key 管理流程

```
用户打开 API Key 设置
    ↓
加载已保存的 API Key（从 Keychain）
    ↓
用户输入新的 API Key
    ↓
点击保存
    ↓
保存到 Keychain
    ↓
显示"已保存"状态
```

#### 删除 API Key 流程

```
用户打开 API Key 设置
    ↓
显示已保存的 API Key
    ↓
点击"删除"按钮
    ↓
弹出确认对话框
    ↓
用户确认
    ↓
清空输入框
    ↓
从 Keychain 删除
    ↓
隐藏"删除"按钮
```

### UI 设计规范

#### 主题色

- 主色调：品牌蓝色（`Theme.Colors.brandBlue`）
- 辅助色：金色渐变（`Theme.Colors.goldGradient`）
- 成功色：绿色（`Color.fromHex("#34C759")`）
- 警告色：橙色
- 错误色：红色（`Theme.Colors.destructive`）

#### 字体

- 大标题：`Theme.Fonts.largeTitle`
- 标题 2：`Theme.Fonts.title2`
- 标题 3：`Theme.Fonts.title3`
- 正文：`Theme.Fonts.body`
- 正文粗体：`Theme.Fonts.bodyBold`
- 标注：`Theme.Fonts.callout`

#### 间距

- 超大间距：`Theme.Spacing.xxxl`
- 大间距：`Theme.Spacing.xl`
- 中间距：`Theme.Spacing.lg`
- 小间距：`Theme.Spacing.md`
- 超小间距：`Theme.Spacing.xs`

#### 圆角

- 按钮圆角：`Theme.Shapes.buttonCornerRadius`
- 卡片圆角：`Theme.Shapes.cardCornerRadius`

### 安全考虑

#### 客户端安全

1. **API Key 存储**：使用 Keychain 安全存储
2. **Token 存储**：使用 Keychain 存储
3. **游客模式数据**：不持久化敏感数据

#### 服务端安全

1. **Token 验证**：每次请求验证 JWT Token
2. **配额检查**：生图前检查用户配额
3. **首次登录检测**：基于数据库记录判断

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

#### 联系我们测试

1. **显示徽章**
   - 设置页"联系我们"显示"有福利"徽章

2. **进入页面**
   - 点击进入联系我们页面
   - 显示免费额度提示

3. **保存二维码**
   - 点击保存按钮，保存到相册

## 实施计划

### 后端改造（优先级：高）

1. 修改 `auth_service.py`：首次登录自动给予 3 次免费额度
2. 添加用户名更新接口
3. 测试后端功能

### iOS 端改造（优先级：高）

1. 扩展 `User` 模型
2. 改造 `AuthManager`
3. 改造 `LoginView`
4. 改造 `SettingsView`
5. 改造 `APIConfigView`
6. 改造 `ContactUsView`
7. 新建 `AccountSettingsView`
8. 新建 `GuestModeView`
9. 测试 iOS 功能

### 部署和验证（优先级：高）

1. 同步后端代码到远程服务器
2. 重启后端服务
3. 验证所有功能
4. 代码审查

## 注意事项

1. **UI 一致性**：保持整体 UI 风格一致，高端大气
2. **用户体验**：所有交互要流畅，符合 iOS 设计规范
3. **错误处理**：所有网络请求要有错误处理
4. **数据安全**：敏感数据使用 Keychain 存储
5. **兼容性**：确保向后兼容，不影响现有功能