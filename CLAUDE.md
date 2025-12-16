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
- **UI**: SwiftUI + UIKit (MVVM 架构)
- **绘图**: PencilKit (PKCanvasView)
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
Models/          # 数据模型
  └── Canvas/    # 画布相关模型
      ├── CanvasTool.swift       # 工具枚举 (select/pan/pen/eraser/arrow/rectangle)
      ├── ShapeType.swift        # 形状类型 (rectangle/circle/triangle/line/arrow等)
      ├── ArrowLayerNode.swift   # 箭头/直线数据模型 (hasArrowHead区分)
      ├── ShapeLayerNode.swift   # 形状数据模型
      └── CanvasAction.swift     # 撤销/恢复操作 (Command Pattern)
ViewModels/      # 视图模型 (@Observable + @MainActor)
  ├── CanvasStateManager.swift   # 画布状态 (工具、缩放、撤销栈)
  └── NativeEditorViewModel.swift # 编辑器业务逻辑
Views/           # 视图层
  ├── Auth/      # 登录认证
  ├── Editor/    # 核心编辑器
  │   ├── Canvas/  # 原生画布组件
  │   │   ├── NativeCanvasView.swift      # PKCanvasView封装 (UIKit)
  │   │   ├── SelectableArrowView.swift   # 箭头/直线视图 (端点控制点)
  │   │   ├── SelectableShapeView.swift   # 形状视图 (角点+旋转控制点)
  │   │   ├── CanvasToolbar.swift         # 底部工具栏
  │   │   └── ShapePickerPopover.swift    # 形状选择弹窗
  │   └── NativeEditorView.swift  # 主编辑器 (三栏布局)
  ├── Feed/      # 社区流 (MindStream)
  └── ...
Services/        # Mock 服务层
Managers/        # 管理器 (AuthManager)
Infrastructure/  # 基础设施 (Keychain, Theme)
Extensions/      # Swift 扩展
```

### 核心模块

**NativeEditorView**: 主编辑器视图，全屏三栏布局 (资源库300pt + 画布 + 控制面板320pt)
**NativeEditorViewModel**: 编辑器状态管理，处理 AI 生成流程 (文生图/图生图)
**CanvasStateManager**: 画布状态管理 (工具切换、缩放、撤销/重做栈)
**NativeCanvasView**: 原生画布实现，直接使用 PKCanvasView 内置缩放功能

### 画布架构 (重要)

```
NativeCanvasView (UIView)
├── pencilCanvas (PKCanvasView)    <- 直接作为根滚动容器，5000x5000画布
│   └── objectLayerView (UIView)   <- 对象层 (箭头/形状)
└── overlayContainerView (UIView)  <- 覆盖层容器 (与pencilCanvas同步滚动)
```

**关键设计决策**:
- PKCanvasView 本身继承自 UIScrollView，直接使用其内置缩放功能
- 不嵌套额外的 UIScrollView，避免坐标转换错误 (Apple FB15166022)
- objectLayerView 作为 PKCanvasView 子视图，随画布滚动缩放
- 形状/箭头使用控制点交互 (Figma风格)，移除双指手势依赖

### 工具系统

当前实现的工具 (CanvasTool):
- **select**: 选择工具，可选中/移动/缩放/旋转对象
- **pan**: 平移工具，拖动画布
- **pen**: 画笔工具，PencilKit 绘图
- **eraser**: 橡皮擦，擦除笔画
- **arrow**: 箭头/直线工具，通过 ShapeType 选择具体类型
- **rectangle**: 形状工具，支持9种形状 (矩形/圆形/三角形/菱形等)
- **image**: 图片工具，从相册选择或拍照

形状选择器支持的类型 (ShapeType):
- 线条类: line (直线), arrow (箭头)
- 基础形状: rectangle, circle, triangle, diamond, star, hexagon, roundedRectangle

### 撤销/恢复系统

采用 Command Pattern，每个操作封装为 CanvasAction:
- undoStack / redoStack 维护在 CanvasStateManager
- 支持: 绘图、添加/删除/移动图层、形状操作等
- PKCanvasView 重建机制解决笔画复活问题

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

### PencilKit 开发注意事项
- PKCanvasView 继承自 UIScrollView，不要再嵌套 UIScrollView
- 撤销绘图时需重建 PKCanvasView 实例，清除内部缓存状态
- 绘图模式下冻结 scrollView 的 pan/pinch/scroll，避免坐标漂移
- `canvasViewDidEndUsingTool` 调用时 drawing 数据可能未更新完成，需延迟处理

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
- **除非明确要求整合CHANGELOG的内容，否则不允许以修改的方式覆盖CHANGELOG，CHANGELOG就是要记录过程的**
- 结构脉络清晰，区分模块功能，记录上下文背景和思考过程

### Mermaid 图表规则
- 所有包含中文/空格/标点的文本必须用双引号包裹: `A["节点文本"]`
- `end` 关键字必须独占一行
- 跨子图连接必须在 `subgraph ... end` 块外部定义
- 顶层 `graph` 不需要 `end` 结尾
- 避免在节点文本中使用反引号、HTML 标签、列表语法

---

## 关键文件

### 核心入口
- 主入口: [MindCanvasApp.swift](src/MindCanvas/MindCanvas/MindCanvasApp.swift)
- 编辑器视图: [NativeEditorView.swift](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift)
- 编辑器 VM: [NativeEditorViewModel.swift](src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift)

### 画布系统
- 画布状态: [CanvasStateManager.swift](src/MindCanvas/MindCanvas/ViewModels/CanvasStateManager.swift)
- 原生画布: [NativeCanvasView.swift](src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift)
- 箭头视图: [SelectableArrowView.swift](src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableArrowView.swift)
- 形状视图: [SelectableShapeView.swift](src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift)

### 数据模型
- 工具枚举: [CanvasTool.swift](src/MindCanvas/MindCanvas/Models/Canvas/CanvasTool.swift)
- 形状类型: [ShapeType.swift](src/MindCanvas/MindCanvas/Models/Canvas/ShapeType.swift)
- 箭头节点: [ArrowLayerNode.swift](src/MindCanvas/MindCanvas/Models/Canvas/ArrowLayerNode.swift)
- 撤销操作: [CanvasAction.swift](src/MindCanvas/MindCanvas/Models/Canvas/CanvasAction.swift)

### 设计文档
- 画布工具栏重构: [canvas_toolbar_redesign_v1.0.md](docs/design/ui/canvas_toolbar_redesign_v1.0.md)
- 形状工具修复v4: [shape_tool_critical_fixes_v4.md](docs/design/fix/shape_tool_critical_fixes_v4.md)
