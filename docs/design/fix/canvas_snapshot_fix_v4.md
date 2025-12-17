# 画布截图功能修复方案 v4.0

> 日期: 2025-12-18
> 状态: 设计完成，待开发
> 优先级: P0 紧急
> 前置文档: [img2img_confirm_sheet_v3.md](img2img_confirm_sheet_v3.md)

---

## 一、问题概述

### 1.1 现象描述

用户在画布上绘制内容（如蓝色竖线），使用 MagicFrame（选框）框住后点击"图生图"，弹窗预览显示**空白图片**（只有棋盘格背景），但图片尺寸 480x380 是有值的。

**截图证据分析**：
- 画布上有一条蓝色竖线被选框框住
- 弹窗标题"确认生成"正常显示
- 预览区域标签"选区预览"和尺寸显示正常
- **预览图内容为空白**（棋盘格背景 = 透明图片）
- 提示词区域显示正常
- 按钮区域正常可见

### 1.2 问题本质

截图函数 `captureViewportSnapshotSimple()` 返回了图片（尺寸有值），但图片内容为空。这意味着：
1. 截图流程正常执行
2. **截取的区域没有可见内容**
3. 坐标转换或视图层级存在问题

---

## 二、根因分析

### 2.1 四个并行分析维度的结论汇总

经过对以下四个维度的深入分析：

| 维度 | 分析内容 | 关键发现 |
|-----|---------|---------|
| 视图层级 | NativeCanvasView 的结构 | overlayContainerView.clipsToBounds = true 导致对象被裁剪 |
| 坐标转换 | contentRect(forViewportRect:) | MagicFrame 是 SwiftUI 坐标，与 UIKit 层级不在同一坐标系 |
| 历史变更 | CHANGELOG 和 git 历史 | 从四层架构重构为两层架构后破坏了坐标关系 |
| 最佳实践 | PencilKit 截图方式 | layer.render() 方式正确，但坐标系不匹配 |

### 2.2 根本原因：**MagicFrame 坐标系与截图目标不匹配**

#### 2.2.1 当前视图层级结构

```
NativeEditorView (SwiftUI)
└── NativeCanvasContainer (SwiftUI, GeometryReader)
    └── ZStack
        ├── NativeCanvasViewWrapper (UIViewRepresentable)
        │   └── NativeCanvasView (UIView)
        │       ├── pencilCanvas (PKCanvasView) ← 笔画在这里
        │       └── overlayContainerView (UIView)
        │           └── objectLayerView (UIView) ← 对象在这里
        │
        ├── ArrowDrawingView (SwiftUI) ← 绘制时的预览
        ├── ShapeDrawingGestureView (SwiftUI)
        ├── TextEditingView (SwiftUI)
        ├── ForEach (显示矩形/文字/标注)
        │
        └── MagicFrameView (SwiftUI) ← 选框在这里！
```

#### 2.2.2 坐标系统分析

| 元素 | 坐标系 | 说明 |
|-----|-------|------|
| **MagicFrame** | SwiftUI ZStack 坐标 | 相对于 GeometryReader 的 proxy.size |
| **pencilCanvas** | UIKit 坐标 | NativeCanvasView 内部，有 contentOffset/zoomScale |
| **objectLayerView** | UIKit 变换坐标 | 应用了 transform 和 frame.origin 偏移 |
| **overlayContainerView** | UIKit 坐标 | 与 NativeCanvasView 重叠，但有 clipsToBounds |

#### 2.2.3 核心问题

```swift
// NativeEditorViewModel.swift 第 220-225 行
let viewportRect = stateManager.magicFrame  // SwiftUI 坐标！
guard let snapshot = canvasView.captureViewportSnapshotSimple(rect: viewportRect)

// NativeCanvasView.swift 第 942-947 行
func captureViewportSnapshotSimple(rect viewportRect: CGRect) -> UIImage? {
    context.cgContext.translateBy(x: -viewportRect.origin.x, y: -viewportRect.origin.y)
    pencilCanvas.layer.render(in: context.cgContext)      // UIKit layer
    overlayContainerView.layer.render(in: context.cgContext)  // UIKit layer
}
```

