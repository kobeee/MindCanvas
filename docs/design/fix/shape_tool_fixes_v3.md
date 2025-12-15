# 图形工具问题修复方案 v3.0

## 文档信息

- **版本**: v3.0
- **日期**: 2025-12-15
- **状态**: 待实施
- **优先级**: P0 (阻塞性问题)

---

## 一、问题汇总

### 问题 1：选择箭头形状后拖出的是直线

**现象**：用户在形状选择器中选择"箭头"，在画布上拖动后生成的是直线而非箭头。

**根因**：

1. **工具与形状类型混淆**：系统存在两套并行的箭头机制：
   - `CanvasTool.arrow`：独立的箭头工具，使用 `ArrowDrawingView` + `SelectableArrowView`
   - `ShapeType.arrow`：形状选择器中的箭头选项，被错误地路由到 `ShapeDrawingView`

2. **代码路径错误**：

```swift
// CanvasToolbar.swift 第 22-28 行
onShapeSelected: { shape in
    showShapePicker = false
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        currentTool = .rectangle  // 问题：无论选什么形状，都设置为 .rectangle
    }
    onShapeSelected?(shape)
}
```

当用户选择 `ShapeType.arrow` 时：
- `currentTool` 被设置为 `.rectangle`
- 触发 `NativeEditorView` 中 `if viewModel.stateManager.currentTool == .rectangle` 分支
- 调用 `ShapeDrawingView`，但它对 `.line` 和 `.arrow` 的绘制完全相同（只画直线）

3. **ShapeDrawingView 不画箭头头部**：

```swift
// ShapeDrawingView.swift 第 49-51 行
case .line, .arrow:
    path.move(to: CGPoint(x: rect.minX, y: rect.midY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
```

两种类型使用相同的绘制逻辑，没有箭头头部。

---

### 问题 2：直线只能横着拖出来

**现象**：拖动绘制直线时，无论如何拖动方向，直线始终是水平的。

**根因**：

`ShapeDrawingView` 中的直线绘制逻辑固定使用矩形的水平中线：

```swift
// ShapeDrawingView.swift 第 49-51 行
case .line, .arrow:
    path.move(to: CGPoint(x: rect.minX, y: rect.midY))  // 从左边中点
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))  // 到右边中点
```

无论拖拽形成什么样的矩形，直线都从 `rect.minX, rect.midY` 到 `rect.maxX, rect.midY`，始终是水平的。

**问题本质**：直线/箭头是基于两点（startPoint, endPoint）绘制的，不应该使用矩形（CGRect）作为绘制参数。

---

### 问题 3：圆角矩形无图标且选择后没反应

**现象**：
- 形状选择器中圆角矩形显示空白图标
- 选择圆角矩形后画布上无法绘制

**根因**：

1. **图标问题**：`rectangle.roundedcorners` 这个 SF Symbol 名称在某些 iOS 版本上可能不存在或显示异常。

2. **选择后无反应的可能原因**：
   - 如果 `ShapeType.iconName` 返回无效图标名，按钮可能无法正确响应
   - 需要验证实际行为，但代码逻辑上 `.roundedRectangle` 是完整支持的

```swift
// ShapeType.swift 第 21 行
case .roundedRectangle: return "rectangle.roundedcorners"  // 图标名可能有问题
```

---

### 问题 4：形状绘制时发生偏移（类似笔画偏移）

**现象**：在画布上拖动绘制形状时，预览位置和最终创建位置不一致，出现偏移。

**根因**：

这与之前笔画偏移问题同源 —— **SwiftUI 手势视图和 UIKit 画布之间的坐标系不同步**。

1. **手势坐标系问题**：
   - `ShapeDrawingGestureView` 在 SwiftUI 层捕获手势
   - 手势坐标是相对于 `GeometryReader` 的视图坐标
   - 但这个视图的位置受到画布 contentOffset 和 zoomScale 的影响

2. **预览和创建的坐标不一致**：
   - 预览（`ShapeDrawingView`）使用视图坐标直接渲染，位置正确
   - 创建（`ShapeLayerNode`）虽然做了坐标转换，但转换逻辑可能有问题

3. **潜在的布局更新干扰**：
   - 绘图过程中 SwiftUI 可能触发重布局
   - 导致手势坐标突然跳变

---

### 问题 5：形状对象只能移动，不能缩放和旋转

**现象**：在选择工具下，形状可以拖动移动，但双指缩放和旋转手势无效。

**根因**：

检查 `SelectableShapeView` 代码发现手势已经实现，问题可能在于：

1. **手势未被正确启用**：虽然 `enableShapeGestures()` 被调用，但需要验证是否在正确的时机

