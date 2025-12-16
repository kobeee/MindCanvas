# 图形绘制偏移与缩放跳变修复方案 v6.0

## 文档信息
- **版本**: v6.0
- **日期**: 2025-12-16
- **优先级**: P0 (核心交互问题)
- **预估工作量**: 3-4 小时

---

## 一、问题现象

### 1.1 问题一：图形绘制时偏移

**现象描述**：
- 用户选择图形工具（如矩形）在画布上拖动绘制
- 绘制过程中，图形预览位置与手指位置存在偏移
- 手指释放后，图形回到正确位置

**用户反馈的图片对比**：
- 图1：绘制过程中矩形位置偏离
- 图2：释放后矩形回到正确位置

### 1.2 问题二：缩放时先放大再跟手

**现象描述**：
- 用户选中一个已创建的形状
- 点击任意一个角点控制点开始拖动
- 形状会先突然放大一定比例，然后才开始跟随手指缩放
- 给人"先跳一下再拖"的不流畅感

---

## 二、根因分析

### 2.1 问题一根因：坐标系不一致导致预览偏移

#### 代码位置

[NativeEditorView.swift:387-440](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift#L387-L440)

```swift
// 形状绘制层
if viewModel.stateManager.currentTool == .rectangle {
    ZStack {
        // 显示正在绘制的形状 (SwiftUI 视图坐标系)
        if isDrawingRectangle, let start = rectangleStartPoint, let end = rectangleEndPoint {
            let rect = CGRect(
                x: min(start.x, end.x),
                y: min(start.y, end.y),
                width: abs(end.x - start.x),
                height: abs(end.y - start.y)
            )

            ShapeDrawingView(
                rect: rect,  // <-- 问题: 使用原始视图坐标
                ...
            )
        }
```

[ShapeDrawingView.swift:103-107](src/MindCanvas/MindCanvas/Views/Editor/Canvas/ShapeDrawingView.swift#L103-L107)

```swift
.stroke(color, style: StrokeStyle(lineWidth: lineWidth, ...))
)
.position(x: rect.midX, y: rect.midY)  // <-- 问题: position 修饰符会再次偏移
```

#### 根因

1. **SwiftUI `.position()` 修饰符的特殊行为**：
   - `.position(x:y:)` 将视图的**中心点**放置在指定坐标
   - 但 `ShapeDrawingView` 内部的 Path 已经基于 `rect` 的原点绘制
   - 造成了双重定位：Path 自身有位置 + position 又将中心移动

2. **形状预览与最终形状的坐标系不同**：
   - 预览使用的是 SwiftUI 视图坐标（相对于 GeometryReader）
   - 最终创建形状时做了坐标转换（加上 contentOffset，除以 scale）
   - 但预览没有做相同的坐标处理

3. **PKCanvasView 的 contentOffset 和 zoomScale**：
   - overlayContainerView 通过 `syncOverlayTransform()` 同步了变换
   - 但 SwiftUI 层的形状预览视图是独立绘制的，没有受到这个变换的影响

### 2.2 问题二根因：缩放初始计算使用了错误的参考值

#### 代码位置

[SelectableShapeView.swift:434-492](src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift#L434-L492)

```swift
private func handleResizeImproved(handle: ControlHandle, currentPoint: CGPoint) {
    guard let oppositeCorner = handle.oppositeCorner else { return }

    // Step 1: 计算初始状态下锚点的位置 (考虑旋转)
    let anchorLocalOffset = anchorOffset(for: oppositeCorner)
    let cosR = cos(initialRotation)
    let sinR = sin(initialRotation)

    // 锚点在 superview 坐标系中的位置
    let anchorInSuperview = CGPoint(
        x: initialCenter.x + anchorLocalOffset.x * cosR - anchorLocalOffset.y * sinR,
        y: initialCenter.y + anchorLocalOffset.x * sinR + anchorLocalOffset.y * cosR
    )

    // Step 2: 计算拖动向量
    let dx = currentPoint.x - anchorInSuperview.x  // <-- 问题: currentPoint 应该和 dragStartPoint 比较
    let dy = currentPoint.y - anchorInSuperview.y
```

#### 根因

1. **第一帧计算基准错误**：
   - 缩放逻辑使用 `currentPoint - anchorInSuperview` 计算新尺寸
   - 但 `currentPoint` 是当前触摸点，`anchorInSuperview` 是对角锚点
   - 第一帧时，`currentPoint` 就是 `dragStartPoint`（手指刚触碰角点的位置）
   - 角点位置和锚点位置之间的距离就是**初始尺寸的一半**（对角线长度的投影）
   - 如果触摸点不在角点的精确中心，会导致计算出的尺寸偏大或偏小

2. **控制点命中区域较大，但位置计算假设精确命中**：
   - hitTestHandle 的 hitRadius 是 `handleSize + 10 = 22pt`
   - 用户可能点击在控制点边缘，而非正中心
   - 但缩放计算假设触摸点就是控制点的精确位置

3. **没有使用增量计算**：
   - 正确做法应该是：`新尺寸 = 初始尺寸 + 拖动增量`
   - 当前做法是：`新尺寸 = |currentPoint - anchor|` 直接计算绝对距离
   - 这导致第一帧就可能有尺寸跳变

---

## 三、解决方案

### 3.1 问题一修复：统一形状预览的坐标系

#### 方案 A：修改 ShapeDrawingView，移除 .position() 修饰符（推荐）

**原理**：Path 应该直接在正确的位置绘制，不需要额外的 position 调整

**修改文件**：[ShapeDrawingView.swift](src/MindCanvas/MindCanvas/Views/Editor/Canvas/ShapeDrawingView.swift)

```swift
// 文件: src/MindCanvas/MindCanvas/Views/Editor/Canvas/ShapeDrawingView.swift

/// 形状绘制预览视图
struct ShapeDrawingView: View {
    let rect: CGRect
    let shapeType: ShapeType
    let color: Color
    let lineWidth: CGFloat
    let isFilled: Bool

    var body: some View {
        // 移除 .position() 修饰符
        // Path 直接在 rect 指定的位置绘制，不再需要额外定位
        Canvas { context, size in
            var path = Path()

            switch shapeType {
            case .rectangle:
                path.addRect(rect)

            case .roundedRectangle:
                path.addRoundedRect(in: rect, cornerSize: CGSize(width: 12, height: 12))

            case .circle:
                path.addEllipse(in: rect)

            case .triangle:
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()

            case .diamond:
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.closeSubpath()

            case .star:
                addStarPath(to: &path, in: rect, points: 5)

            case .pentagon:
                addPolygonPath(to: &path, in: rect, sides: 5)

            case .hexagon:
                addPolygonPath(to: &path, in: rect, sides: 6)

            case .line, .arrow:
                path.move(to: CGPoint(x: rect.minX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }

            // 填充（如果需要）
            if isFilled {
                context.fill(path, with: .color(color))
            }

            // 描边
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        // 关键: 不使用 .position()，Canvas 默认覆盖整个父视图
        // rect 参数已经包含了正确的位置信息
    }

    private func addStarPath(to path: inout Path, in rect: CGRect, points: Int) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.4

        for i in 0..<(points * 2) {
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
    }

    private func addPolygonPath(to path: inout Path, in rect: CGRect, sides: Int) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        for i in 0..<sides {
            let angle = CGFloat(i) * 2 * .pi / CGFloat(sides) - .pi / 2
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
    }
}
```

**关键改动说明**：

| 改动 | 原因 |
|-----|------|
| 使用 `Canvas` 替代 `Path` + `.position()` | Canvas 视图覆盖整个父视图区域，Path 在其中按绝对坐标绘制 |
| 移除 `.position(x: rect.midX, y: rect.midY)` | 这是造成偏移的直接原因 |
| rect 参数直接作为绘制坐标 | 保持与手势返回的坐标一致 |

### 3.2 问题二修复：正确的增量式缩放计算

#### 核心原理

参考 [Apple Transform 文档](https://developer.apple.com/documentation/uikit/uiview/1622459-transform)、[Hacking with Swift - Anchor Point](https://www.hackingwithswift.com/example-code/calayer/how-to-change-a-views-anchor-point-without-moving-it) 和 [Swift by Sundell - Bounds and Transforms](https://www.swiftbysundell.com/tips/uiview-bounds-and-transforms/) 的最佳实践：

1. **使用 `center` + `bounds` 而非 `frame`** - transform 存在时 frame 不可靠
2. **使用增量计算而非绝对计算** - `新尺寸 = 初始尺寸 + delta`
3. **保存拖动起始位置的角点位置，而非触摸点位置** - 避免触摸偏移导致跳变

#### 修改文件

[SelectableShapeView.swift](src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift)

```swift
// 文件: src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift

// MARK: - 属性（需要添加或修改的）

// 拖动开始时的角点实际位置（不是触摸点，是角点本身的位置）
private var initialHandlePosition: CGPoint = .zero

// MARK: - handlePan 方法修改

@objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    let locationInSelf = gesture.location(in: self)

    switch gesture.state {
    case .began:
        // 保存初始状态
        initialNode = shapeNode
        onOperationStart?(shapeNode)

        activeHandle = hitTestHandle(at: locationInSelf)

        // 关键: 保存 center 和 bounds，而非 frame
        initialCenter = center
        initialBounds = bounds
        initialRotation = atan2(transform.b, transform.a)

        // 如果是缩放，保存被拖动角点的实际位置（不是触摸点）
        if let handle = activeHandle, handle != .rotation {
            // 计算角点在 superview 坐标系中的位置
            let handleLocalOffset = handleOffset(for: handle)
            let cosR = cos(initialRotation)
            let sinR = sin(initialRotation)
            initialHandlePosition = CGPoint(
                x: initialCenter.x + handleLocalOffset.x * cosR - handleLocalOffset.y * sinR,
                y: initialCenter.y + handleLocalOffset.x * sinR + handleLocalOffset.y * cosR
            )
        }

        // 如果是旋转，计算初始触摸角度
        if activeHandle == .rotation {
            let touchInSuperview = gesture.location(in: superview)
            initialTouchAngle = atan2(
                touchInSuperview.y - initialCenter.y,
                touchInSuperview.x - initialCenter.x
            )
        }

        dragStartPoint = gesture.location(in: superview)

    case .changed:
        let currentPoint = gesture.location(in: superview)

        if let handle = activeHandle {
            switch handle {
            case .rotation:
                handleRotationImproved(currentPoint: currentPoint)
            default:
                handleResizeFixed(handle: handle, currentPoint: currentPoint)
            }
        } else {
            handleMoveImproved(currentPoint: currentPoint)
        }

    case .ended, .cancelled:
        syncToNode()
        if let initial = initialNode {
            onOperationEnd?(initial, shapeNode)
        }
        activeHandle = nil
        initialNode = nil

    default:
        break
    }
}

// MARK: - 修复后的缩放方法

/// 修复后的缩放方法 - 使用增量计算，避免第一帧跳变
private func handleResizeFixed(handle: ControlHandle, currentPoint: CGPoint) {
    guard let oppositeCorner = handle.oppositeCorner else { return }

    // Step 1: 计算锚点位置（对角点）
    let anchorLocalOffset = anchorOffset(for: oppositeCorner)
    let cosR = cos(initialRotation)
    let sinR = sin(initialRotation)

    let anchorInSuperview = CGPoint(
        x: initialCenter.x + anchorLocalOffset.x * cosR - anchorLocalOffset.y * sinR,
        y: initialCenter.y + anchorLocalOffset.x * sinR + anchorLocalOffset.y * cosR
    )

    // Step 2: 计算拖动增量（关键修复：使用 dragStartPoint 而非 anchorInSuperview）
    let dragDeltaX = currentPoint.x - dragStartPoint.x
    let dragDeltaY = currentPoint.y - dragStartPoint.y

    // Step 3: 将拖动增量逆旋转到本地坐标系
    let cosNegR = cos(-initialRotation)
    let sinNegR = sin(-initialRotation)
    let localDeltaX = dragDeltaX * cosNegR - dragDeltaY * sinNegR
    let localDeltaY = dragDeltaX * sinNegR + dragDeltaY * cosNegR

    // Step 4: 计算新尺寸（增量计算，不是绝对计算）
    // 根据拖动方向决定符号
    let widthSign: CGFloat = (handle == .topLeft || handle == .bottomLeft) ? -1 : 1
    let heightSign: CGFloat = (handle == .topLeft || handle == .topRight) ? -1 : 1

    var newWidth = initialBounds.width + localDeltaX * widthSign
    var newHeight = initialBounds.height + localDeltaY * heightSign

    // 最小尺寸限制
    let minSize: CGFloat = 20
    newWidth = max(newWidth, minSize)
    newHeight = max(newHeight, minSize)

    // Step 5: 计算新中心点
    // 锚点固定不动，中心点根据新尺寸移动
    let newHalfWidth = newWidth / 2
    let newHalfHeight = newHeight / 2

    // 新中心相对于锚点的本地偏移（注意符号与锚点相反）
    let newCenterLocalOffsetX = newHalfWidth * (-anchorLocalOffset.x / abs(anchorLocalOffset.x + 0.001))
    let newCenterLocalOffsetY = newHalfHeight * (-anchorLocalOffset.y / abs(anchorLocalOffset.y + 0.001))

    // 安全处理：如果锚点偏移接近0，使用默认方向
    let safeCenterOffsetX: CGFloat
    let safeCenterOffsetY: CGFloat

    if abs(anchorLocalOffset.x) < 0.001 {
        safeCenterOffsetX = 0
    } else {
        safeCenterOffsetX = anchorLocalOffset.x < 0 ? newHalfWidth : -newHalfWidth
    }

    if abs(anchorLocalOffset.y) < 0.001 {
        safeCenterOffsetY = 0
    } else {
        safeCenterOffsetY = anchorLocalOffset.y < 0 ? newHalfHeight : -newHalfHeight
    }

    // 将新中心偏移旋转回世界坐标系
    let newCenter = CGPoint(
        x: anchorInSuperview.x + safeCenterOffsetX * cosR - safeCenterOffsetY * sinR,
        y: anchorInSuperview.y + safeCenterOffsetX * sinR + safeCenterOffsetY * cosR
    )

    // Step 6: 更新视图（使用 bounds + center）
    bounds = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
    center = newCenter

    // Step 7: 保持旋转角度不变
    transform = CGAffineTransform(rotationAngle: initialRotation)

    // Step 8: 更新内容
    updateShapePath()
    updateSelectionAppearance()
}

/// 计算控制点（拖动的那个角）相对于中心的偏移量
private func handleOffset(for handle: ControlHandle) -> CGPoint {
    let halfWidth = initialBounds.width / 2
    let halfHeight = initialBounds.height / 2

    switch handle {
    case .topLeft:
        return CGPoint(x: -halfWidth, y: -halfHeight)
    case .topRight:
        return CGPoint(x: halfWidth, y: -halfHeight)
    case .bottomRight:
        return CGPoint(x: halfWidth, y: halfHeight)
    case .bottomLeft:
        return CGPoint(x: -halfWidth, y: halfHeight)
    case .rotation:
        return .zero
    }
}
```

#### 关键改动说明

| 改动 | 原因 |
|-----|------|
| 新增 `initialHandlePosition` 属性 | 保存被拖动角点的实际位置，用于精确计算 |
| 使用 `currentPoint - dragStartPoint` 计算增量 | 避免第一帧使用绝对位置导致的跳变 |
| 增量乘以 `widthSign/heightSign` 加到初始尺寸 | 正确的增量式计算，而非绝对值计算 |
| 简化锚点方向判断逻辑 | 使用锚点偏移量的符号来确定中心点移动方向 |

---

## 四、方案对比

### 4.1 问题一的两个备选方案

| 方案 | 描述 | 优点 | 缺点 |
|-----|------|------|------|
| **方案 A (推荐)** | 使用 Canvas 视图替代 Path + .position() | 代码简洁，坐标系统一 | 需要理解 Canvas API |
| 方案 B | 在预览时也做坐标转换 | 保持原有代码结构 | 需要同时修改多处，易出错 |

### 4.2 问题二的方案演进

| 版本 | 做法 | 问题 |
|-----|------|------|
| v5 之前 | 使用 frame | transform 时 frame 不可靠 |
| v5 | 使用 center + bounds，但绝对距离计算 | 第一帧跳变 |
| **v6 (本方案)** | 使用 center + bounds + 增量计算 | 解决跳变 |

---

## 五、实施步骤

### Step 1: 修复形状预览偏移 (30 分钟)

1. 备份 `ShapeDrawingView.swift`
2. 使用 Canvas 视图重写 `ShapeDrawingView`
3. 在 Simulator 中测试绘制矩形、圆形、三角形
4. 验证预览位置与手指位置一致

### Step 2: 修复缩放跳变 (1 小时)

1. 备份 `SelectableShapeView.swift`
2. 添加 `initialHandlePosition` 属性
3. 修改 `handlePan` 方法中的 `.began` 分支
4. 添加新的 `handleResizeFixed` 方法
5. 添加 `handleOffset` 辅助方法
6. 在 `.changed` 分支中调用 `handleResizeFixed`

### Step 3: 综合测试 (1 小时)

详见下方测试用例

### Step 4: 代码清理 (30 分钟)

1. 删除旧的 `handleResizeImproved` 方法（或标记 deprecated）
2. 确保代码注释清晰
3. 检查是否有冗余代码

---

## 六、测试用例

### 6.1 形状预览测试

| 用例 | 操作 | 预期结果 |
|-----|------|---------|
| T1-1 | 选择矩形工具，从点 A 拖到点 B | 绘制过程中，矩形预览的左上角精确在 A 点 |
| T1-2 | 选择圆形工具，从点 A 拖到点 B | 绘制过程中，圆形预览包含在 A-B 定义的矩形内 |
| T1-3 | 快速绘制多个形状 | 每个形状的预览位置都正确，释放后无跳动 |
| T1-4 | 在画布缩放为 150% 时绘制 | 预览位置仍然正确 |
| T1-5 | 在画布平移后绘制 | 预览位置仍然正确 |

### 6.2 缩放跳变测试

| 用例 | 操作 | 预期结果 |
|-----|------|---------|
| T2-1 | 选中矩形，点击右下角控制点 | 形状不应有任何跳变（即使不拖动） |
| T2-2 | 选中矩形，轻轻触碰右下角后松开 | 形状尺寸完全不变 |
| T2-3 | 选中矩形，拖动右下角向右下方 10px | 形状宽高各增加约 10px，无跳变 |
| T2-4 | 选中矩形，拖动左上角向左上方 | 形状放大，右下角锚点固定不动 |
| T2-5 | 选中已旋转 45 度的矩形，拖动角点 | 缩放平滑，旋转角度保持不变 |
| T2-6 | 快速点击不同角点 | 无跳变，形状稳定 |

### 6.3 综合测试

| 用例 | 操作 | 预期结果 |
|-----|------|---------|
| T3-1 | 绘制一个矩形 -> 选中 -> 缩放 -> 撤销 | 所有操作流畅，撤销恢复正确尺寸 |
| T3-2 | 绘制 -> 旋转 -> 缩放 -> 移动 | 所有变换操作互不影响 |
| T3-3 | 连续快速绘制 5 个形状 | 每个形状位置正确，无预览偏移 |

---

## 七、参考资料

### 官方文档
- [Apple UIView.transform](https://developer.apple.com/documentation/uikit/uiview/1622459-transform) - Transform 应用于 bounds 中心
- [Apple UIView.anchorPoint](https://developer.apple.com/documentation/uikit/uiview/4051982-anchorpoint) - 锚点默认为 (0.5, 0.5)

### 社区最佳实践
- [Hacking with Swift - Anchor Point](https://www.hackingwithswift.com/example-code/calayer/how-to-change-a-views-anchor-point-without-moving-it) - 修改锚点不移动视图
- [Swift by Sundell - Bounds and Transforms](https://www.swiftbysundell.com/tips/uiview-bounds-and-transforms/) - Bounds 在 Transform 下保持不变
- [HackerNoon - Mastering UIView Geometry](https://hackernoon.com/mastering-uiview-geometry-a-dive-into-uikits-foundational-class-and-geometry-concepts-for-ios) - Frame vs Bounds vs Center
- [InformIT - UIView Transforms](https://www.informit.com/articles/article.aspx?p=1951182) - 详解 Transform 影响

### 开源项目参考
- [DragRotateScaleView](https://github.com/yokurin/DragRotateScaleView) - 拖拽旋转缩放实现
- [RKUserResizableView](https://github.com/RajatJain4061/RKUserResizableView) - 用户可调整大小的视图
- [TransformableView](https://github.com/Rep2/TransformableView) - 协议化的变换视图

---

## 八、风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|-----|--------|-----|---------|
| Canvas API 在旧系统不支持 | 低 | 高 | Canvas 在 iOS 15+ 可用，项目要求 iPadOS 17+ |
| 坐标计算仍有边界情况 | 中 | 中 | 详尽的测试用例覆盖各种角度和位置 |
| 性能影响 | 低 | 低 | Canvas 性能优秀，增量计算比绝对计算更轻量 |

---

## 九、回滚方案

如果上线后发现严重问题：

1. **问题一回滚**：将 `ShapeDrawingView.swift` 恢复为原版本
2. **问题二回滚**：将 `SelectableShapeView.swift` 恢复为原版本（v5）
3. 两个问题独立，可以分别回滚

---

## 十、后续优化 (本次不做)

1. 添加等比例缩放模式（锁定宽高比）
2. 添加 45 度角旋转吸附
3. 添加对齐辅助线
4. 优化控制点触摸反馈（按下时高亮）
5. 添加键盘快捷键微调位置

---

## 十一、附录：代码改动清单

### 需要修改的文件

1. **ShapeDrawingView.swift**
   - 完全重写 body，使用 Canvas 替代 Path + .position()
   - 移动辅助方法到 View 内部

2. **SelectableShapeView.swift**
   - 添加 `initialHandlePosition` 属性
   - 修改 `handlePan` 方法的 `.began` 分支
   - 添加 `handleResizeFixed` 方法
   - 添加 `handleOffset` 辅助方法
   - 在 `.changed` 中调用新方法

### 不需要修改的文件

- NativeEditorView.swift (调用方式不变)
- ShapeLayerNode.swift (数据模型不变)
- CanvasStateManager.swift (状态管理不变)
- NativeCanvasView.swift (创建逻辑不变)
