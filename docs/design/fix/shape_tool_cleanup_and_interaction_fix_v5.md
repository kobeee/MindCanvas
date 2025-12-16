# 图形工具清理与交互优化方案 v5.0

## 文档信息
- **版本**: v5.0
- **日期**: 2025-12-16
- **优先级**: P0 (交互体验核心问题)
- **预估工作量**: 2-3 小时

---

## 一、问题概述

### 1.1 工具栏清理
**当前状态**: 底部工具栏显示了 9 个工具，其中存在冗余和未实现的工具

**问题**:
- `arrow` 工具：箭头已作为形状类型移入图形工具选择器，不应在主工具栏独立显示
- `annotation` 工具：图标为 `bubble.left`，功能未实现，用户困惑
- `text` 工具：功能未完整实现

### 1.2 图形线条颜色
**当前状态**: 形状默认颜色为 `#007AFF` (系统蓝色)

**问题**: 与画笔默认颜色 (黑色) 不一致，视觉上不统一

### 1.3 控制点交互
**当前状态**: 角点缩放和旋转手柄已实现，但交互体验差

**问题**:
- **缩放不丝滑**: 拖动角点时，形状尺寸变化跳跃，难以精准控制
- **旋转改变尺寸**: 旋转时形状尺寸会意外改变

---

## 二、问题根因分析