**问题**：`viewportRect` 是 SwiftUI 坐标，但 `layer.render()` 期望的是 UIKit 坐标。两者**不在同一坐标系**！

### 2.3 具体问题点

#### 问题1：SwiftUI 与 UIKit 坐标系不一致

- MagicFrameView 在 SwiftUI 的 ZStack 中通过 `.position()` 定位
- SwiftUI 的 position 是相对于**父视图中心**，不是左上角
- 截图时直接使用 `magicFrame` 作为 UIKit 坐标，导致位置错误

#### 问题2：overlayContainerView.clipsToBounds = true

```swift
// NativeCanvasView.swift 第 169 行
overlayContainerView.clipsToBounds = true  // 问题！
```

- 当 objectLayerView 应用 transform 和负 origin 时，超出 overlayContainerView 边界的内容被裁剪
- `layer.render()` 只能渲染未被裁剪的内容

#### 问题3：layer.render() 的坐标原点问题

```swift
context.cgContext.translateBy(x: -viewportRect.origin.x, y: -viewportRect.origin.y)
pencilCanvas.layer.render(in: context.cgContext)
```

- `translateBy()` 设置了坐标原点偏移
- 但 `layer.render()` 渲染的是**整个 layer 的内容**，从 layer 的 bounds.origin 开始
- 如果 viewportRect.origin 与 layer 的实际可见区域不匹配，结果为空白

#### 问题4：PKCanvasView 的内容在 contentOffset 位置

```
pencilCanvas.layer 的可见区域 = [0, 0, bounds.width, bounds.height]
实际内容位置 = contentOffset 决定
```

- 当画布有滚动偏移时，`layer.render()` 渲染的是**视口可见区域**
- 但 `translateBy()` 使用的是 SwiftUI 坐标，两者不匹配

### 2.4 为什么"早期可以成功截图"

根据 CHANGELOG 和 git 历史分析：

**早期架构（可用）**：
```
NativeCanvasView
└── scrollView (UIScrollView)
    └── contentView (UIView) ← 截图目标
        ├── objectLayerView
        └── pencilCanvas
```
- 使用 `contentView.convert()` 进行标准 UIKit 坐标转换
- `contentView.layer.render()` 渲染完整内容

**当前架构（有问题）**：
```
NativeCanvasView
├── pencilCanvas (PKCanvasView) ← UIScrollView 子类
└── overlayContainerView
    └── objectLayerView
```
- 移除了 scrollView 和 contentView
- 直接使用 PKCanvasView 的内置缩放
- 但**坐标转换逻辑没有相应调整**

---

## 三、解决方案

### 3.1 方案概述

采用"**绕过复杂坐标转换，直接截取整个画布再裁剪**"的策略。

**核心思路**：
1. 截取 pencilCanvas 的完整可见区域
2. 截取 overlayContainerView 的完整可见区域
3. 合成两个图层
4. 根据 MagicFrame 的**相对位置**裁剪最终图片

### 3.2 实现方案

#### 方案 A：统一使用 UIKit 坐标（推荐）

**思路**：将 MagicFrame 的坐标转换为 NativeCanvasView 内部的 UIKit 坐标。

**步骤**：

1. **在 NativeCanvasView 中添加新方法，接受相对于自身的坐标**

