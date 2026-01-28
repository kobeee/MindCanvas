# 图片添加到视口中心位置修复方案 v1.0

## 问题描述

### 现象
从资源栏点击添加图片到画布时，图片应该出现在当前屏幕可见区域的中心位置。但实际上：
- 画布拖动或缩放后，添加的图片位置不正确
- 图片被添加到了画布的右下角或其他非预期位置
- 用户需要拖动画布去寻找新添加的图片

### 期望行为
无论画布如何缩放或拖动，新添加的图片都应该出现在**屏幕可见区域的正中央**。

---

## 问题分析

### 1. 当前代码调用链

```
资源栏点击 "添加到画布"
    ↓
NativeEditorView.onAddToCanvas
    ↓
NativeEditorViewModel.addAssetToCanvas(asset)
    ↓
canvasView.contentRect(forViewportRect: viewportRect)  ← 问题所在
    ↓
计算 centerInContent
    ↓
创建 LayerNode 并添加到画布
```

### 2. 当前坐标转换逻辑

**文件**: `NativeCanvasView.swift:1666-1680`

```swift
func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
    let rectInCanvas = pencilCanvas.convert(viewportRect, from: self)

    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset

    let result = CGRect(
        x: (rectInCanvas.origin.x + offset.x) / scale,
        y: (rectInCanvas.origin.y + offset.y) / scale,
        width: rectInCanvas.width / scale,
        height: rectInCanvas.height / scale
    )

    return result
}
```

### 3. 问题根因分析

#### 问题 1: 坐标转换公式错误

当前公式：`contentCoord = (viewportCoord + offset) / scale`

这个公式存在**概念性错误**：

1. `pencilCanvas.convert(viewportRect, from: self)` 已经将视口坐标转换到了 PKCanvasView 的坐标系
2. 但 PKCanvasView 作为 UIScrollView，其坐标系已经包含了 contentOffset 的影响
3. 再次加上 `offset` 会导致**重复计算偏移量**

#### 问题 2: 视图层级理解错误

```
NativeCanvasView (UIView)
├── pencilCanvas (PKCanvasView/UIScrollView)  ← 滚动容器
│   └── (内部内容视图)                         ← 5000x5000 画布内容
└── overlayContainerView (UIView)
    └── objectLayerView (UIView)              ← 图片实际添加位置
```

关键点：
- `pencilCanvas` 是 UIScrollView，有自己的 `contentOffset` 和 `zoomScale`
- `objectLayerView` 通过 `syncOverlayTransform()` 与 `pencilCanvas` 同步
- 图片的 `frame` 是相对于 `objectLayerView` 的，而 `objectLayerView` 的坐标系是**画布内容坐标系**

#### 问题 3: convert 方法的误用

`pencilCanvas.convert(viewportRect, from: self)` 的行为：
- 将 `self`（NativeCanvasView）坐标系中的矩形转换到 `pencilCanvas` 坐标系
- 但 `pencilCanvas` 作为 UIScrollView，其坐标系是**视口坐标系**，不是内容坐标系
- 这个转换结果仍然是视口坐标，不是画布内容坐标

---

## 正确的坐标转换原理

### UIScrollView 坐标系统