### 2.1 工具栏冗余
**代码位置**: [CanvasTool.swift:82-87](src/MindCanvas/MindCanvas/Models/Canvas/CanvasTool.swift#L82-L87)

```swift
var isMainToolbarTool: Bool {
    switch self {
    case .select, .pan, .pen, .eraser, .arrow, .rectangle, .text, .annotation, .image:
        return true
    }
}
```

**根因**: `arrow`, `text`, `annotation` 被标记为主工具栏工具，但：
- `arrow` 已整合到 `rectangle` 工具的形状选择器
- `text` 和 `annotation` 功能未完整实现

### 2.2 颜色不一致
**代码位置**: [CanvasStateManager.swift:269](src/MindCanvas/MindCanvas/ViewModels/CanvasStateManager.swift#L269)

```swift
var rectangleColor: String = "#007AFF"  // 蓝色
```

**根因**: 形状默认颜色硬编码为蓝色，而 PencilKit 画笔默认为黑色

### 2.3 缩放不丝滑

**代码位置**: [SelectableShapeView.swift:360-420](src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift#L360-L420)

```swift
private func handleResize(handle: ControlHandle, currentPoint: CGPoint) {
    // ...
    // 问题1: 使用 abs() 导致符号丢失
    var newWidth = abs(localDx)
    var newHeight = abs(localDy)

    // 问题2: 每次都重新计算 frame，没有基于 initialFrame 做增量计算
    frame = CGRect(
        x: newCenterX - newWidth / 2,
        y: newCenterY - newHeight / 2,
        width: newWidth,
        height: newHeight
    )
}
```

**根因分析**:

1. **坐标转换累积误差**: 涉及多次三角函数计算 (`cos`, `sin`, `atan2`)，浮点精度累积导致抖动
2. **锚点计算复杂**: 旋转状态下的锚点位置计算需要考虑旋转矩阵变换
3. **没有使用初始状态的增量计算**: 每帧都从 currentPoint 重新计算，而非基于 initialFrame 做差值

### 2.4 旋转改变尺寸

**代码位置**: [SelectableShapeView.swift:422-438](src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift#L422-L438)

```swift
private func handleRotation(currentPoint: CGPoint) {
    let centerInSuperview = CGPoint(
        x: frame.midX,  // 问题: frame 在有 transform 时不可靠
        y: frame.midY
    )
    // ...
    transform = CGAffineTransform(rotationAngle: rotation)
}
```

**根因分析**:

1. **使用 `frame` 而非 `center`**: 当视图有 transform 时，`frame` 是不可靠的 (Apple 文档明确指出)
2. **旋转操作没有保持 bounds 不变**: transform 会影响 frame 计算
3. **缺少初始角度的增量计算**: 应该基于手势开始时的角度做增量，而非直接设置绝对角度

---

## 三、解决方案

### 3.1 工具栏清理

#### 3.1.1 修改 CanvasTool.swift

```swift
// 文件: src/MindCanvas/MindCanvas/Models/Canvas/CanvasTool.swift

enum CanvasTool: String, CaseIterable, Identifiable {
    case select = "select"          // 选择工具
    case pan = "pan"                // 平移工具
    case pen = "pen"                // 画笔工具
    case eraser = "eraser"          // 橡皮擦
    case arrow = "arrow"            // 箭头工具 (内部使用，不在工具栏显示)
    case rectangle = "rectangle"    // 图形工具
    case image = "image"            // 图片工具
    // 移除 text 和 annotation，待功能完整后再添加

    /// 是否在主工具栏显示
    var isMainToolbarTool: Bool {
        switch self {
        case .select, .pan, .pen, .eraser, .rectangle, .image:
            return true
        case .arrow:  // arrow 作为 rectangle 的子类型，不独立显示
            return false
        }
    }
}
```

#### 3.1.2 清理后的工具栏布局

| 位置 | 工具 | 图标 | 说明 |
|-----|------|------|------|
| 1 | select | arrow.up.left.and.arrow.down.right | 选择工具 |
| 2 | pan | hand.raised | 平移工具 |
| 3 | pen | pencil | 画笔工具 |
| 4 | eraser | eraser | 橡皮擦 |
| 5 | rectangle | rectangle | 图形工具 (点击弹出选择器) |
| 6 | image | photo | 图片工具 |

**共 6 个工具，整洁清晰**

### 3.2 统一图形线条颜色

#### 3.2.1 修改 CanvasStateManager.swift

```swift
// 文件: src/MindCanvas/MindCanvas/ViewModels/CanvasStateManager.swift

// MARK: - 图形工具 (改名为 shape，更准确)

/// 图形描边颜色 - 与画笔保持一致，默认黑色
var shapeStrokeColor: String = "#000000"

/// 图形线宽
var shapeLineWidth: CGFloat = 2  // 从 3 改为 2，更细腻

/// 图形是否填充
var shapeIsFilled: Bool = false

// 同时更新 setter 方法名称
func setShapeStrokeColor(_ color: String) {
    shapeStrokeColor = color
}

func setShapeLineWidth(_ width: CGFloat) {
    shapeLineWidth = width
}

func setShapeIsFilled(_ filled: Bool) {
    shapeIsFilled = filled
}
```

#### 3.2.2 更新 NativeEditorView.swift 中的引用

将所有 `rectangleColor` 改为 `shapeStrokeColor`，`rectangleLineWidth` 改为 `shapeLineWidth`，`rectangleIsFilled` 改为 `shapeIsFilled`

### 3.3 重构控制点交互 (核心修复)

#### 3.3.1 设计原则

参考 [Hacking with Swift](https://www.hackingwithswift.com/example-code/calayer/how-to-change-a-views-anchor-point-without-moving-it) 和 [Apple 文档](https://developer.apple.com/documentation/uikit/uiview/1622459-transform) 的最佳实践：

1. **旋转时使用 `center` + `bounds`，而非 `frame`**
2. **缩放使用增量计算，而非绝对计算**
3. **分离缩放和旋转的 transform 处理**

#### 3.3.2 重写 SelectableShapeView 核心方法

```swift
// 文件: src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift

// MARK: - 属性扩展

// 初始状态 (手势开始时保存)
private var initialBounds: CGRect = .zero
private var initialCenter: CGPoint = .zero
private var initialRotation: CGFloat = 0
private var initialTouchAngle: CGFloat = 0  // 旋转手势: 初始触摸角度

// MARK: - 手势开始

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
                handleResizeImproved(handle: handle, currentPoint: currentPoint)
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

// MARK: - 改进的移动方法

private func handleMoveImproved(currentPoint: CGPoint) {
    let dx = currentPoint.x - dragStartPoint.x
    let dy = currentPoint.y - dragStartPoint.y

    // 直接修改 center，保持 bounds 不变
    center = CGPoint(
        x: initialCenter.x + dx,
        y: initialCenter.y + dy
    )
}

// MARK: - 改进的缩放方法

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
    let dx = currentPoint.x - anchorInSuperview.x
    let dy = currentPoint.y - anchorInSuperview.y

    // Step 3: 将拖动向量逆旋转，得到在未旋转坐标系中的位移
    let cosNegR = cos(-initialRotation)
    let sinNegR = sin(-initialRotation)
    let localDx = dx * cosNegR - dy * sinNegR
    let localDy = dx * sinNegR + dy * cosNegR

    // Step 4: 计算新尺寸 (保持符号，根据拖动方向确定)
    let widthSign: CGFloat = (handle == .topLeft || handle == .bottomLeft) ? -1 : 1
    let heightSign: CGFloat = (handle == .topLeft || handle == .topRight) ? -1 : 1

    var newWidth = initialBounds.width + localDx * widthSign
    var newHeight = initialBounds.height + localDy * heightSign

    // 最小尺寸限制
    newWidth = max(newWidth, 20)
    newHeight = max(newHeight, 20)

    // Step 5: 计算新的中心点 (锚点固定，中心点移动)
    let newCenterLocalOffset = CGPoint(
        x: (newWidth / 2) * widthSign,
        y: (newHeight / 2) * heightSign
    )

    // 将新中心点偏移量旋转回 superview 坐标系
    let newCenter = CGPoint(
        x: anchorInSuperview.x + newCenterLocalOffset.x * cosR - newCenterLocalOffset.y * sinR,
        y: anchorInSuperview.y + newCenterLocalOffset.x * sinR + newCenterLocalOffset.y * cosR
    )

    // Step 6: 更新视图 (使用 bounds + center，不改变 transform)
    bounds = CGRect(origin: .zero, width: newWidth, height: newHeight)
    center = newCenter

    // Step 7: 保持旋转角度不变
    transform = CGAffineTransform(rotationAngle: initialRotation)

    // Step 8: 更新内容
    updateShapePath()
    updateSelectionAppearance()
}

/// 计算锚点相对于中心的偏移量
private func anchorOffset(for corner: ControlHandle) -> CGPoint {
    let halfWidth = initialBounds.width / 2
    let halfHeight = initialBounds.height / 2

    switch corner {
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

// MARK: - 改进的旋转方法

private func handleRotationImproved(currentPoint: CGPoint) {
    // 关键: 使用 initialCenter 而非 frame.mid
    // 因为 frame 在有 transform 时是不可靠的

    // 计算当前触摸角度
    let currentTouchAngle = atan2(
        currentPoint.y - initialCenter.y,
        currentPoint.x - initialCenter.x
    )

    // 计算角度增量
    let deltaAngle = currentTouchAngle - initialTouchAngle

    // 新旋转角度 = 初始旋转 + 增量
    let newRotation = initialRotation + deltaAngle

    // 只修改 transform，不改变 bounds 和 center
    transform = CGAffineTransform(rotationAngle: newRotation)

    // 更新选中外观 (控制点位置需要随旋转更新)
    updateSelectionAppearance()
}

// MARK: - 同步到数据模型

private func syncToNode() {
    let currentRotation = atan2(transform.b, transform.a)

    // 从 center 和 bounds 重建 frame
    let newFrame = CGRect(
        x: center.x - bounds.width / 2,
        y: center.y - bounds.height / 2,
        width: bounds.width,
        height: bounds.height
    )

    shapeNode = shapeNode.updated(
        frame: newFrame,
        rotation: currentRotation
    )
    onNodeUpdated?(shapeNode)
}

// MARK: - 从数据模型更新视图

func updateFromNode() {
    // 重置 transform 为 identity
    transform = .identity

    // 设置 bounds 和 center
    bounds = CGRect(origin: .zero, width: shapeNode.frame.width, height: shapeNode.frame.height)
    center = CGPoint(x: shapeNode.frame.midX, y: shapeNode.frame.midY)

    // 应用旋转
    transform = CGAffineTransform(rotationAngle: shapeNode.rotation)

    updateShapePath()
    updateSelectionAppearance()
}
```

#### 3.3.3 核心改进点说明

| 改进项 | 之前 | 之后 | 原因 |
|--------|-----|------|-----|
| 视图状态表示 | `frame` | `center` + `bounds` | 有 transform 时 frame 不可靠 |
| 旋转计算 | 绝对角度 | 初始角度 + 增量 | 避免跳跃，更平滑 |
| 缩放计算 | 每帧重算 | 基于初始状态增量 | 避免累积误差 |
| 锚点处理 | 复杂的位置计算 | 偏移量 + 旋转矩阵 | 逻辑更清晰 |

---

## 四、实施步骤

### Step 1: 清理工具栏 (15 分钟)

1. 修改 `CanvasTool.swift` 的 `isMainToolbarTool` 属性
2. 验证编译通过
3. 在模拟器确认工具栏只显示 6 个工具

### Step 2: 统一颜色配置 (15 分钟)

1. 修改 `CanvasStateManager.swift` 中的默认颜色值
2. 全局搜索替换变量名 (`rectangleColor` -> `shapeStrokeColor` 等)
3. 验证新建形状默认为黑色边框

### Step 3: 重构控制点交互 (1.5-2 小时)

1. 备份当前 `SelectableShapeView.swift`
2. 添加新的属性声明
3. 重写 `handlePan` 方法
4. 重写 `handleMoveImproved` 方法
5. 重写 `handleResizeImproved` 方法
6. 重写 `handleRotationImproved` 方法
7. 更新 `syncToNode` 方法
8. 更新 `updateFromNode` 方法

### Step 4: 测试验证 (30 分钟)

详见下方测试用例

---

## 五、测试用例

### 5.1 工具栏测试

| 用例 | 操作 | 预期结果 |
|-----|------|---------|
| T1-1 | 进入编辑器，查看底部工具栏 | 显示 6 个工具: 选择、平移、画笔、橡皮擦、图形、图片 |
| T1-2 | 点击图形工具 | 弹出形状选择器，包含直线、箭头、矩形等 9 种形状 |

### 5.2 颜色测试

| 用例 | 操作 | 预期结果 |
|-----|------|---------|
| T2-1 | 选择图形工具，拖出一个矩形 | 矩形边框为黑色 (#000000)，无填充 |
| T2-2 | 用画笔工具画一笔 | 笔画为黑色，与形状边框颜色一致 |

### 5.3 缩放交互测试

| 用例 | 操作 | 预期结果 |
|-----|------|---------|
| T3-1 | 选中一个矩形，拖动右下角 | 矩形平滑缩放，左上角锚点固定不动 |
| T3-2 | 选中一个已旋转的矩形，拖动右下角 | 矩形平滑缩放，对角锚点固定，旋转角度不变 |
| T3-3 | 快速拖动角点 | 缩放跟手，无跳跃或抖动 |
| T3-4 | 将矩形缩小到接近 20x20 | 达到最小尺寸后停止缩小，不会变形 |

### 5.4 旋转交互测试

| 用例 | 操作 | 预期结果 |
|-----|------|---------|
| T4-1 | 选中一个矩形，拖动旋转手柄顺时针转动 | 矩形绕中心顺时针旋转，尺寸不变 |
| T4-2 | 选中一个矩形，拖动旋转手柄逆时针转动 | 矩形绕中心逆时针旋转，尺寸不变 |
| T4-3 | 快速旋转 360 度以上 | 旋转跟手，无跳跃 |
| T4-4 | 旋转一个非正方形矩形 | 宽高比保持不变 |

### 5.5 撤销测试

| 用例 | 操作 | 预期结果 |
|-----|------|---------|
| T5-1 | 缩放一个形状后撤销 | 形状恢复到缩放前的尺寸 |
| T5-2 | 旋转一个形状后撤销 | 形状恢复到旋转前的角度 |

---

## 六、参考资料

- [Apple UIView Transform 文档](https://developer.apple.com/documentation/uikit/uiview/1622459-transform)
- [Hacking with Swift - 修改 anchorPoint 不移动视图](https://www.hackingwithswift.com/example-code/calayer/how-to-change-a-views-anchor-point-without-moving-it)
- [Swift by Sundell - UIView bounds 与 transforms](https://www.swiftbysundell.com/tips/uiview-bounds-and-transforms/)
- [GitHub - SPUserResizableView](https://github.com/spoletto/SPUserResizableView)
- [GitHub - DragRotateScaleView](https://github.com/yokurin/DragRotateScaleView)

---

## 七、风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|-----|--------|-----|---------|
| 重构引入新 bug | 中 | 高 | 完整执行测试用例，备份原代码 |
| 与箭头视图不一致 | 低 | 中 | 检查 SelectableArrowView 是否需要同步修改 |
| 撤销系统不兼容 | 低 | 中 | 确认 CanvasAction 使用 frame 格式正确 |

---

## 八、回滚方案

如果上线后发现严重问题：

1. Git 回滚到本次修改前的 commit
2. 或者单独回滚 `SelectableShapeView.swift` 文件
3. 工具栏和颜色配置修改影响小，可以保留

---

## 九、后续优化 (本次不做)

1. 添加等比例缩放模式 (按住某键)
2. 添加 45 度角吸附
3. 添加对齐辅助线
4. 添加键盘方向键微调
