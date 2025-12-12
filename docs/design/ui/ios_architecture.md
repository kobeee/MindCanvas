# MindCanvas iOS 客户端详细设计文档

## 1. 概述 (Overview)

本文档基于 MindCanvas v1.0 PRD，详细阐述 iOS 客户端的技术架构、模块设计及核心交互实现。App 旨在利用 iPad 的大屏优势，结合 SwiftUI 的现代 UI 能力与 WKWebView 的 Web 生态（tldraw），提供流畅的 AI 绘图体验。

### 1.1 技术栈选择
- **语言**: Swift 5+
- **UI 框架**: SwiftUI (生命周期、布局、状态管理)
- **Web 容器**: WKWebView (加载 tldraw 画布)
- **网络层**: Alamofire (RESTful API 请求)
- **图片加载**: Kingfisher (异步图片加载与缓存)
- **本地存储**: SwiftData (轻量级元数据缓存) + Keychain (敏感 Token)
- **最低版本**: iPadOS 17.0+

---

## 2. 总体架构 (Architecture)

采用 **MVVM (Model-View-ViewModel)** 架构模式，配合 **Repository Pattern** 进行数据层抽象。

### 2.1 架构分层
*   **View Layer (SwiftUI)**: 负责 UI 渲染、用户交互响应。通过 `@ObservedObject` 或 `@EnvironmentObject` 监听 ViewModel 状态。
*   **ViewModel Layer**: 负责业务逻辑处理、状态转换、桥接 Web 事件。
*   **Repository Layer**: 统一数据入口，决定是从 API 获取数据还是读取本地缓存。
*   **Service/Infrastructure Layer**: 网络请求、Keychain 访问、WebView 桥接管理。

---

## 3. 模块详细设计

### 3.1 导航与路由 (Navigation)
采用 iPad 标准的 `NavigationSplitView` 实现三栏/双栏布局。

*   **SidebarView**: 侧边栏菜单。
    *   枚举 `AppTab`: `.creations`, `.mindStream`, `.subscription`, `.settings`。
    *   状态: `@State private var selectedTab: AppTab? = .creations`。
*   **ContentDetailView**: 根据 `selectedTab` 渲染不同主视图。

### 3.2 身份认证模块 (Auth Module)
*   **AuthManager (Singleton)**:
    *   管理登录状态 (`isAuthenticated`: Bool)。
    *   处理 `Sign in with Apple` 委托回调。
    *   Token 管理: 登录成功后将 JWT 写入 Keychain，退出时清除。
*   **Views**:
    *   `LoginView`: 包含 Apple/Google/Github/Email 按钮的模态视图。
*   **Flow**:
    1.  App 启动检查 Keychain 是否有有效 Token。
    2.  无 Token -> 弹出/跳转 `LoginView`。
    3.  登录接口请求 -> 获取 JWT -> 存 Keychain -> 切换 Root View。

### 3.3 核心编辑器模块 (Editor Module) - *重难点*

编辑器由三个主要区域组成，通过 `EditorViewModel` 进行状态协调。

#### A. 画布容器 (CanvasContainer)
*   **组件**: `CanvasWebView` (UIViewRepresentable)。
*   **BridgeController**: 专门处理 Swift 与 JS 的双向通信。
    *   **Swift -> JS**:
        *   `insertImage(url: String, frame: CGRect?)`: 将左侧素材拖入/点击上屏。
        *   `exportCanvasSnapshot()`: 请求当前画布截图（用于生成时的参考图）。
    *   **JS -> Swift (`WKScriptMessageHandler`)**:
        *   `onSelectionChanged(hasSelection: Bool)`: 通知 Swift 更新 UI（如是否允许“填入选区”）。
        *   `onCanvasReady()`: 画布加载完成。
        *   `onExportData(base64: String)`: 返回画布截图数据。

#### B. 资源管理器 (Asset Library - Left Panel)
*   **AssetListViewModel**:
    *   维护 `assets: [AssetItem]` 数组。
    *   `AssetItem` 结构: `{ id, url, type (user_upload/ai_generated), createdAt }`。
