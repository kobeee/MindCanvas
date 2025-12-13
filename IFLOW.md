# MindCanvas 项目概览

MindCanvas 是一个基于 AI 的创意绘图应用，专为 iPad 设计，集成了 AI 图像生成能力，允许用户通过简单的画布操作和文字描述来创作独特的艺术作品。

## 项目类型

这是一个 **iOS 应用项目**，采用前后端分离架构，目前专注于 iOS 客户端的开发，使用 SwiftUI 构建现代化的用户界面。

## 技术栈

### iOS 客户端
- **语言**: Swift 5.9+
- **UI 框架**: SwiftUI
- **最低版本**: iPadOS 17.0+
- **数据存储**: SwiftData
- **网络**: URLSession (当前使用 Mock 服务)
- **画布**: WKWebView (内嵌简易画布，预留 tldraw 集成接口)

### 后端（待开发）
- **语言**: Python 3.11
- **框架**: FastAPI
- **数据库**: PostgreSQL
- **缓存**: Redis
- **部署**: Docker

## 项目结构

```
MindCanvas/
├── docs/                   # 文档
│   ├── prd/               # 产品需求文档
│   ├── design/            # 设计文档
│   └── archive/           # 归档文档
├── src/                   # 源代码
│   └── MindCanvas/        # iOS 项目
│       ├── Models/        # 数据模型
│       ├── ViewModels/    # 视图模型
│       ├── Views/         # 视图层
│       ├── Services/      # 服务层（Mock）
│       ├── Managers/      # 管理器
│       └── Infrastructure/ # 基础设施
└── tests/                 # 测试代码
```

## 核心功能模块

1. **身份认证**: 支持 Apple/Google/GitHub/邮箱多种登录方式
2. **项目管理**: 创建、编辑、管理多个绘图项目
3. **核心编辑器**: 三栏式编辑界面（资源库 + 画布 + 控制面板）
4. **AI 生成**: 基于提示词生成图像（当前使用 Mock）
5. **社区模块**: MindStream 灵感流，浏览和分享作品
6. **订阅系统**: Pro 会员展示和订阅计划
7. **设置中心**: 账号管理、配置和退出登录

## 构建和运行

### iOS 开发

1. **环境要求**:
   - macOS 14.0+
   - Xcode 15.0+
   - iPad 模拟器或真机

2. **打开项目**:
```bash
cd src/MindCanvas
open MindCanvas.xcodeproj
```

3. **运行**: 选择 iPad 目标设备并运行（⌘R）

### Mock 数据说明

当前版本使用完全本地化的 Mock 数据：
- 所有登录都会成功（邮箱验证码: `123456`）
- 图片生成使用 picsum.photos 随机图片
- 社区内容为随机生成
- 无需后端服务即可完整体验 UI 和交互

## 开发状态

### 已完成 ✅
- iOS 客户端基础架构
- 所有核心模块的 UI 和交互
- Mock 服务层（模拟后端接口）
- SwiftData 本地数据持久化
- WebView 画布基础功能

### 进行中 🚧
- 真实后端 API 集成
- tldraw 完整画布集成
- IAP 订阅功能

### 待开发 📋
- 后端服务器
- 真实 AI 模型集成
- 图片下载功能
- Remix 完整流程
- 性能优化

## 开发约定

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

### SwiftData 查询
```swift
@Query(sort: \Project.lastModified, order: .reverse) 
private var projects: [Project]
```

## 注意事项

1. **iPad Only**: 本应用专为 iPad 设计，使用 NavigationSplitView
2. **无后端依赖**: 当前版本完全独立运行，不需要后端服务
3. **Mock 延迟**: 所有 Mock 接口都添加了人工延迟以模拟真实网络环境
4. **审核合规**: 已预置举报、拉黑功能以符合 App Store 审核要求

## 开发规范与约定