```swift
/// 截取指定视口区域的快照（UIKit 坐标，相对于 NativeCanvasView）
func captureVisibleAreaSnapshot(viewportRect: CGRect) -> UIImage? {
    print("[Snapshot] ===== Begin captureVisibleAreaSnapshot =====")
    print("[Snapshot] viewportRect: \(viewportRect)")
    print("[Snapshot] bounds: \(bounds)")
    print("[Snapshot] pencilCanvas.contentOffset: \(pencilCanvas.contentOffset)")
    print("[Snapshot] pencilCanvas.zoomScale: \(pencilCanvas.zoomScale)")

    guard viewportRect.width >= 10, viewportRect.height >= 10 else {
        print("[Snapshot] Error: rect too small")
        return nil
    }

    // 确保视口区域在有效范围内
    let clippedRect = viewportRect.intersection(bounds)
    guard !clippedRect.isEmpty else {
        print("[Snapshot] Error: viewportRect outside bounds")
        return nil
    }

    let scale = UIScreen.main.scale
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false

    let renderer = UIGraphicsImageRenderer(size: clippedRect.size, format: format)

    let result = renderer.image { context in
        let ctx = context.cgContext

        // 方式1：直接渲染整个视图层级到指定区域
        // 先平移坐标系，使 clippedRect 的左上角对应图片的 (0,0)
        ctx.translateBy(x: -clippedRect.origin.x, y: -clippedRect.origin.y)

        // 渲染 self（整个 NativeCanvasView）到上下文
        // 这会自动包含 pencilCanvas 和 overlayContainerView
        self.layer.render(in: ctx)
    }

    print("[Snapshot] Result size: \(result.size)")
    print("[Snapshot] ===== End captureVisibleAreaSnapshot =====")
    return result
}
```

2. **在 SwiftUI 层将 MagicFrame 坐标转换为 UIKit 坐标**

```swift
// NativeEditorView.swift - NativeCanvasContainer 中添加
private func convertMagicFrameToUIKitCoordinates(
    magicFrame: CGRect,
    in geometryProxy: GeometryProxy
) -> CGRect {
    // MagicFrameView 使用 .position() 定位，这是相对于父视图中心
    // 但 magicFrame 存储的是 frame（左上角 + 尺寸）
    // SwiftUI 的坐标系和 UIKit 相同：左上角为原点
    // 因此可以直接使用（如果 MagicFrameView 的实现是正确的）
    return magicFrame
}
```

3. **修改截图调用链路**

```swift
// NativeEditorViewModel.swift
@discardableResult
func prepareImageToImageFlow() -> Bool {
    print("[ImageToImage] ===== Begin prepareImageToImageFlow =====")

    guard !isGenerating else { return false }

    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        flowHintMessage = "请输入生成描述"
        return false
    }

    guard let canvasView else {
        flowHintMessage = "画布尚未就绪"
        return false
    }

    guard stateManager.isMagicFrameVisible else {
        flowHintMessage = "请先显示选框并框选区域"
        return false
    }

    // 获取选框区域
    let viewportRect = stateManager.magicFrame
    print("[ImageToImage] magicFrame: \(viewportRect)")
    print("[ImageToImage] canvasView.bounds: \(canvasView.bounds)")

    // 使用新的截图方法
    guard let snapshot = canvasView.captureVisibleAreaSnapshot(viewportRect: viewportRect),
          let imageData = snapshot.pngData() else {
        flowHintMessage = "预览准备失败：截图失败"
        return false
    }

    print("[ImageToImage] Snapshot size: \(snapshot.size)")
    pendingImageToImagePreview = snapshot
    pendingImageToImageBase64 = imageData.base64EncodedString()
    flowHintMessage = nil

    print("[ImageToImage] ===== End prepareImageToImageFlow (success) =====")
    return true
}
```

#### 方案 B：截取整个可见区域再裁剪

**思路**：先截取整个 NativeCanvasView，再根据 MagicFrame 裁剪。