```
┌─────────────────────────────────────────────────────────────┐
│                    Content (5000 x 5000)                     │
│                                                              │
│    ┌──────────────────────┐                                  │
│    │   Viewport (可见区域) │ ← contentOffset = (x, y)        │
│    │                      │                                  │
│    │    ┌────────┐        │                                  │
│    │    │ Center │        │ ← 我们要计算的位置               │
│    │    └────────┘        │                                  │
│    │                      │                                  │
│    └──────────────────────┘                                  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 正确的转换公式

**从视口坐标到内容坐标**：

```
contentX = (viewportX + contentOffset.x) / zoomScale
contentY = (viewportY + contentOffset.y) / zoomScale
```

**视口中心点在内容坐标系中的位置**：

```
centerX = (viewportWidth / 2 + contentOffset.x) / zoomScale
centerY = (viewportHeight / 2 + contentOffset.y) / zoomScale
```

### 关键洞察

当前代码的问题在于：
1. `pencilCanvas.convert(viewportRect, from: self)` 返回的是 PKCanvasView 坐标系中的矩形
2. 由于 `pencilCanvas` 和 `self` 的 frame 相同（都填满整个视图），这个转换实际上**没有改变坐标值**
3. 然后又加上了 `contentOffset`，导致偏移量被**错误地应用**

---

## 修复方案

### 方案 A: 简化坐标计算（推荐）

直接使用 UIScrollView 的标准公式，不使用 `convert` 方法：

```swift
/// 获取当前视口中心点在画布内容坐标系中的位置
func getViewportCenterInContent() -> CGPoint {
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset
    let viewportSize = pencilCanvas.bounds.size

    // 视口中心点在内容坐标系中的位置
    let centerX = (viewportSize.width / 2 + offset.x) / scale
    let centerY = (viewportSize.height / 2 + offset.y) / scale

    return CGPoint(x: centerX, y: centerY)
}
```

### 方案 B: 修复现有方法

修改 `contentRect(forViewportRect:)` 方法：

```swift
func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset

    // 直接计算：视口矩形在内容坐标系中的位置
    // 不使用 convert 方法，因为 pencilCanvas 和 self 的 frame 相同
    let result = CGRect(
        x: (viewportRect.origin.x + offset.x) / scale,
        y: (viewportRect.origin.y + offset.y) / scale,
        width: viewportRect.width / scale,
        height: viewportRect.height / scale
    )

    return result
}
```

**注意**：方案 B 的公式与当前代码相同，但移除了 `convert` 调用。如果当前代码仍然不工作，问题可能在其他地方。

### 方案 C: 使用 UIScrollView 内置方法

UIScrollView 没有直接提供"视口到内容坐标"的转换方法，但我们可以利用其属性：

```swift
func getVisibleContentRect() -> CGRect {
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset
    let viewportSize = pencilCanvas.bounds.size

    return CGRect(
        x: offset.x / scale,
        y: offset.y / scale,
        width: viewportSize.width / scale,
        height: viewportSize.height / scale
    )
}
```

---

## 深入调试

### 调试步骤 1: 验证坐标值

在 `addAssetToCanvas` 方法中添加详细日志：

```swift
func addAssetToCanvas(_ asset: Asset) {
    guard let canvasView = canvasView else { return }

    // 调试信息
    let scale = canvasView.zoomScale
    let offset = canvasView.pencilCanvas.contentOffset  // 需要暴露或通过方法获取
    let viewportSize = canvasView.bounds.size

    print("=== 坐标调试 ===")
    print("zoomScale: \(scale)")
    print("contentOffset: \(offset)")
    print("viewportSize: \(viewportSize)")

    // 手动计算期望的中心点
    let expectedCenterX = (viewportSize.width / 2 + offset.x) / scale
    let expectedCenterY = (viewportSize.height / 2 + offset.y) / scale
    print("期望中心点: (\(expectedCenterX), \(expectedCenterY))")

    // 使用现有方法计算
    let viewportRect = canvasView.bounds
    let contentRect = canvasView.contentRect(forViewportRect: viewportRect)
    let actualCenter = CGPoint(x: contentRect.midX, y: contentRect.midY)
    print("实际中心点: \(actualCenter)")

    // 比较差异
    print("差异: (\(actualCenter.x - expectedCenterX), \(actualCenter.y - expectedCenterY))")
    print("================")

    // ... 后续代码
}
```

### 调试步骤 2: 检查 convert 方法的影响

```swift
func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
    print("=== contentRect 调试 ===")
    print("输入 viewportRect: \(viewportRect)")

    let rectInCanvas = pencilCanvas.convert(viewportRect, from: self)
    print("convert 后: \(rectInCanvas)")
    print("差异: (\(rectInCanvas.origin.x - viewportRect.origin.x), \(rectInCanvas.origin.y - viewportRect.origin.y))")

    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset
    print("scale: \(scale), offset: \(offset)")

    // ... 后续计算
}
```

### 调试步骤 3: 验证视图层级

```swift
// 在 NativeCanvasView 中添加调试方法
func debugViewHierarchy() {
    print("=== 视图层级调试 ===")
    print("self.frame: \(frame)")
    print("self.bounds: \(bounds)")
    print("pencilCanvas.frame: \(pencilCanvas.frame)")
    print("pencilCanvas.bounds: \(pencilCanvas.bounds)")
    print("pencilCanvas.contentSize: \(pencilCanvas.contentSize)")
    print("pencilCanvas.contentOffset: \(pencilCanvas.contentOffset)")
    print("pencilCanvas.zoomScale: \(pencilCanvas.zoomScale)")
    print("overlayContainerView.frame: \(overlayContainerView.frame)")
    print("objectLayerView.frame: \(objectLayerView.frame)")
    print("objectLayerView.transform: \(objectLayerView.transform)")
    print("========================")
}
```

---

## 可能的其他问题

### 问题 1: syncOverlayTransform 的影响

```swift
private func syncOverlayTransform() {
    let offset = pencilCanvas.contentOffset
    let scale = pencilCanvas.zoomScale

    objectLayerView.transform = CGAffineTransform(scaleX: scale, y: scale)
    objectLayerView.frame.origin = CGPoint(x: -offset.x, y: -offset.y)
    // ...
}
```

这个方法将 `objectLayerView` 的变换与 `pencilCanvas` 同步。这意味着：
- `objectLayerView` 的坐标系是**画布内容坐标系**
- 图片的 `frame` 应该使用**画布内容坐标**

如果坐标计算正确，图片应该出现在正确的位置。

### 问题 2: 异步加载的时序问题

```swift
loadImageSize(from: asset.url) { [weak self] originalSize in
    // 这里的代码在异步回调中执行
    // 此时画布的状态可能已经改变
    let viewportRect = canvasView.bounds
    let contentRect = canvasView.contentRect(forViewportRect: viewportRect)
    // ...
}
```

如果用户在图片加载期间移动了画布，计算出的位置会是**新的位置**，而不是点击时的位置。

**解决方案**：在点击时立即捕获坐标：

```swift
func addAssetToCanvas(_ asset: Asset) {
    guard let canvasView = canvasView else { return }

    // 立即捕获当前视口中心点
    let centerInContent = canvasView.getViewportCenterInContent()

    loadImageSize(from: asset.url) { [weak self] originalSize in
        // 使用之前捕获的中心点
        let position = CGPoint(
            x: centerInContent.x - scaledSize.width / 2,
            y: centerInContent.y - scaledSize.height / 2
        )
        // ...
    }
}
```

### 问题 3: bounds vs frame

```swift
let viewportRect = canvasView.bounds  // 使用 bounds
```

`bounds` 是正确的选择，因为：
- `bounds` 是视图自身坐标系中的矩形，origin 通常是 (0, 0)
- `frame` 是父视图坐标系中的矩形

但需要确认 `canvasView.bounds` 确实代表可见区域。

---

## 推荐修复步骤

### 步骤 1: 添加新的坐标计算方法

在 `NativeCanvasView.swift` 中添加：

```swift
/// 获取当前视口中心点在画布内容坐标系中的位置
/// 这是最简单、最直接的计算方法
func getViewportCenterInContent() -> CGPoint {
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset
    let viewportSize = bounds.size

    let centerX = (viewportSize.width / 2 + offset.x) / scale
    let centerY = (viewportSize.height / 2 + offset.y) / scale

    return CGPoint(x: centerX, y: centerY)
}

