# iOS 登录功能后端适配 - 配置指南

**文档版本**: v1.0
**创建日期**: 2026-01-01
**目标**: 为 iOS 登录功能后端适配改造提供详细的配置指南

---

## 一、概述

本文档提供了完成 iOS 登录功能后端适配改造所需的详细配置步骤，包括系统框架配置、URL Scheme 配置、Info.plist 配置以及第三方 OAuth 凭证获取指南。

---

## 二、系统框架配置

### 2.1 AuthenticationServices 框架

**用途**: Apple Sign In 功能

**配置步骤**:

1. 打开 Xcode 项目
2. 选择项目 target
3. 进入 "General" 标签页
4. 找到 "Frameworks, Libraries, and Embedded Content" 部分
5. 点击 "+" 按钮
6. 搜索并添加 `AuthenticationServices.framework`

**验证**:
- 在项目导航器中，找到 `Frameworks` 文件夹
- 确认 `AuthenticationServices.framework` 已添加

### 2.2 GoogleSignIn 框架

**用途**: Google Sign In 功能

**推荐安装方式**: Swift Package Manager

**配置步骤**:

1. 打开 Xcode 项目
2. 选择项目 target
3. 进入 "Package Dependencies" 标签页
4. 点击 "+" 按钮
5. 在搜索框中输入: `https://github.com/google/GoogleSignIn-iOS`
6. 选择最新版本（推荐 7.0.0 或更高）
7. 点击 "Add Package"
8. 选择 `GoogleSignIn` 库
9. 点击 "Add Package"

**验证**:
- 在项目导航器中，找到 `Package Dependencies` 文件夹
- 确认 `GoogleSignIn` 已添加

**备选安装方式**: CocoaPods

```ruby
# Podfile
pod 'GoogleSignIn', '~> 7.0'
```

---

## 三、URL Scheme 配置

### 3.1 添加 URL Scheme

**用途**: GitHub OAuth 回调

**配置步骤**:

1. 打开 Xcode 项目
2. 选择项目 target
3. 进入 "Info" 标签页
4. 找到 "URL Types" 部分
5. 点击 "+" 按钮
6. 填写以下信息:
   - **Identifier**: `com.mindcanvas.auth`
   - **URL Schemes**: `mindcanvas`
   - **Role**: `Editor`

**验证**:
- 在 `Info.plist` 文件中，应该能看到以下配置:
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.mindcanvas.auth</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>mindcanvas</string>
        </array>
    </dict>
</array>
```

---

## 四、Info.plist 配置

### 4.1 Google Sign In 配置

**配置项**: `GIDClientID`

**配置步骤**:

1. 打开 `Info.plist` 文件
2. 添加以下配置:
```xml
<key>GIDClientID</key>
<string>YOUR_GOOGLE_CLIENT_ID</string>
```

**获取 Google Client ID**:
- 访问 [Google Cloud Console](https://console.cloud.google.com/)
- 创建或选择项目
- 启用 Google Sign-In API
- 创建 OAuth 2.0 客户端 ID
- 选择 "iOS" 应用类型
- 填写 Bundle Identifier: `com.elvis.MindCanvas`
- 下载配置文件（可选）
- 复制 Client ID

**示例**:
```xml
<key>GIDClientID</key>
<string>123456789-abcdefghijklmnopqrstuvwxyz.apps.googleusercontent.com</string>
```

### 4.2 GitHub OAuth 配置

**配置项**: `GitHubClientID` 和 `GitHubClientSecret`

**配置步骤**:

1. 打开 `Info.plist` 文件
2. 添加以下配置:
```xml
<key>GitHubClientID</key>
<string>YOUR_GITHUB_CLIENT_ID</string>
<key>GitHubClientSecret</key>
<string>YOUR_GITHUB_CLIENT_SECRET</string>
```

**获取 GitHub OAuth 凭证**:
- 访问 [GitHub Developer Settings](https://github.com/settings/developers)
- 点击 "New OAuth App"
- 填写以下信息:
  - **Application name**: MindCanvas
  - **Homepage URL**: `http://localhost:8000`
  - **Application description**: MindCanvas AI Art App
  - **Authorization callback URL**: `mindcanvas://auth`
- 点击 "Register application"
- 复制 Client ID 和 Client Secret

**示例**:
```xml
<key>GitHubClientID</key>
<string>iv1234567890abcdef</string>
<key>GitHubClientSecret</key>
<string>ghp_1234567890abcdefghijklmnopqrstuvwxyz</string>
```

### 4.3 完整的 Info.plist 配置示例

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- 其他配置... -->

    <!-- Google Sign In -->
    <key>GIDClientID</key>
    <string>YOUR_GOOGLE_CLIENT_ID</string>

    <!-- GitHub OAuth -->
    <key>GitHubClientID</key>
    <string>YOUR_GITHUB_CLIENT_ID</string>
    <key>GitHubClientSecret</key>
    <string>YOUR_GITHUB_CLIENT_SECRET</string>

    <!-- URL Types -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>CFBundleURLName</key>
            <string>com.mindcanvas.auth</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>mindcanvas</string>
            </array>
        </dict>
    </array>

    <!-- 其他配置... -->