```swift
/// 截取整个可见区域，然后裁剪指定区域
func captureAndCropSnapshot(cropRect: CGRect) -> UIImage? {
    print("[Snapshot] ===== Begin captureAndCropSnapshot =====")
    print("[Snapshot] cropRect: \(cropRect)")

    // 第一步：截取整个可见区域
    let fullSize = bounds.size
    guard fullSize.width > 0, fullSize.height > 0 else {
        print("[Snapshot] Error: bounds is empty")
        return nil
    }

    let scale = UIScreen.main.scale
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false

    let renderer = UIGraphicsImageRenderer(size: fullSize, format: format)
    let fullImage = renderer.image { context in
        self.layer.render(in: context.cgContext)
    }

    print("[Snapshot] Full image size: \(fullImage.size)")

    // 第二步：裁剪指定区域
    let scaledCropRect = CGRect(
        x: cropRect.origin.x * scale,
        y: cropRect.origin.y * scale,
        width: cropRect.width * scale,
        height: cropRect.height * scale
    )

    guard let cgImage = fullImage.cgImage,
          let croppedCGImage = cgImage.cropping(to: scaledCropRect) else {
        print("[Snapshot] Error: Failed to crop image")
        return nil
    }

    let croppedImage = UIImage(cgImage: croppedCGImage, scale: scale, orientation: .up)
    print("[Snapshot] Cropped image size: \(croppedImage.size)")
    print("[Snapshot] ===== End captureAndCropSnapshot =====")

    return croppedImage
}
```

### 3.3 关键修复点

#### 修复1：移除 overlayContainerView.clipsToBounds

```swift
// NativeCanvasView.swift setupViews() 方法
// 修改前
overlayContainerView.clipsToBounds = true

// 修改后
overlayContainerView.clipsToBounds = false
```

**影响评估**：
- 可能导致对象层内容超出视图边界时可见
- 需要测试是否影响其他功能

**替代方案**：如果需要保持 clipsToBounds，则在截图时临时关闭：

```swift
func captureVisibleAreaSnapshot(viewportRect: CGRect) -> UIImage? {
    // 临时关闭裁剪
    let originalClipsToBounds = overlayContainerView.clipsToBounds
    overlayContainerView.clipsToBounds = false

    defer {
        overlayContainerView.clipsToBounds = originalClipsToBounds
    }

    // ... 截图逻辑
}
```

#### 修复2：使用 self.layer.render() 而非分层渲染

```swift
// 修改前（有问题）
pencilCanvas.layer.render(in: context.cgContext)
overlayContainerView.layer.render(in: context.cgContext)

// 修改后（推荐）
self.layer.render(in: context.cgContext)
```

**原因**：
- `self.layer.render()` 会自动递归渲染所有子视图
- 保证了层级顺序和变换的正确性
- 避免了分别渲染时的坐标不一致问题

#### 修复3：确保截图时视图已完成布局

```swift
func captureVisibleAreaSnapshot(viewportRect: CGRect) -> UIImage? {
    // 确保布局完成
    layoutIfNeeded()
    syncOverlayTransform()

    // ... 截图逻辑
}
```

---

## 四、实现步骤

### 第一步：添加新的截图方法 (P0)

**文件**：`NativeCanvasView.swift`

1. 添加 `captureVisibleAreaSnapshot(viewportRect:)` 方法
2. 添加 `captureAndCropSnapshot(cropRect:)` 方法（备用）
3. 添加详细的调试日志

### 第二步：修改截图调用 (P0)

**文件**：`NativeEditorViewModel.swift`

1. 修改 `prepareImageToImageFlow()` 使用新方法
2. 添加调试日志输出坐标信息

### 第三步：修复 clipsToBounds 问题 (P0)

**文件**：`NativeCanvasView.swift`

1. 将 `overlayContainerView.clipsToBounds` 改为 `false`
2. 或在截图时临时关闭

### 第四步：验证测试 (P0)

1. 在模拟器和真机上测试
2. 测试不同缩放级别下的截图
3. 测试画布有滚动偏移时的截图
4. 验证各种工具（画笔、形状、图片）的内容都能正确截取

---

## 五、修改文件清单

| 文件 | 修改类型 | 说明 |
|-----|---------|------|
| [NativeCanvasView.swift](../../../src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift) | 修改 | 添加新截图方法，修复 clipsToBounds |
| [NativeEditorViewModel.swift](../../../src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift) | 修改 | 使用新截图方法 |

