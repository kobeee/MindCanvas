# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

MindCanvas 是一个基于 AI 的创意绘图应用，专为 iPad 设计。用户可通过画布操作和文字描述来创作艺术作品。当前专注于 iOS 客户端开发，后端待开发。

## 构建和运行

```bash
# 打开 iOS 项目
cd src/MindCanvas
open MindCanvas.xcodeproj

# 在 Xcode 中选择 iPad 模拟器或真机，按 Cmd+R 运行
```

**环境要求**: macOS 14.0+, Xcode 15.0+, iPadOS 17.0+

**Mock 模式**: 当前版本无需后端，所有接口使用 Mock 数据。邮箱验证码固定为 `123456`。

## 技术架构

### iOS 客户端
- **语言**: Swift 5.9+
- **UI**: SwiftUI (MVVM 架构)
- **数据**: SwiftData
- **最低版本**: iPadOS 17.0+

### 后端 (待开发)
- **语言**: Python 3.11
- **框架**: FastAPI + Uvicorn
- **数据库**: PostgreSQL
- **缓存**: Redis
- **容器化**: Docker

### 代码结构 (src/MindCanvas/MindCanvas/)
```
Models/          # 数据模型 (User, Project, Asset, Canvas相关)
ViewModels/      # 视图模型 (@Observable + @MainActor)
Views/           # 视图层
  ├── Auth/      # 登录认证
  ├── Editor/    # 核心编辑器 (三栏式: 资源库+画布+控制面板)
  │   └── Canvas/  # 原生画布组件
  ├── Feed/      # 社区流 (MindStream)
  └── ...
Services/        # Mock 服务层
Managers/        # 管理器 (AuthManager)
Infrastructure/  # 基础设施 (Keychain, Theme)
Extensions/      # Swift 扩展
```

### 核心模块

**NativeEditorView**: 主编辑器视图，集成原生画布、工具栏和控制面板
**NativeEditorViewModel**: 编辑器状态管理，处理 AI 生成流程
**CanvasStateManager**: 画布状态管理 (工具、缩放、撤销/重做)
**NativeCanvasView**: 原生画布实现，支持图层、绘图、箭头、矩形、文字、标注

---

## 核心开发原则

### 研发流程
接需求 -> 写PRD -> 需求分析 -> 系统设计和分析 -> 测试设计和分析 -> 研发 -> 测试

**先设计后开发**: 不要着急写代码，设计应包含测试用例。先完成测试代码，如果无法完成说明需求理解不透彻。

### 通用原则
- **可测试性**: 组件保持单一职责
- **DRY**: 避免重复代码，提取共用逻辑
- **KISS**: 保持代码简洁明了
- **命名规范**: 使用描述性名称，反映用途和含义
- **利用生态**: 优先使用成熟的库和工具
- **代码行数**: 文件/函数过长时应重构拆分

### 重构原则
1. 抽象基类的方法签名必须严格匹配，重构时不可随意更改接口契约
2. 调用方的参数传递必须与接口定义保持一致
3. 大幅重构分步进行，每步集成测试
4. 重构后必须进行端到端集成测试

---

## 重要约定

- **不自动提交**: 禁止 git push 或 git commit，需用户明确同意
- **禁止代码图标**: 不在代码和注释里使用 emoji 图标，只用文字
- **不追求完美**: 务实推进，有疑问就问
- **省 token**: 不啰嗦、读代码跳注释、非必要不读 `docs/archive/`
- **代码有效**: 不添加调试用的无效日志，调试完后主动清除
- **响应语言**: 始终使用中文回复

---

## SwiftUI 开发规范

### 视图设计
- 必须使用 `struct` 创建 View，保持小巧和专注
- 如果 `body` 超过 50 行，强制拆分为独立子视图组件
- **禁止**使用计算属性 (`var someView: some View`) 来拆分复杂 UI
- 为每个视图编写 `#Preview` 块，提供 Mock 数据