2. **手势识别器配置问题**：检查 `handlePinch` 和 `handleRotate` 的实现：

```swift
// SelectableShapeView.swift 第 172-189 行
@objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
    switch gesture.state {
    case .ended:
        let newWidth = bounds.width * abs(transform.a)
        let newHeight = bounds.height * abs(transform.d)
        bounds.size = CGSize(width: newWidth, height: newHeight)
        transform = CGAffineTransform(rotationAngle: shapeNode.rotation)  // 问题：没有更新 shapeNode
        syncToNode()
        // ...
    }
}
```

3. **syncToNode 只更新 frame 和 rotation**：

```swift
// SelectableShapeView.swift 第 207-213 行
private func syncToNode() {
    shapeNode = shapeNode.updated(
        frame: frame,
        rotation: atan2(transform.b, transform.a)
    )
    onNodeUpdated?(shapeNode)
}
```

缩放后 `bounds.size` 变了，但 `frame.origin` 没有正确更新，导致形状位置跳动。

---

## 二、解决方案

### 2.1 架构决策：统一直线/箭头到独立绘制系统

**决策**：将直线和箭头从 `ShapeDrawingView` 中移出，使用独立的绘制视图。

**理由**：
1. 直线/箭头是基于两点的，形状是基于矩形的，本质不同
2. 箭头需要绘制箭头头部，逻辑复杂
3. 分离后代码更清晰，维护更容易

```
现有架构（混乱）:
ShapeType.arrow --> ShapeDrawingView --> 只画直线
CanvasTool.arrow --> ArrowDrawingView --> 完整箭头

重构后架构（清晰）:
ShapeType（移除 line/arrow）--> ShapeDrawingView --> 形状
新增 LineDrawingView --> 直线
保留 ArrowDrawingView --> 箭头

或者更简化的方案：
选择 line/arrow 时 --> 切换到 CanvasTool.arrow，复用现有逻辑
```

### 2.2 最优方案：复用现有箭头系统

为了最小化代码改动和风险，推荐以下方案：

#### 步骤 1：修改 CanvasToolbar 的形状选择回调

**文件**：`Views/Editor/Canvas/CanvasToolbar.swift`

**修改位置**：第 22-28 行

```swift
// 修改前
onShapeSelected: { shape in
    showShapePicker = false
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        currentTool = .rectangle
    }
    onShapeSelected?(shape)
}

// 修改后
onShapeSelected: { shape in
    showShapePicker = false
    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        // 根据形状类型设置不同的工具
        if shape.isLineType {
            // 直线和箭头使用独立的箭头工具
            currentTool = .arrow
        } else {
            currentTool = .rectangle
        }
    }
    onShapeSelected?(shape)
}
```

#### 步骤 2：修改箭头绘制逻辑支持直线

**文件**：`Views/Editor/NativeEditorView.swift`

**修改位置**：第 325-371 行（箭头绘制层）

```swift
// 修改前
if viewModel.stateManager.currentTool == .arrow {
    // ... 只处理箭头
}

// 修改后
if viewModel.stateManager.currentTool == .arrow {
    ZStack {
        // 根据 selectedShapeType 决定显示直线还是箭头
        if isDrawingArrow, let start = arrowStartPoint, let end = arrowEndPoint {
            if viewModel.selectedShapeType == .line {
                // 直线预览
                LinePreviewView(
                    startPoint: start,
                    endPoint: end,
                    color: Color.fromHex(viewModel.stateManager.arrowColor) ?? .blue,
                    lineWidth: viewModel.stateManager.arrowLineWidth
                )
            } else {
                // 箭头预览（默认）
                ArrowView(
                    startPoint: start,
                    endPoint: end,
                    color: Color.fromHex(viewModel.stateManager.arrowColor) ?? .blue,
                    lineWidth: viewModel.stateManager.arrowLineWidth
                )
            }
        }

        // 绘制手势
        ArrowDrawingView(...) { start, end in
            // ... 坐标转换逻辑

            if viewModel.selectedShapeType == .line {
                // 创建直线（使用 ArrowLayerNode，但标记为无箭头头部）
                let line = ArrowLayerNode(
                    startPoint: contentStart,
                    endPoint: contentEnd,
                    color: viewModel.stateManager.arrowColor,
                    lineWidth: viewModel.stateManager.arrowLineWidth,
                    zIndex: ...,
                    hasArrowHead: false  // 新增属性
                )
                canvasView.addArrow(line)
            } else {
                // 创建箭头
                let arrow = ArrowLayerNode(...)
                canvasView.addArrow(arrow)
            }
        }
    }
}
```