---

## 六、代码实现

### 6.1 NativeCanvasView.swift 新增/修改

```swift
// MARK: - Snapshot Methods (修复版)

/// 截取指定视口区域的快照
/// - Parameter viewportRect: 视口坐标（相对于 NativeCanvasView）
/// - Returns: 截取的图片，失败返回 nil
func captureVisibleAreaSnapshot(viewportRect: CGRect) -> UIImage? {
    print("[Snapshot] ===== Begin captureVisibleAreaSnapshot =====")
    print("[Snapshot] Input viewportRect: \(viewportRect)")
    print("[Snapshot] NativeCanvasView bounds: \(bounds)")
    print("[Snapshot] pencilCanvas.bounds: \(pencilCanvas.bounds)")
    print("[Snapshot] pencilCanvas.contentOffset: \(pencilCanvas.contentOffset)")
    print("[Snapshot] pencilCanvas.zoomScale: \(pencilCanvas.zoomScale)")
    print("[Snapshot] objectLayerView.frame: \(objectLayerView.frame)")
    print("[Snapshot] objectLayerView.transform: \(objectLayerView.transform)")

    // 验证尺寸
    guard viewportRect.width >= 10, viewportRect.height >= 10 else {
        print("[Snapshot] Error: viewportRect too small (< 10pt)")
        return nil
    }

    // 确保区域在视图范围内
    let clippedRect = viewportRect.intersection(bounds)
    guard !clippedRect.isEmpty else {
        print("[Snapshot] Error: viewportRect does not intersect bounds")
        return nil
    }

    print("[Snapshot] Clipped rect: \(clippedRect)")

    // 确保布局完成
    layoutIfNeeded()
    syncOverlayTransform()

    // 临时关闭 clipsToBounds 以确保完整渲染
    let originalClipsToBounds = overlayContainerView.clipsToBounds
    overlayContainerView.clipsToBounds = false

    defer {
        overlayContainerView.clipsToBounds = originalClipsToBounds
    }

    // 配置渲染器
    let scale = UIScreen.main.scale
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false

    let renderer = UIGraphicsImageRenderer(size: clippedRect.size, format: format)

    let result = renderer.image { context in
        let ctx = context.cgContext

        // 平移坐标系：使 clippedRect 的左上角对应图片的 (0, 0)
        ctx.translateBy(x: -clippedRect.origin.x, y: -clippedRect.origin.y)

        // 渲染整个视图层级
        // 这会自动包含 pencilCanvas 和 overlayContainerView 及其所有子视图
        self.layer.render(in: ctx)
    }

    print("[Snapshot] Result image size: \(result.size)")
    print("[Snapshot] Result image scale: \(result.scale)")
    print("[Snapshot] ===== End captureVisibleAreaSnapshot (success) =====")

    return result
}

/// 备用方法：截取整个可见区域后裁剪
/// - Parameter cropRect: 裁剪区域（相对于 NativeCanvasView）
/// - Returns: 裁剪后的图片
func captureAndCropSnapshot(cropRect: CGRect) -> UIImage? {
    print("[Snapshot-Crop] ===== Begin =====")
    print("[Snapshot-Crop] cropRect: \(cropRect)")

    // 验证
    guard cropRect.width >= 10, cropRect.height >= 10 else {
        print("[Snapshot-Crop] Error: cropRect too small")
        return nil
    }

    let fullSize = bounds.size
    guard fullSize.width > 0, fullSize.height > 0 else {
        print("[Snapshot-Crop] Error: bounds is empty")
        return nil
    }

    // 确保布局完成
    layoutIfNeeded()
    syncOverlayTransform()

    // 临时关闭 clipsToBounds
    let originalClipsToBounds = overlayContainerView.clipsToBounds
    overlayContainerView.clipsToBounds = false
    defer { overlayContainerView.clipsToBounds = originalClipsToBounds }

    // 配置渲染器
    let scale = UIScreen.main.scale
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false

    // 第一步：截取整个可见区域
    let renderer = UIGraphicsImageRenderer(size: fullSize, format: format)
    let fullImage = renderer.image { context in
        self.layer.render(in: context.cgContext)
    }

    print("[Snapshot-Crop] Full image captured: \(fullImage.size)")

    // 第二步：裁剪
    // 注意：CGImage 使用像素坐标，需要乘以 scale
    let pixelCropRect = CGRect(
        x: cropRect.origin.x * scale,
        y: cropRect.origin.y * scale,
        width: cropRect.width * scale,
        height: cropRect.height * scale
    )

    guard let cgImage = fullImage.cgImage,
          let croppedCGImage = cgImage.cropping(to: pixelCropRect) else {
        print("[Snapshot-Crop] Error: Failed to crop")
        return nil
    }

    let croppedImage = UIImage(cgImage: croppedCGImage, scale: scale, orientation: .up)
    print("[Snapshot-Crop] Cropped image: \(croppedImage.size)")
    print("[Snapshot-Crop] ===== End =====")

    return croppedImage
}
```