### 状态管理
```swift
// iOS 17+ 必须使用 @Observable 替代 ObservableObject
@Observable
@MainActor
final class SomeViewModel {
    var state = ""
}

// 本地状态
@State private var localState = ""

// 双向绑定
@Binding var boundState: String

// 依赖注入
@Environment(\.dismiss) private var dismiss
@EnvironmentObject var authManager: AuthManager
```

### 样式与布局
- 创建自定义 `ViewModifier` 封装重复样式，扩展 `View` 接口以便点语法调用
- 处理长列表时**必须**使用 `LazyVStack` 或 `LazyHStack`
- 将复杂业务逻辑从 View 中提取到 ViewModel

### 禁止事项
- **禁止**在 View 的 `body` 内部写复杂的 `if-else` 逻辑计算
- **禁止**在 `List` 内部随意使用 `GeometryReader`
- **禁止**使用单例强耦合业务逻辑，应使用依赖注入

---

## Swift 语法规范

### 绝对禁区
- **严禁**强制解包 `!`（除 IBOutlet 和极少数确定性场景如 `URL(string: "static")!`）
- **严禁** `NS` 前缀类型，使用 `String`、`Array`、`Dictionary`
- **严禁** `try!`，使用 `do-catch` 或 `try?`
- **慎用** `unowned`，闭包捕获列表中一律使用 `[weak self]`

### 流程控制
- **卫语句优先**: `guard let user = user else { return }`，拒绝"金字塔式"嵌套
- **Switch 穷举**: 尽量避免使用 `default`，强制穷举所有 case
- **Defer 清理**: 进行文件/锁/资源操作时，紧接着使用 `defer { ... }` 确保释放

### 函数式与集合
- 优先使用 `.map`, `.filter`, `.reduce`, `.compactMap`
- 使用 KeyPath 语法: `users.map(\.name)` 而非 `users.map { $0.name }`
- 使用 `.isEmpty` 检查集合，**永远不要**使用 `.count == 0`

### 属性与访问控制
- 所有属性默认标记为 `private` 或 `private(set)`
- 衍生数据使用只读计算属性，不要用函数
- 昂贵的初始化操作必须使用 `lazy var`

### 并发
- 所有 UI 相关的类和操作必须标记为 `@MainActor`
- 使用 `async/await`、`Actor` 和 `Task`
- 严禁使用 GCD (`DispatchQueue`) 或 Completion Handlers

### Extension 分组
- Struct/Class 定义保持干净，只保留存储属性和 Init
- 所有协议遵循 (`Conformance`) 必须放入单独的 `extension` 中

---

## FastAPI 后端规范 (待开发)

- 为所有函数参数和返回值使用类型提示
- 使用 Pydantic 模型进行请求和响应验证
- 使用适当的 HTTP 方法和状态码
- 使用依赖注入实现共享逻辑
- 使用 APIRouter 按功能或资源组织路由

---

## 文档规范

### 目录结构
- `docs/prd/`: 需求 PRD 文档
- `docs/design/`: 设计文档 (Plan 模式产出的方案保存于此)
- `docs/tests/validation/`: 验证步骤文档
- `docs/archive/`: 归档文档 (**非必要不读取**)

### 开发记录
- 使用 `CHANGELOG.md` 记录开发内容
- **每次以换行追加到文件头部**（最新记录在最上面）
- 结构脉络清晰，区分模块功能，记录上下文背景和思考过程

### Mermaid 图表规则
- 所有包含中文/空格/标点的文本必须用双引号包裹: `A["节点文本"]`
- `end` 关键字必须独占一行
- 跨子图连接必须在 `subgraph ... end` 块外部定义
- 顶层 `graph` 不需要 `end` 结尾
- 避免在节点文本中使用反引号、HTML 标签、列表语法

---

## 关键文件

- 主入口: [MindCanvasApp.swift](src/MindCanvas/MindCanvas/MindCanvasApp.swift)
- 编辑器视图: [NativeEditorView.swift](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift)
- 编辑器 VM: [NativeEditorViewModel.swift](src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift)
- 画布状态: [CanvasStateManager.swift](src/MindCanvas/MindCanvas/ViewModels/CanvasStateManager.swift)
- 原生画布: [NativeCanvasView.swift](src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift)