*   **功能实现**:
    *   **导入**: 调用 `PHPickerViewController` 或 `UIImagePickerController` (相机)。图片上传至服务器后，将返回的 URL 加入列表。
    *   **拖拽 (Drag & Drop)**: 实现 `.itemProvider`，允许用户直接从左侧列表拖拽图片到中间的 WebView（需 Web 端配合 drop 事件，或通过位置坐标计算调用 JS 插入）。
    *   **上下文菜单**: 长按/点击触发 SwiftUI `.contextMenu` 或自定义浮层。
        *   *Add to Canvas*: 调用 `BridgeController.insertImage`。
        *   *Publish*: 仅当 `type == ai_generated` 时可用，弹窗输入 Title 后调用 API。

#### C. 控制面板 (Control Panel - Right Panel)
*   **ControlViewModel**:
    *   输入绑定: `@Published var prompt: String`。
    *   状态: `@Published var isGenerating: Bool`。
*   **生成流程**:
    1.  用户点击 Generate。
    2.  调用 `BridgeController.exportCanvasSnapshot()` 获取当前画面 Base64。
    3.  组合 Prompt + Base64 -> 调用 `GenerationService.generate()`.
    4.  左侧 Asset 列表插入一个 "Loading" 占位符。
    5.  收到后端返回 URL -> 替换 Loading 占位符 -> 自动刷新列表。

### 3.4 社区模块 (MindStream)
*   **UI**: `PinterestGrid` (瀑布流布局)。自定义 `Layout` 或使用 `LazyVGrid` (如果高度固定) / `HStack` of `VStack` (列布局)。
*   **数据**: 分页加载 (`loadMore`)。
*   **交互**:
    *   点击卡片 -> `ImageDetailView` (全屏预览 + 提示词查看)。
    *   **Remix 逻辑**:
        1.  点击 Remix。
        2.  下载原图。
        3.  新建 Project (本地或云端)。
        4.  跳转至编辑器，并自动将该图作为底层背景/参考图插入画布。
        5.  自动填充 Prompt 到输入框。

---

## 4. 数据模型设计 (Data Models)

```swift
struct User: Codable {
    let id: String
    let username: String
    let avatarUrl: String?
}

struct Asset: Identifiable, Codable {
    let id: UUID
    let url: String
    let thumbnailUrl: String
    let type: AssetType // .upload, .generated
    let prompt: String? // 仅生成的图片有
    let createdAt: Date
}

struct Project: Identifiable {
    let id: UUID
    var name: String
    var tldrawSnapshot: Data? // 画布状态的 JSON 快照
    var lastModified: Date
}
```

---

## 5. 关键交互细节与通信协议

### 5.1 WebView Bridge 协议
定义 `window.webkit.messageHandlers.mindCanvas` 接收的消息格式：

```json
// JS 发送给 Swift 的消息体
{
  "event": "selection_change",
  "payload": {
    "hasSelection": true,
    "selectionCount": 1,
    "bounds": { "x": 100, "y": 100, "w": 200, "h": 200 }
  }
}
```

### 5.2 错误处理
*   **网络错误**: 全局 Toast 提示 / 顶部 Banner。
*   **生成失败**: 左侧列表 Loading 卡片变更为“失败重试”状态。
*   **鉴权失败**: 自动登出并跳转 Login 页。

---

## 6. 开发排期建议 (Phasing)
1.  **Phase 1**: 搭建框架，实现 Auth (UI Only) + WebView 加载本地 HTML。
2.  **Phase 2**: 打通 Swift 与 tldraw 的 Bridge (插入图片、截图)。
3.  **Phase 3**: 对接后端 API，实现图片上传、生成流 (Generate API)。
4.  **Phase 4**: 完善左侧资源库管理 (CoreData/SwiftData 缓存列表)。
5.  **Phase 5**: MindStream 社区及 Remix 功能。