### 6.2 setupViews() 修改

```swift
private func setupViews() {
    // ... 其他代码保持不变

    // 配置覆盖层容器视图
    overlayContainerView.backgroundColor = .clear
    overlayContainerView.isUserInteractionEnabled = true
    // 修改：关闭裁剪，确保对象层完整渲染
    overlayContainerView.clipsToBounds = false  // 从 true 改为 false

    // ... 其他代码保持不变
}
```

### 6.3 NativeEditorViewModel.swift 修改

```swift
/// 图生图：准备预览
@discardableResult
func prepareImageToImageFlow() -> Bool {
    print("[ImageToImage] ===== Begin prepareImageToImageFlow =====")

    guard !isGenerating else {
        print("[ImageToImage] Error: Already generating")
        return false
    }

    let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    print("[ImageToImage] prompt: \(trimmed.isEmpty ? "(empty)" : trimmed)")
    guard !trimmed.isEmpty else {
        flowHintMessage = "请输入生成描述"
        return false
    }

    guard let canvasView else {
        print("[ImageToImage] Error: canvasView is nil")
        flowHintMessage = "画布尚未就绪"
        return false
    }

    guard stateManager.isMagicFrameVisible else {
        print("[ImageToImage] Error: Magic Frame not visible")
        flowHintMessage = "请先显示选框并框选区域"
        return false
    }

    // 获取选框区域（SwiftUI 坐标，但 NativeCanvasContainer 的 ZStack 与 UIKit 坐标系一致）
    let viewportRect = stateManager.magicFrame
    print("[ImageToImage] magicFrame: \(viewportRect)")
    print("[ImageToImage] canvasView.bounds: \(canvasView.bounds)")

    // 使用新的截图方法
    guard let snapshot = canvasView.captureVisibleAreaSnapshot(viewportRect: viewportRect),
          let imageData = snapshot.pngData() else {
        print("[ImageToImage] Error: Failed to capture snapshot")
        pendingImageToImagePreview = nil
        pendingImageToImageBase64 = nil
        flowHintMessage = "预览准备失败：截图失败"
        return false
    }

    print("[ImageToImage] Snapshot captured successfully!")
    print("[ImageToImage] Snapshot size: \(snapshot.size)")
    pendingImageToImagePreview = snapshot
    pendingImageToImageBase64 = imageData.base64EncodedString()
    flowHintMessage = nil

    print("[ImageToImage] ===== End prepareImageToImageFlow (success) =====")
    return true
}
```

---

## 七、验收标准

### 7.1 功能验收

- [ ] 使用画笔工具绘制内容后，图生图预览正确显示画笔内容
- [ ] 使用箭头/直线工具绘制后，图生图预览正确显示
- [ ] 使用形状工具绘制后，图生图预览正确显示
- [ ] 导入图片后，图生图预览正确显示图片
- [ ] 缩放画布到 200% 后，图生图预览正确显示
- [ ] 滚动画布后，图生图预览正确显示选框内容
- [ ] 预览图尺寸与选框尺寸匹配

