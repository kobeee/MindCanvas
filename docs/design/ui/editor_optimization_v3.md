# 编辑器架构重构方案 v3.0 (Native Layer Engine)

## 1. 核心决策：All in Native

鉴于对操作灵活性、绘图手感及交互体验的极致追求，我们决定**彻底放弃 Web/tldraw 方案**，转而采用 **iOS 纯原生技术栈 (SwiftUI + PencilKit + UIKit)** 构建核心编辑器。

### 核心优势
1.  **零延迟绘图**：PencilKit 提供系统级手写支持，120Hz 刷新率，完美压感与倾斜识别。
2.  **对象级操控**：所有元素（图片、生成图）均为独立对象，支持随时移动、缩放、层级调整（Z-Index）。
3.  **无缝 AI 交互**：无需 JS Bridge，直接处理原生位图数据，性能更佳。

---

## 2. 核心架构：三明治图层模型 (The Sandwich Architecture)

编辑器不再是一个扁平的画布，而是一个垂直堆叠的**图层栈 (ZStack)**。从下至上依次为：

### Layer 0: 无限背景容器 (Canvas Container)
*   **组件**：`UIScrollView` (双向滚动) + `UIView` (Content View)。
*   **职责**：提供画布的缩放（Zoom）和漫游（Pan）能力。
*   **特性**：内容尺寸动态调整（或预设超大尺寸，如 5000x5000）。

### Layer 1: 对象图层 (Object Layer)
*   **组件**：自定义 `ZStack` 或 `UIView` 容器。
*   **内容**：存放所有 **图片节点 (Image Nodes)**。
    *   用户导入的素材（贴纸、参考图）。
    *   AI 生成的结果图。
*   **特性**：
    *   每个节点是一个独立的 `ResizableImageView`。
    *   支持手势：拖拽 (Drag)、缩放 (Pinch)、旋转 (Rotate)。
    *   **遮挡控制**：严格遵循数组顺序渲染，支持“上移一层”、“下移一层”、“置底/置顶”。

### Layer 2: 绘图图层 (PencilKit Layer)
*   **组件**：`PKCanvasView`。
*   **属性**：`backgroundColor = .clear` (透明背景)。
*   **职责**：专门接收 Apple Pencil 的笔迹（线条、涂鸦、手写文字）。
*   **特性**：始终覆盖在图片层之上，确保笔迹永远画在图片上面（模拟在照片上写字的体验）。

### Layer 3: 交互与选框层 (Interaction Layer)
*   **组件**：SwiftUI Overlay。
*   **内容**：
    *   **Magic Frame (生成选框)**：蓝色的矩形框，决定 AI 生成的范围。
    *   **Selection Handles**：选中图片时的调整手柄。
*   **职责**：不参与绘图，只负责交互控制。

---

## 3. 关键交互机制 (Interaction Mechanics)

为了解决“手指拖图”与“笔尖绘图”的冲突，引入 **状态机 (State Machine)** 管理。

### 3.1 锁定与解锁机制 (Locking Mechanism)
这是解决触控冲突的核心：
*   **默认状态 (Unlocked)**：
    *   图片可以被手指自由拖拽、缩放。
    *   此时若用笔在图片上画，笔迹会画在 Layer 2 上，但视觉上感觉像是在图片上画。
*   **锁定状态 (Locked)**：
    *   用户选中图片 -> 点击“锁定”。
    *   图片**不再响应移动手势**（位置固定）。
    *   **用途**：当用户确定了构图（如把一张山脉图作为底图），锁定它，然后专注在上面进行描绘，防止误触移动背景。

### 3.2 工具模式区分 (Tool Modes)
*   **✋ 指尖/对象模式 (Object Mode)**：
    *   `PKCanvasView.isUserInteractionEnabled = false` (让出触控权)。
    *   手指完全用于操作 Layer 1 的图片（移动、缩放、框选）。
*   **✏️ 绘图模式 (Drawing Mode)**：
    *   `PKCanvasView.tool = PKInkingTool(...)`。
    *   **Finger vs Pencil**：开启 PencilKit 的 `drawingPolicy = .pencilOnly`。
        *   **Apple Pencil**：画线。
        *   **手指**：仅用于漫游画布（滚动/缩放），不画线，也不误触图片。

---

## 4. AI 生成工作流 (The Generation Loop)

### 步骤 1：框选 (Frame It)
用户拖动 Layer 3 的 **Magic Frame**，框住画布上的任意区域（可能包含：Layer 1 的两张拼贴图 + Layer 2 的手绘草图）。

### 步骤 2：快照 (Snapshot)
系统执行**图层合并截图**：
```swift
func captureFrame(rect: CGRect) -> UIImage {
    // 1. 创建渲染器
    let renderer = UIGraphicsImageRenderer(bounds: rect)
    return renderer.image { context in
        // 2. 依次渲染可见层
        objectLayer.drawHierarchy(in: rect, afterScreenUpdates: true) // 渲染图片
        pencilCanvas.drawHierarchy(in: rect, afterScreenUpdates: true) // 渲染笔迹
    }
}
```
*结果：一张包含所有视觉信息的扁平位图。*

### 步骤 3：生成 (Generate)
将快照发送给 Gemini/Backend，获取生成结果（URL 或 Base64）。

### 步骤 4：回填 (Stamping)
*   系统创建一个新的 `ImageNode`。
*   将其插入到 Layer 1 的**最顶层**。
*   位置对齐 Magic Frame 的位置。
*   用户如果不满意，可以：
    *   **撤销 (Undo)**：直接移除该对象。
    *   **调整**：降低透明度（作为垫底参考），或缩小放到角落。

---

## 5. 数据模型设计 (Data Model)

```swift
struct CanvasDocument: Codable {
    var id: UUID
    var layers: [LayerNode] // 遵循 Z-Index 顺序
    var drawingData: Data   // PKDrawing 的序列化数据 (Layer 2)
}

struct LayerNode: Identifiable, Codable {
    var id: UUID
    var type: NodeType // .userImage, .aiGenerated
    var url: String?   // 图片资源路径
    var frame: CGRect  // 位置与尺寸
    var rotation: Double
    var isLocked: Bool // 锁定状态
    var zIndex: Int    // 渲染顺序
}
```

---

## 6. 总结

本方案放弃了 Web 的跨平台便利性，换取了 **iOS 平台上的极致体验**。它通过严格的图层分层和状态管理，完美解决了“混合编辑”中的触控冲突痛点，且技术实现路径完全在原生 UI 框架的可控范围内。