#### 步骤 3：扩展 ArrowLayerNode 支持直线

**文件**：`Models/Canvas/ArrowLayerNode.swift`

```swift
struct ArrowLayerNode: Codable, Identifiable {
    // ... 现有属性

    /// 是否显示箭头头部（false = 直线）
    var hasArrowHead: Bool = true

    // 更新 init 方法
    init(
        startPoint: CGPoint,
        endPoint: CGPoint,
        color: String = "#000000",
        lineWidth: CGFloat = 2,
        zIndex: Int = 0,
        hasArrowHead: Bool = true  // 新增
    ) {
        // ...
        self.hasArrowHead = hasArrowHead
    }
}
```

#### 步骤 4：修改 SelectableArrowView 支持直线渲染

**文件**：`Views/Editor/Canvas/SelectableArrowView.swift`

**修改位置**：`updateArrowPath()` 方法（第 119-168 行）

```swift
private func updateArrowPath() {
    let path = UIBezierPath()
    // ... 现有的直线绘制逻辑

    path.move(to: localStart)
    path.addLine(to: localEnd)

    // 只有在 hasArrowHead 为 true 时才绘制箭头头部
    if arrowNode.hasArrowHead {
        let angle = atan2(localEnd.y - localStart.y, localEnd.x - localStart.x)
        let arrowLength: CGFloat = 20 * scale
        let arrowAngle: CGFloat = .pi / 6

        let arrowPoint1 = CGPoint(
            x: localEnd.x - arrowLength * cos(angle - arrowAngle),
            y: localEnd.y - arrowLength * sin(angle - arrowAngle)
        )
        let arrowPoint2 = CGPoint(
            x: localEnd.x - arrowLength * cos(angle + arrowAngle),
            y: localEnd.y - arrowLength * sin(angle + arrowAngle)
        )

        path.move(to: localEnd)
        path.addLine(to: arrowPoint1)

        path.move(to: localEnd)
        path.addLine(to: arrowPoint2)
    }

    arrowLayer.path = path.cgPath
}
```

#### 步骤 5：新增 LinePreviewView（简单的 SwiftUI 预览）

**新建文件**：`Views/Editor/Canvas/LinePreviewView.swift`

```swift
import SwiftUI

/// 直线预览视图
struct LinePreviewView: View {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Path { path in
            path.move(to: startPoint)
            path.addLine(to: endPoint)
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}
```

---

### 2.3 修复圆角矩形图标

**文件**：`Models/Canvas/ShapeType.swift`

**修改位置**：第 21 行

```swift
// 修改前
case .roundedRectangle: return "rectangle.roundedcorners"

// 修改后（使用更通用的图标）
case .roundedRectangle: return "rectangle.inset.filled"
// 或者使用自定义绘制的图标
```

**备选方案**：如果 SF Symbol 不满足需求，可以使用自定义形状绘制：

```swift
// 在 ShapePickerButton 中添加特殊处理
if shape == .roundedRectangle {
    // 使用自定义绘制
    RoundedRectangle(cornerRadius: 4)
        .stroke(lineWidth: 2)
        .frame(width: 24, height: 18)
} else {
    Image(systemName: shape.iconName)
}
```

---

### 2.4 修复形状绘制偏移问题

**问题本质**：SwiftUI 手势层和 UIKit 画布层的坐标系不一致。

**解决方案**：参考箭头绘制的成功经验，确保：

1. **手势坐标使用一致的参考系**
2. **坐标转换在正确的时机执行**
3. **绘图过程中不触发布局更新**

**文件**：`Views/Editor/Canvas/ShapeDrawingView.swift`

**修改 ShapeDrawingGestureView**：

```swift
struct ShapeDrawingGestureView: View {
    // ... 现有属性

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)  // 明确使用 local 坐标空间
                        .onChanged { value in
                            if !isDrawing {
                                isDrawing = true
                                startPoint = value.startLocation
                            }
                            endPoint = value.location
                        }
                        .onEnded { value in
                            // ... 现有逻辑
                        }
                )
        }
        .allowsHitTesting(true)
    }
}
```

**关键修改**：确保 `NativeEditorView.swift` 中的坐标转换正确（已有实现看起来正确，需要验证实际运行）。

如果问题依然存在，可能需要**将形状预览也移到 UIKit 层**，与箭头预览保持一致。

---

### 2.5 修复形状缩放和旋转

**文件**：`Views/Editor/Canvas/SelectableShapeView.swift`

#### 问题 1：handlePinch 缩放后 frame 计算错误

**修改位置**：第 172-189 行