/// 获取当前可见的画布内容区域
func getVisibleContentRect() -> CGRect {
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset
    let viewportSize = bounds.size

    return CGRect(
        x: offset.x / scale,
        y: offset.y / scale,
        width: viewportSize.width / scale,
        height: viewportSize.height / scale
    )
}
```

### 步骤 2: 修改 addAssetToCanvas 方法

在 `NativeEditorViewModel.swift` 中修改：

```swift
func addAssetToCanvas(_ asset: Asset) {
    guard let canvasView = canvasView else { return }

    // 【关键修复】立即捕获当前视口中心点，避免异步加载期间画布移动
    let centerInContent = canvasView.getViewportCenterInContent()

    print("📍 [addAssetToCanvas] 视口中心点: \(centerInContent)")

    loadImageSize(from: asset.url) { [weak self] originalSize in
        guard let self = self else { return }

        let maxSize: CGFloat = 600
        let scaledSize = self.scaleImageSizeToFit(originalSize, maxSize: maxSize)

        // 确保中心点在画布范围内
        let canvasSize = CGSize(width: 5000, height: 5000)
        let safeCenter = CGPoint(
            x: max(scaledSize.width / 2, min(canvasSize.width - scaledSize.width / 2, centerInContent.x)),
            y: max(scaledSize.height / 2, min(canvasSize.height - scaledSize.height / 2, centerInContent.y))
        )

        // 计算图片左上角位置
        let position = CGPoint(
            x: safeCenter.x - scaledSize.width / 2,
            y: safeCenter.y - scaledSize.height / 2
        )

        print("📍 [addAssetToCanvas] 图片位置: \(position)")

        // 创建图层节点
        let layer = LayerNode(
            type: .userImage,
            url: asset.url,
            frame: CGRect(origin: position, size: scaledSize),
            originalSize: originalSize,
            rotation: 0,
            isLocked: false,
            zIndex: canvasView.getNextGlobalZIndex(),
            opacity: 1.0,
            createdAt: Date()
        )

        canvasView.addLayer(layer)
        self.canvasDocument.addLayer(layer)
    }
}
```

### 步骤 3: 添加调试日志验证

```swift
// 在 NativeCanvasView 中添加
func debugCoordinateSystem() {
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset
    let viewportSize = bounds.size

    print("=== 坐标系统调试 ===")
    print("缩放比例: \(scale)")
    print("内容偏移: \(offset)")
    print("视口大小: \(viewportSize)")
    print("视口中心(视口坐标): (\(viewportSize.width/2), \(viewportSize.height/2))")

    let center = getViewportCenterInContent()
    print("视口中心(内容坐标): \(center)")

    let visibleRect = getVisibleContentRect()
    print("可见内容区域: \(visibleRect)")
    print("====================")
}
```

---

## 测试用例

### 测试 1: 初始状态添加图片
1. 打开编辑器，不做任何操作
2. 从资源栏添加图片
3. **预期**: 图片出现在屏幕中央

### 测试 2: 缩放后添加图片
1. 将画布缩放到 50%
2. 从资源栏添加图片
3. **预期**: 图片出现在屏幕中央（画布内容坐标会更大）

### 测试 3: 拖动后添加图片
1. 将画布拖动到右下角
2. 从资源栏添加图片
3. **预期**: 图片出现在屏幕中央（画布内容坐标会偏移）

### 测试 4: 缩放+拖动后添加图片
1. 将画布缩放到 200%
2. 将画布拖动到左上角
3. 从资源栏添加图片
4. **预期**: 图片出现在屏幕中央

### 测试 5: 连续添加多张图片
1. 添加第一张图片
2. 拖动画布
3. 添加第二张图片
4. **预期**: 两张图片都出现在各自添加时的屏幕中央

---

## 参考资料

### UIScrollView 坐标转换

根据 [Stack Overflow 讨论](https://stackoverflow.com/questions/10454916/convertrect-accounting-for-uiscrollview-zoom-and-contentoffset)，UIScrollView 的坐标转换需要考虑：

1. **contentOffset**: 滚动偏移量
2. **zoomScale**: 缩放比例
3. **bounds vs contentSize**: 视口大小 vs 内容大小

标准公式：
```
contentPoint = (viewportPoint + contentOffset) / zoomScale
viewportPoint = contentPoint * zoomScale - contentOffset
```

### PKCanvasView 特性

根据 [Apple Developer Forums](https://developer.apple.com/forums/thread/698317)：
- PKCanvasView 继承自 UIScrollView
- 其 delegate 被重写为 PKCanvasViewDelegate
- 缩放和滚动行为与标准 UIScrollView 相同

---

## 总结

### 问题根因
1. `contentRect(forViewportRect:)` 方法中的 `convert` 调用是多余的
2. 异步加载图片期间，画布状态可能改变
3. 坐标计算公式本身是正确的，但实现有问题

### 修复要点
1. 使用简化的坐标计算方法 `getViewportCenterInContent()`
2. 在点击时立即捕获坐标，避免异步问题
3. 添加充分的调试日志验证计算结果

### 预期效果
修复后，无论画布如何缩放或拖动，新添加的图片都会出现在屏幕可见区域的正中央。

---

## 附录: 完整修复代码

### NativeCanvasView.swift 新增方法

```swift
// MARK: - Viewport Coordinate Helpers