### 核心开发原则
- **研发流程**：接需求->写PRD->需求分析->系统设计和分析->测试设计和分析->研发->测试
- **先设计后开发**：按照研发流程一步步推进，设计应包含测试用例
- **可测试性**：编写可测试的代码，组件应保持单一职责
- **DRY 原则**：避免重复代码，提取共用逻辑到单独的函数或类
- **代码简洁**：保持代码简洁明了，遵循 KISS 原则
- **命名规范**：使用描述性的变量、函数和类名，反映其用途和含义
- **风格一致**：遵循项目或语言的官方风格指南和代码约定

### 项目通用规范
- **省token**: 不啰嗦、不生成无用文档、读代码跳注释、非必要不读 docs/archive
- **不自动提交**: 禁止 git push 或 git commit，需要用户明确同意
- **不追求完美**: 谦虚务实，实践检验，有疑问就问
- **代码有效**: 不添加调试用的无效日志，调试完后主动清除
- **禁止在代码和注释里使用图标，只允许使用文字**

### SwiftUI 开发规范
- **视图即值**: 必须使用 `struct` 创建 View，保持视图小巧和专注
- **状态管理**: 
  - 本地状态使用 `@State` 并标记为 `private`
  - 双向绑定使用 `@Binding`
  - iOS 17+ 必须使用 `@Observable` 宏替代 `ObservableObject`
  - 依赖注入使用 `@Environment` 或 `@EnvironmentObject`
- **样式与布局**:
  - 创建自定义 `ViewModifier` 来封装重复的样式逻辑
  - 处理长列表时必须使用 `LazyVStack` 或 `LazyHStack`
  - 将复杂的业务逻辑从 View 中提取到 ViewModel
- **架构模式**: 默认使用 MVVM，View 负责渲染，ViewModel 负责状态流转
- **线程安全**: 所有 UI 相关的类和操作必须标记为 `@MainActor`

### Swift 语法最佳实践
- **绝对禁区**:
  - 严禁强制解包 (`!`)，除了 `IBOutlet` 和极少数确定性场景
  - 严禁 `NS` 前缀类型，使用 `String`、`Array`、`Dictionary`
  - 严禁 `try!`，使用 `do-catch` 或 `try?`
  - 慎用 `unowned`，在闭包捕获列表中一律使用 `[weak self]`
- **流程控制**:
  - 卫语句优先 (`guard let`)，拒绝"金字塔式"嵌套
  - Switch 穷举，尽量避免使用 `default`
  - 使用 `defer` 确保资源释放
- **函数式与集合**:
  - 优先使用 `.map`, `.filter`, `.reduce`, `.compactMap`
  - 使用 KeyPath 语法: `users.map(\.name)`
  - 使用 `.isEmpty` 检查集合，不要使用 `.count == 0`
- **属性与访问控制**:
  - 所有属性默认标记为 `private` 或 `private(set)`
  - 使用只读计算属性而不是函数
  - 对于昂贵的初始化操作必须使用 `lazy var`

### FastAPI 开发规范（后端）
- 为所有函数参数和返回值使用类型提示
- 使用 Pydantic 模型进行请求和响应验证
- 在路径操作装饰器中使用适当的 HTTP 方法
- 使用依赖注入实现共享逻辑
- 使用后台任务进行非阻塞操作
- 使用适当的状态码进行响应
- 使用 APIRouter 按功能或资源组织路由

### 文档规范
- 所有文档使用Markdown格式
- 使用简洁、清晰的语言，文档内容应保持最新
- 使用中文作为主要语言
- 开发记录使用 `CHANGELOG.md`，每次以换行追加到文件头部
- 在 Plan 模式下产出的方案需保存到 `docs/design/` 目录

## 重要文件路径

- **主应用入口**: `src/MindCanvas/MindCanvas/MindCanvasApp.swift`
- **认证管理器**: `src/MindCanvas/MindCanvas/Managers/AuthManager.swift`
- **编辑器视图模型**: `src/MindCanvas/MindCanvas/ViewModels/EditorViewModel.swift`
- **核心编辑器视图**: `src/MindCanvas/MindCanvas/Views/Editor/EditorView.swift`
- **产品需求文档**: `docs/prd/v1.0.md`
- **后端架构设计**: `docs/design/backend/backend_architecture.md`