```swift
// 修改前
@objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
    switch gesture.state {
    case .ended:
        let newWidth = bounds.width * abs(transform.a)
        let newHeight = bounds.height * abs(transform.d)
        bounds.size = CGSize(width: newWidth, height: newHeight)
        transform = CGAffineTransform(rotationAngle: shapeNode.rotation)
        syncToNode()
        // ...
    }
}

// 修改后
@objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
    switch gesture.state {
    case .began:
        onOperationStart?(shapeNode)

    case .changed:
        transform = transform.scaledBy(x: gesture.scale, y: gesture.scale)
        gesture.scale = 1.0

    case .ended:
        // 从 transform 提取缩放比例
        let scaleX = sqrt(transform.a * transform.a + transform.c * transform.c)
        let scaleY = sqrt(transform.b * transform.b + transform.d * transform.d)

        // 计算新的尺寸
        let newWidth = bounds.width * scaleX
        let newHeight = bounds.height * scaleY

        // 保持中心点不变
        let oldCenter = center

        // 更新 frame
        frame = CGRect(
            x: oldCenter.x - newWidth / 2,
            y: oldCenter.y - newHeight / 2,
            width: newWidth,
            height: newHeight
        )

        // 重置 transform，只保留旋转
        transform = CGAffineTransform(rotationAngle: shapeNode.rotation)

        // 更新路径
        updateShapePath()

        // 同步到节点
        syncToNode()
        onOperationEnd?(shapeNode, shapeNode)

    default:
        break
    }
}
```

#### 问题 2：handleRotate 同样需要修复

**修改位置**：第 192-205 行

```swift
// 修改后
@objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
    switch gesture.state {
    case .began:
        onOperationStart?(shapeNode)

    case .changed:
        transform = transform.rotated(by: gesture.rotation)
        gesture.rotation = 0

    case .ended:
        // 从 transform 提取旋转角度
        let rotation = atan2(transform.b, transform.a)

        // 更新节点
        shapeNode = shapeNode.updated(frame: frame, rotation: rotation)

        // 重置 transform
        transform = CGAffineTransform(rotationAngle: rotation)

        // 更新外观
        updateShapePath()
        updateSelectionAppearance()

        // 同步
        onNodeUpdated?(shapeNode)
        onOperationEnd?(shapeNode, shapeNode)

    default:
        break
    }
}
```

#### 问题 3：确保 syncToNode 正确更新所有属性

```swift
private func syncToNode() {
    let rotation = atan2(transform.b, transform.a)
    shapeNode = shapeNode.updated(
        frame: frame,
        rotation: rotation
    )
    onNodeUpdated?(shapeNode)
}
```

---

## 三、实施计划

### Phase 1：紧急修复（P0）

| 优先级 | 修复项 | 文件 | 预计耗时 |
|--------|--------|------|----------|
| 1 | 箭头/直线工具切换 | CanvasToolbar.swift | 15min |
| 2 | ArrowLayerNode 支持直线 | ArrowLayerNode.swift | 20min |
| 3 | SelectableArrowView 条件渲染 | SelectableArrowView.swift | 15min |
| 4 | 新增 LinePreviewView | LinePreviewView.swift | 10min |
| 5 | NativeEditorView 集成 | NativeEditorView.swift | 30min |

### Phase 2：体验优化（P1）

| 优先级 | 修复项 | 文件 | 预计耗时 |
|--------|--------|------|----------|
| 1 | 圆角矩形图标 | ShapeType.swift | 10min |
| 2 | 形状缩放修复 | SelectableShapeView.swift | 30min |
| 3 | 形状旋转修复 | SelectableShapeView.swift | 20min |

### Phase 3：稳定性（P2）

| 优先级 | 修复项 | 文件 | 预计耗时 |
|--------|--------|------|----------|
| 1 | 形状绘制偏移排查 | ShapeDrawingView.swift | 60min |
| 2 | 坐标系统统一验证 | 多个文件 | 30min |

---

## 四、详细代码修改清单

### 4.1 需要修改的文件

| 文件路径 | 修改类型 | 具体修改内容 |
|---------|---------|-------------|
| `Views/Editor/Canvas/CanvasToolbar.swift` | 修改 | 形状选择回调中根据类型设置工具 |
| `Models/Canvas/ArrowLayerNode.swift` | 修改 | 添加 `hasArrowHead` 属性 |
| `Views/Editor/Canvas/SelectableArrowView.swift` | 修改 | `updateArrowPath()` 条件渲染箭头头部 |
| `Views/Editor/NativeEditorView.swift` | 修改 | 箭头绘制层支持直线预览和创建 |
| `Models/Canvas/ShapeType.swift` | 修改 | 圆角矩形图标名 |
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | 修复缩放和旋转逻辑 |