</dict>
</plist>
```

---

## 五、第三方 OAuth 凭证获取指南

### 5.1 Apple Sign In 配置

**配置平台**: Apple Developer Portal

**配置步骤**:

1. 访问 [Apple Developer Portal](https://developer.apple.com/)
2. 进入 "Certificates, Identifiers & Profiles"
3. 选择 "Identifiers"
4. 选择或创建 App ID
5. 启用 "Sign In with Apple" 能力
6. 保存并下载配置文件（如需要）

**注意事项**:
- Apple Sign In 不需要在 Info.plist 中配置 Client ID
- Apple 会自动使用 Bundle Identifier 生成 Client ID
- 需要在 Apple Developer Portal 中启用 "Sign In with Apple" 能力

### 5.2 Google Sign In 配置

**配置平台**: Google Cloud Console

**配置步骤**:

1. 访问 [Google Cloud Console](https://console.cloud.google.com/)
2. 创建或选择项目
3. 进入 "APIs & Services" > "Library"
4. 搜索并启用以下 API:
   - Google Sign-In API
5. 进入 "APIs & Services" > "Credentials"
6. 点击 "Create Credentials" > "OAuth client ID"
7. 选择应用类型: "iOS"
8. 配置 OAuth consent screen（首次使用时）
9. 填写 Bundle Identifier: `com.elvis.MindCanvas`
10. 创建并复制 Client ID

**OAuth Consent Screen 配置**:
- **App name**: MindCanvas
- **User support email**: your-email@example.com
- **Developer contact information**: your-email@example.com
- **Scopes for Google API**: 添加 `.../auth/userinfo.email` 和 `.../auth/userinfo.profile`

**注意事项**:
- 记录 Client ID 并配置到 Info.plist
- 确保应用类型为 "iOS"
- Bundle Identifier 必须与 Xcode 项目中的 Bundle Identifier 一致

### 5.3 GitHub OAuth 配置

**配置平台**: GitHub Developer Settings

**配置步骤**:

1. 访问 [GitHub Developer Settings](https://github.com/settings/developers)
2. 点击 "New OAuth App"
3. 填写以下信息:
   - **Application name**: MindCanvas
   - **Homepage URL**: `http://localhost:8000`
   - **Application description**: MindCanvas AI Art App
   - **Authorization callback URL**: `mindcanvas://auth`
4. 点击 "Register application"
5. 复制 Client ID 和 Client Secret

**注意事项**:
- Authorization callback URL 必须与代码中的 `redirectURI` 一致
- Client Secret 是敏感信息，不要泄露
- 将 Client ID 和 Client Secret 配置到 Info.plist

---

## 六、后端服务配置

### 6.1 启动本地后端服务

**前提条件**:
- Docker 已安装
- Docker Compose 已安装

**启动步骤**:

1. 进入后端目录:
```bash
cd src/backend
```

2. 启动服务:
```bash
docker-compose up -d
```

3. 查看日志:
```bash
docker-compose logs -f
```

4. 停止服务:
```bash
docker-compose down
```

**验证服务**:
- 访问: `http://localhost:8000/docs`
- 确认 API 文档页面正常显示

### 6.2 配置环境变量

**文件**: `src/backend/.env`

**配置项**:
```env
# 数据库配置
DATABASE_URL=postgresql+asyncpg://mindcanvas:mindcanvas@db:5432/mindcanvas

# Redis 配置
REDIS_URL=redis://redis:6379/0

# JWT 配置
JWT_SECRET_KEY=your-secret-key-here

# 邮件服务配置
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password

# 加密配置
ENCRYPTION_SECRET_KEY=your-encryption-secret-key-here

# Google API 配置
GOOGLE_API_KEY=your-google-api-key-here
```

**注意事项**:
- 修改 `JWT_SECRET_KEY` 为随机字符串
- 修改 `ENCRYPTION_SECRET_KEY` 为随机字符串
- 配置邮件服务（可选，用于邮箱验证码登录）
- 配置 Google API Key（用于 AI 图像生成）

---

## 七、编译和运行

### 7.1 编译项目

**步骤**:

1. 打开 Xcode 项目
2. 选择目标设备（iPad 模拟器或真机）
3. 点击 "Product" > "Build" (⌘B)
4. 检查编译结果

**常见编译错误**:

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| No such module 'GoogleSignIn' | GoogleSignIn 框架未安装 | 通过 Swift Package Manager 安装 |
| Use of unresolved identifier 'ASAuthorizationAppleIDProvider' | AuthenticationServices 框架未添加 | 在 Frameworks 中添加 AuthenticationServices.framework |
| Value of type 'GoogleSignInManager' has no member 'configure' | GoogleSignInManager.configure() 调用错误 | 添加 try-catch 错误处理 |

### 7.2 运行项目

**步骤**:

1. 打开 Xcode 项目
2. 选择目标设备（iPad 模拟器或真机）
3. 点击 "Product" > "Run" (⌘R)
4. 等待应用启动

**验证登录功能**:

1. **Apple Sign In**:
   - 点击 "使用 Apple 登录" 按钮
   - 在弹出的 Apple 登录页面中授权
   - 验证登录成功

2. **Google Sign In**:
   - 点击 "使用 Google 登录" 按钮
   - 在弹出的 Google 登录页面中授权
   - 验证登录成功

3. **GitHub OAuth**:
   - 点击 "使用 GitHub 登录" 按钮
   - 在弹出的 GitHub 授权页面中授权
   - 验证登录成功

4. **邮箱验证码登录**:
   - 输入邮箱地址
   - 点击 "发送验证码" 按钮
   - 检查邮箱（或后端日志）获取验证码
   - 输入验证码
   - 验证登录成功

---

## 八、测试清单

### 8.1 功能测试

- [ ] Apple Sign In 登录成功
- [ ] Google Sign In 登录成功
- [ ] GitHub OAuth 登录成功
- [ ] 邮箱验证码发送成功
- [ ] 邮箱验证码登录成功
- [ ] Token 自动刷新成功
- [ ] 退出登录成功
- [ ] 应用重启后保持登录状态

### 8.2 错误处理测试

- [ ] 网络错误提示正确
- [ ] 认证失败提示正确
- [ ] Token 过期自动刷新
- [ ] Refresh Token 过期提示重新登录
- [ ] 第三方登录取消处理正确

### 8.3 UI/UX 测试

- [ ] 登录页面布局正确
- [ ] 加载状态显示正确
- [ ] 错误提示显示正确
- [ ] 登录成功后跳转正确
- [ ] 退出登录后返回登录页

---

## 九、常见问题

### Q1: Apple Sign In 无法使用？

**可能原因**:
- 未在 Apple Developer Portal 中启用 "Sign In with Apple" 能力
- Bundle Identifier 不匹配
- 未添加 AuthenticationServices 框架

**解决方案**:
1. 在 Apple Developer Portal 中启用 "Sign In with Apple" 能力
2. 确保 Bundle Identifier 与 Apple Developer Portal 中配置的一致
3. 在 Xcode 中添加 AuthenticationServices 框架

### Q2: Google Sign In 无法使用？

**可能原因**:
- GoogleSignIn 框架未安装
- GIDClientID 未配置
- Google Cloud Console 中未启用 Google Sign-In API

**解决方案**:
1. 通过 Swift Package Manager 安装 GoogleSignIn 框架
2. 在 Info.plist 中配置 GIDClientID
3. 在 Google Cloud Console 中启用 Google Sign-In API

### Q3: GitHub OAuth 回调失败？

**可能原因**:
- URL Scheme 未配置
- GitHub OAuth 配置中的回调 URL 不正确
- GitHubClientID 或 GitHubClientSecret 配置错误

**解决方案**:
1. 在 Xcode 中添加 `mindcanvas` URL Scheme
2. 确保 GitHub OAuth 配置中的回调 URL 为 `mindcanvas://auth`
3. 检查 GitHubClientID 和 GitHubClientSecret 是否正确

### Q4: 后端服务无法连接？

**可能原因**:
- 后端服务未启动
- 端口被占用
- 网络连接问题

**解决方案**:
1. 启动后端服务: `docker-compose up -d`
2. 检查端口是否被占用: `lsof -i :8000`
3. 检查网络连接: `ping localhost`

### Q5: Token 刷新失败？

**可能原因**:
- Refresh Token 过期
- 网络连接问题
- 后端服务异常

**解决方案**:
1. 检查 Refresh Token 是否过期（30天有效期）
2. 检查网络连接
3. 检查后端服务日志

---

## 十、后续步骤

1. **配置第三方 OAuth 凭证**:
   - [ ] 获取 Google Client ID
   - [ ] 获取 GitHub Client ID 和 Secret
   - [ ] 配置到 Info.plist

2. **测试登录功能**:
   - [ ] 测试 Apple Sign In
   - [ ] 测试 Google Sign In
   - [ ] 测试 GitHub OAuth
   - [ ] 测试邮箱验证码登录

3. **集成真实后端**:
   - [ ] 确保后端服务正常运行
   - [ ] 测试所有 API 接口
   - [ ] 验证 Token 刷新机制

4. **提交代码**:
   - [ ] 更新 CHANGELOG.md
   - [ ] 提交代码到版本控制
   - [ ] 创建 Pull Request

---

## 十一、相关文档

- [iOS 登录功能后端适配改造方案](./ios_login_backend_integration_plan.md)
- [iOS 第三方登录最佳实践](./ios_third_party_login_best_practices.md)
- [后端架构设计](../backend/backend_architecture.md)
- [CHANGELOG.md](../../../../CHANGELOG.md)

---

**文档维护**: iFlow CLI
**最后更新**: 2026-01-01