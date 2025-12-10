# MindCanvas iOS 客户端

MindCanvas 是一个基于 AI 的创意绘图应用，专为 iPad 设计。用户可以使用画布工具和 AI 生成功能创作独特的艺术作品。

## 技术栈

- **语言**: Swift 5.9+
- **UI 框架**: SwiftUI
- **最低版本**: iPadOS 17.0+
- **数据存储**: SwiftData
- **网络**: URLSession (Mock 服务)
- **画布**: WKWebView (内嵌简易画布，预留 tldraw 集成接口)

## 项目结构

```
MindCanvas/
├── Models/              # 数据模型
│   ├── User.swift
│   ├── Project.swift
│   ├── Asset.swift
│   ├── FeedItem.swift
│   └── AppTab.swift
├── ViewModels/          # 视图模型
│   ├── EditorViewModel.swift
│   └── FeedViewModel.swift
├── Views/               # 视图层
│   ├── Auth/           # 登录认证
│   ├── Projects/       # 项目列表
│   ├── Editor/         # 核心编辑器
│   ├── Feed/           # 社区流
│   ├── Settings/       # 设置
│   ├── Subscription/   # 订阅
│   └── Navigation/     # 导航
├── Services/            # 服务层（Mock）
│   ├── MockAuthService.swift
│   ├── MockGenerationService.swift
│   └── MockFeedService.swift
├── Managers/            # 管理器
│   └── AuthManager.swift
└── Infrastructure/      # 基础设施
    └── KeychainManager.swift
```

## 核心功能

### 1. 身份认证
- Sign in with Apple（符合 App Store 审核要求）
- Google 登录
- GitHub 登录
- 邮箱验证码登录
- Token 存储在 Keychain

### 2. 项目管理
- 创建、编辑、删除项目
- SwiftData 本地持久化
- 项目列表展示

### 3. 核心编辑器
#### 左侧资源库
- 从相册导入图片
- 显示生成历史
- 图片操作：添加到画布、下载、发布、删除
- 区分用户上传和 AI 生成

#### 中间画布
- 基于 WKWebView 的简易画布
- 支持绘图、橡皮擦、框架工具
- Swift 与 JavaScript 双向通信
- 预留 tldraw 集成接口

#### 右侧控制面板
- API 配置展示
- 模型选择（锁定 Nano Banana Pro）
- Prompt 输入
- 生成触发

### 4. 社区模块（MindStream）
- 瀑布流展示用户作品
- 点赞功能
- Remix 功能（预留）
- 举报和拉黑（审核要求）

### 5. 订阅系统
- Pro 会员展示
- 功能对比
- 订阅计划选择
- 常见问题

### 6. 设置
- 账号信息展示
- API 配置（预留）
- 退出登录

## Mock 数据说明

**当前所有后端接口均使用 Mock 数据**，包括：

- 登录接口：模拟成功返回 token 和用户信息
- 图片生成：使用 picsum.photos 随机图片
- 社区流：随机生成 feed 数据
- 图片上传：模拟延迟后返回 URL

邮箱验证码固定为 `123456`。

## 构建和运行

1. 使用 Xcode 15+ 打开 `MindCanvas.xcodeproj`
2. 选择 iPad 模拟器或真机
3. 点击运行（⌘R）

## 开发说明

### WebView Bridge 通信

**Swift → JavaScript**:
```swift
webView.evaluateJavaScript("insertImage('url', x, y, w, h)")
```

**JavaScript → Swift**:
```javascript
window.webkit.messageHandlers.mindCanvas.postMessage({
    event: 'canvas_updated',
    data: base64Image
})
```

### 状态管理

使用 iOS 17+ 的 `@Observable` 宏替代传统的 `ObservableObject`：

```swift
@Observable
@MainActor
final class EditorViewModel {
    var prompt = ""
    var isGenerating = false
    // ...
}
```

### SwiftData 查询

```swift
@Query(sort: \Project.lastModified, order: .reverse) 
private var projects: [Project]
```

## 待完成功能

- [ ] 集成真实的 tldraw 库
- [ ] 实现拍照功能
- [ ] 实现 Remix 跳转逻辑
- [ ] 连接真实后端 API
- [ ] 完善错误处理和重试机制
- [ ] 添加图片下载到相册功能
- [ ] 实现 IAP 订阅逻辑
- [ ] 性能优化（图片缓存、列表滚动）

## 注意事项

1. **iPad Only**: 本应用专为 iPad 设计，使用 NavigationSplitView
2. **无后端依赖**: 当前版本完全独立运行，不需要后端服务
3. **Mock 延迟**: 所有 Mock 接口都添加了人工延迟以模拟真实网络环境
4. **审核合规**: 已预置举报、拉黑功能以符合 App Store 审核要求

## License

Copyright © 2025 MindCanvas. All rights reserved.