### 7.2 边界条件测试

- [ ] 选框框住空白区域，预览显示空白（白色）而非透明
- [ ] 选框部分超出画布边界，预览正确显示可见部分
- [ ] 选框非常小（接近 10pt）时，预览正常
- [ ] 选框非常大（接近全屏）时，预览正常

### 7.3 性能验收

- [ ] 截图操作耗时 < 500ms
- [ ] 截图不导致 UI 卡顿
- [ ] 内存占用无明显增加

---

## 八、风险评估

### 8.1 关闭 clipsToBounds 的影响

**风险**：对象层内容可能超出视图边界显示

**评估**：
- 由于 objectLayerView 使用 transform 和 frame.origin 进行变换
- 变换后的内容应该与 pencilCanvas 的可见区域对齐
- 正常情况下不会超出边界

**缓解措施**：
- 添加监控日志，观察是否有异常
- 如有问题，改为仅在截图时临时关闭 clipsToBounds

### 8.2 使用 self.layer.render() 的性能影响

**风险**：渲染整个视图层级可能比分层渲染慢

**评估**：
- NativeCanvasView 的视图层级不深
- 渲染区域通常较小（选框尺寸）
- 性能影响可忽略

**缓解措施**：
- 添加耗时日志
- 如有性能问题，可改用 `drawHierarchy(in:afterScreenUpdates:)`

---

## 九、调试指南

### 9.1 日志检查

运行图生图流程后，检查控制台输出：

```
[ImageToImage] ===== Begin prepareImageToImageFlow =====
[ImageToImage] magicFrame: (200.0, 150.0, 300.0, 250.0)
[ImageToImage] canvasView.bounds: (0.0, 0.0, 800.0, 600.0)
[Snapshot] ===== Begin captureVisibleAreaSnapshot =====
[Snapshot] Input viewportRect: (200.0, 150.0, 300.0, 250.0)
[Snapshot] NativeCanvasView bounds: (0.0, 0.0, 800.0, 600.0)
[Snapshot] pencilCanvas.bounds: (0.0, 0.0, 800.0, 600.0)
[Snapshot] pencilCanvas.contentOffset: (100.0, 50.0)
[Snapshot] pencilCanvas.zoomScale: 1.5
[Snapshot] objectLayerView.frame: (-100.0, -50.0, 7500.0, 7500.0)
[Snapshot] objectLayerView.transform: [1.5, 0, 0, 1.5, 0, 0]
[Snapshot] Clipped rect: (200.0, 150.0, 300.0, 250.0)
[Snapshot] Result image size: (300.0, 250.0)
[Snapshot] ===== End captureVisibleAreaSnapshot (success) =====
[ImageToImage] Snapshot size: (300.0, 250.0)
[ImageToImage] ===== End prepareImageToImageFlow (success) =====
```

### 9.2 常见问题排查

| 问题 | 可能原因 | 排查方法 |
|-----|---------|---------|
| 预览仍为空白 | clipsToBounds 未修改 | 检查 setupViews() 中的设置 |
| 预览位置偏移 | 坐标转换问题 | 对比 magicFrame 和 clippedRect |
| 预览缺少部分内容 | objectLayerView 变换问题 | 检查 syncOverlayTransform() 是否被调用 |
| 预览模糊 | scale 设置问题 | 检查 UIGraphicsImageRendererFormat 的 scale |

---

## 十、参考资料

- [Apple UIView.layer.render(in:)](https://developer.apple.com/documentation/uikit/uiview/1622585-layer)
- [Apple UIGraphicsImageRenderer](https://developer.apple.com/documentation/uikit/uigraphicsimagerenderer)
- [PencilKit Best Practices - WWDC 2019](https://developer.apple.com/videos/play/wwdc2019/221/)