/// 获取当前视口中心点在画布内容坐标系中的位置
/// 这是计算图片添加位置的核心方法
func getViewportCenterInContent() -> CGPoint {
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset
    let viewportSize = bounds.size

    // 公式: contentCoord = (viewportCoord + offset) / scale
    let centerX = (viewportSize.width / 2 + offset.x) / scale
    let centerY = (viewportSize.height / 2 + offset.y) / scale

    return CGPoint(x: centerX, y: centerY)
}

/// 获取当前可见的画布内容区域
func getVisibleContentRect() -> CGRect {
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset
    let viewportSize = bounds.size

    return CGRect(
        x: offset.x / scale,
        y: offset.y / scale,
        width: viewportSize.width / scale,
        height: viewportSize.height / scale
    )
}
```

### NativeEditorViewModel.swift 修改

```swift
func addAssetToCanvas(_ asset: Asset) {
    guard let canvasView = canvasView else { return }

    // 【关键】立即捕获当前视口中心点
    let centerInContent = canvasView.getViewportCenterInContent()

    loadImageSize(from: asset.url) { [weak self] originalSize in
        guard let self = self, let canvasView = self.canvasView else { return }

        let maxSize: CGFloat = 600
        let scaledSize = self.scaleImageSizeToFit(originalSize, maxSize: maxSize)

        // 边界检查：确保图片完全在画布内
        let canvasSize = CGSize(width: 5000, height: 5000)
        let safeCenter = CGPoint(
            x: max(scaledSize.width / 2, min(canvasSize.width - scaledSize.width / 2, centerInContent.x)),
            y: max(scaledSize.height / 2, min(canvasSize.height - scaledSize.height / 2, centerInContent.y))
        )

        let position = CGPoint(
            x: safeCenter.x - scaledSize.width / 2,
            y: safeCenter.y - scaledSize.height / 2
        )

        let layer = LayerNode(
            type: .userImage,
            url: asset.url,
            frame: CGRect(origin: position, size: scaledSize),
            originalSize: originalSize,
            rotation: 0,
            isLocked: false,
            zIndex: canvasView.getNextGlobalZIndex(),
            opacity: 1.0,
            createdAt: Date()
        )

        canvasView.addLayer(layer)
        self.canvasDocument.addLayer(layer)
    }
}
```