### 4.2 需要新增的文件

| 文件路径 | 说明 |
|---------|------|
| `Views/Editor/Canvas/LinePreviewView.swift` | 直线预览视图 |

---

## 五、测试用例

### 5.1 直线/箭头功能测试

| 测试项 | 操作步骤 | 预期结果 |
|--------|---------|---------|
| 选择箭头形状 | 点击形状工具 -> 选择箭头 | 工具切换为箭头绘制模式 |
| 绘制箭头 | 在画布上拖动 | 显示箭头预览，释放后创建带箭头头部的线 |
| 选择直线形状 | 点击形状工具 -> 选择直线 | 工具切换为箭头绘制模式 |
| 绘制直线 | 在画布上拖动 | 显示直线预览，释放后创建无箭头头部的线 |
| 直线方向 | 任意方向拖动 | 直线按拖动方向绘制，非水平限制 |

### 5.2 形状功能测试

| 测试项 | 操作步骤 | 预期结果 |
|--------|---------|---------|
| 圆角矩形图标 | 打开形状选择器 | 圆角矩形显示正确图标 |
| 绘制圆角矩形 | 选择圆角矩形 -> 拖动绘制 | 创建圆角矩形，位置正确 |
| 形状缩放 | 选择工具 -> 选中形状 -> 双指捏合 | 形状等比例缩放，中心不变 |
| 形状旋转 | 选择工具 -> 选中形状 -> 双指旋转 | 形状绕中心旋转 |
| 绘制位置 | 在画布任意位置绘制形状 | 形状出现在拖动位置，无偏移 |

### 5.3 边界测试

| 测试项 | 操作步骤 | 预期结果 |
|--------|---------|---------|
| 缩放状态下绘制 | 放大画布到 200% -> 绘制形状 | 形状位置正确 |
| 滚动后绘制 | 滚动画布 -> 绘制形状 | 形状在当前可见区域正确创建 |
| 撤销直线 | 绘制直线 -> 点击撤销 | 直线被移除 |

---

## 六、风险评估

### 6.1 低风险修改

- **CanvasToolbar 工具切换**：影响范围小，容易验证
- **ArrowLayerNode 添加属性**：向后兼容，默认值为 true
- **圆角矩形图标**：纯 UI 修改

### 6.2 中等风险修改

- **SelectableArrowView 条件渲染**：需要验证现有箭头功能不受影响
- **SelectableShapeView 缩放旋转**：需要仔细测试变换计算

### 6.3 高风险修改

- **NativeEditorView 集成**：涉及多个状态变量，需要完整测试绘制流程
- **坐标转换相关**：如果需要调整，可能影响整个绘制系统

### 6.4 回滚方案

每个 Phase 完成后进行验证，如果出现问题可以：
1. Git revert 到上一个 Phase 完成后的状态
2. 单独回滚特定文件的修改

---

## 七、附录

### A. 现有代码架构

```
绘制流程：
1. 用户在 ShapePickerPopover 选择形状
2. CanvasToolbar.onShapeSelected 被调用
3. currentTool 被设置
4. NativeEditorView 根据 currentTool 显示对应的绘制层
5. 用户拖动触发手势
6. 手势结束，创建对应的 LayerNode
7. LayerNode 被添加到 NativeCanvasView
8. 对应的 SelectableXXXView 被创建并显示

选择流程：
1. 用户切换到选择工具
2. NativeCanvasView.updateForTool(.select) 启用对象手势
3. 用户点击对象
4. SelectableXXXView.handleTap 触发
5. 对象被选中，显示选择边框

变换流程：
1. 用户在选择状态下进行双指操作
2. handlePinch/handleRotate 被调用
3. 实时更新 transform
4. 手势结束，计算最终值
5. syncToNode 更新数据模型
6. 触发撤销记录
```

### B. 相关 SF Symbol 图标

| 用途 | 推荐图标 | 备选图标 |
|------|---------|---------|
| 直线 | `line.diagonal` | `minus` |
| 箭头 | `arrow.right` | `arrow.up.right` |
| 圆角矩形 | `rectangle.inset.filled` | `app` |
| 矩形 | `rectangle` | `square` |

### C. 参考资源

- [Apple SF Symbols Browser](https://developer.apple.com/sf-symbols/)
- [SwiftUI Gesture Documentation](https://developer.apple.com/documentation/swiftui/gestures)
- [CGAffineTransform Best Practices](https://developer.apple.com/documentation/coregraphics/cgaffinetransform)
