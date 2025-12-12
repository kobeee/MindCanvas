# 编辑器全屏与横屏适配修复方案 v1.0

## 1. 问题背景

### 1.1 现象描述
- **界面挤压**：在 iPhone 和 iPad 上，编辑器界面呈现“揉成一团”的状态。
- **布局冲突**：
    - 编辑器采用固定的三栏布局：`[资源库 300pt] + [画布 自适应] + [控制面板 320pt]` = 固定占用 **620pt**。
    - **iPhone 竖屏**：屏幕宽度仅 ~400pt，根本无法容纳 620pt 的固定面板，导致重叠。
    - **iPad**：由于使用 `NavigationLink` 进入，左侧的 App 主导航栏（Sidebar）依然保留，占据了宝贵的屏幕宽度，导致画布区域被极度压缩。
- **交互痛点**：用户期望“点击项目 -> 进入独立工作室”，而当前体验是“在 App 列表里看画布”，且为了全屏还需要手动收起左侧栏，操作繁琐且不符合直觉。

### 1.2 根本原因
1.  **导航架构错误**：编辑器被视为导航层级中的“详情页”（Detail View），受限于 `NavigationSplitView` 的布局约束。
2.  **屏幕方向未强制**：专业创作工具（如 Procreate）通常强制横屏以保证工作区，当前应用未做限制。
3.  **Size Class 误区**：过度依赖系统的响应式布局逻辑，反而破坏了专业工具所需的固定面板体验。

---

## 2. 核心设计理念

**“大厅 (Lobby) 与 工作室 (Studio) 分离”**

- **大厅**（项目列表、设置）：保持竖屏，使用标准 iOS 导航。
- **工作室**（编辑器）：**独立全屏模态**，**强制横屏**，独占所有屏幕像素。

---

## 3. 详细修复方案

### 3.1 导航架构重构：从 Push 改为 FullScreenCover

**目标**：彻底切断编辑器与主 App 导航栏（Sidebar）的视觉联系。

-   **当前逻辑**：
    ```swift
    NavigationLink(destination: NativeEditorView(...)) { ... }
    ```
    *缺点：保留导航堆栈，保留左侧 Sidebar，导致空间不足。*

-   **目标逻辑**：
    ```swift
    .fullScreenCover(item: $selectedProject) { project in
        NativeEditorView(project: project)
    }
    ```
    *优点：创建一个全新的 Window 级别的视图上下文，覆盖整个屏幕，Sidebar 物理消失。*

### 3.2 屏幕方向强制：强制横屏 (Forced Landscape)

**目标**：无论在 iPhone 还是 iPad 上，进入编辑器即强制旋转至横屏，退出时恢复。

-   **实现策略**：
    1.  **进入 (`onAppear`)**：调用 `AppDelegate` 或 `UIDevice` 接口强制设为横屏，并锁定只允许横屏。
    2.  **退出 (`onDisappear`)**：解除方向锁定，允许自动旋转或强制回竖屏。
    3.  **适配 iPhone**：iPhone 用户进入编辑器时，手机会自动旋转 90 度，利用长边（iPhone 15 Pro Max 约 850pt+ 安全宽度）来容纳界面。

### 3.3 布局策略：回归硬编码三栏 (Hardcoded 3-Column)

**目标**：在确保横屏宽度的前提下，坚持使用左右固定、中间自适应的经典布局。

-   **布局计算验证**：
    -   **固定开销**：左栏 300pt + 右栏 320pt = **620pt**。
    -   **iPhone 15 Pro Max (横屏)**：
        -   安全区域宽度：约 **850pt**。
        -   画布剩余空间：850 - 620 = **230pt**。
        -   *结论*：可行。虽然画布不算巨大，但作为移动端微调工具，中间有独立可视区域，不再重叠。
    -   **iPad Air/Pro (横屏)**：
        -   屏幕宽度：1180pt ~ 1366pt。
        -   画布剩余空间：> 500pt。
        -   *结论*：完美。

-   **代码回滚**：
    -   移除之前添加的 `compactLayout` / `regularLayout` 响应式判断。
    -   移除 iPhone 上的顶部 Toolbar 切换按钮。
    -   恢复最简单的 `HStack` 结构。

---

## 4. 执行步骤 (Step-by-Step)

### 步骤 1：修改 ProjectListView (入口)
- [ ] 移除 `NavigationLink`。
- [ ] 添加 `@State private var selectedProject: Project?`。
- [ ] 使用 `.fullScreenCover(item: $selectedProject)` 呈现编辑器。

### 步骤 2：实现方向锁定工具 (Orientation Manager)
- [ ] 在 `MindCanvasApp` 或 `AppDelegate` 中添加方向控制支持（SwiftUI 需要配合 `AppDelegate` 才能完美控制）。
- [ ] 创建 `OrientationManager` 单例，提供 `lockLandscape()` 和 `unlock()` 方法。

### 步骤 3：修改 NativeEditorView (编辑器)
- [ ] **清理**：删除 `horizontalSizeClass` 判断，删除 Sheet 模式的资源库/控制面板。
- [ ] **恢复**：恢复 `HStack { AssetLibrary(300); Canvas; ControlPanel(320) }` 布局。
- [ ] **生命周期**：
    - `.onAppear { OrientationManager.lockLandscape() }`
    - `.onDisappear { OrientationManager.unlock() }`
- [ ] **导航栏**：由于是模态视图，需要自定义左上角的“关闭/返回”按钮（调用 `dismiss`）。

---

## 5. 预期效果

1.  **iPhone**：点击项目 -> 界面自动横屏 -> 左右两侧工具栏固定显示，中间显示画布 -> 点击返回 -> 界面转回竖屏 -> 回到列表。
2.  **iPad**：点击项目 -> 界面覆盖全屏（左侧 App 导航栏消失） -> 沉浸式三栏创作界面 -> 点击返回 -> 恢复 App 导航界面。
3.  **解决痛点**：彻底解决“揉成一团”的 UI bug，同时满足“硬编码三栏”的设计执念。

