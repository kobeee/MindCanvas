# 图形工具关键问题修复方案 v4.0（控制点交互）

## 文档信息

- **版本**: v4.0
- **日期**: 2025-12-15
- **状态**: 待实施
- **优先级**: P0 (阻塞性问题)
- **前置文档**: shape_tool_fixes_v3.md (已实施但问题未解决)

---

## 一、问题回顾

v3.0 方案实施后，用户反馈仍存在以下关键问题：

| # | 问题 | 现象 | 严重程度 |
|---|------|------|---------|
| 1 | 直线拖动后变箭头 | 选择直线工具绘制直线后，用选择工具拖动时，直线突然变成箭头 | P0 |
| 2 | 形状绘制偏移 | 在画布上拖动绘制形状时位置偏移，手指释放后回到初始位置 | P1 |
| 3 | 形状无法缩放旋转 | 选择工具下，形状对象只能移动，缩放和旋转无效 | P1 |

**重要澄清**：
- 缩放/旋转的预期交互方式是**控制点 (Handle)**，而不是双指手势
- 角点拖动 → 缩放
- 旋转手柄（角点上方的圆点）→ 旋转
- 参考 Figma/Canva/Keynote 的交互模式

---

## 二、根因分析

### 2.1 问题1：直线拖动后变箭头

**定位文件**: `SelectableArrowView.swift` 第 198-204 行

**问题代码**:
```swift
case .changed:
    let translation = gesture.translation(in: superview)
    center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
    gesture.setTranslation(.zero, in: superview)

    let offset = translation
    arrowNode = ArrowLayerNode(
        startPoint: CGPoint(x: arrowNode.startPoint.x + offset.x, y: arrowNode.startPoint.y + offset.y),
        endPoint: CGPoint(x: arrowNode.endPoint.x + offset.x, y: arrowNode.endPoint.y + offset.y),
        color: arrowNode.color,
        lineWidth: arrowNode.lineWidth,
        zIndex: arrowNode.zIndex
        // BUG: 丢失了 hasArrowHead、rotation、scale 属性！
    )
```

**根因**:
- `handlePan` 在 `.changed` 状态中，通过直接调用 `ArrowLayerNode(...)` 构造函数创建新实例
- 构造函数的 `hasArrowHead` 参数有默认值 `true`
- 原本 `hasArrowHead = false` 的直线，因为没有传递该属性，变成了 `hasArrowHead = true` 的箭头

---

### 2.2 问题2：形状绘制偏移

**根因**: SwiftUI 手势层与 UIKit 画布层的坐标系统分离

详细分析见 v3.0 方案，此处不再重复。核心问题是预览和创建使用不同的坐标系。

---

### 2.3 问题3：形状无法缩放旋转

**根因**: **根本没有实现控制点交互！**

当前代码使用的是 **双指手势**（UIPinchGestureRecognizer、UIRotationGestureRecognizer），而用户期望的是 **控制点交互**：

```
用户期望的交互（Figma/Canva 模式）:

        ○ ← 旋转手柄
        |
    ●───────────●
    |           |  ← 角点控制缩放
    |   形状    |
    |           |
    ●───────────●

控制点功能：
- 4个角点：拖动进行缩放
- 旋转手柄：形状上方的圆点，拖动进行旋转
- 选中边框：虚线边框显示选中状态
```

**现有代码问题**:
1. `SelectableShapeView` 没有绘制控制点
2. 没有控制点的 hitTest 逻辑
3. 没有控制点的拖动处理逻辑
4. 双指手势在单指设备（iPad + Apple Pencil）上很难操作

---

## 三、解决方案

### 3.1 架构设计：控制点系统

```
┌─────────────────────────────────────────────────────────────┐
│                    SelectableShapeView                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                                                       │  │
│  │            ○ ← rotationHandle (旋转手柄)             │  │
│  │            │                                          │  │
│  │    ●───────┴───────●                                  │  │
│  │    │               │    cornerHandles[4]              │  │
│  │    │    shapeLayer │    (角点控制缩放)                │  │
│  │    │               │                                  │  │
│  │    ●───────────────●                                  │  │
│  │                                                       │  │
│  │    selectionBorder (选中边框)                         │  │
│  │                                                       │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  手势处理:                                                   │
│  - panGesture: 整体移动 或 控制点拖动                        │
│  - tapGesture: 选中                                         │
│                                                             │
│  hitTest 逻辑:                                               │
│  1. 先检查是否点击旋转手柄 → 进入旋转模式                     │
│  2. 再检查是否点击角点 → 进入缩放模式                         │
│  3. 最后检查是否点击形状本身 → 进入移动模式                   │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 控制点交互状态机

```
                    ┌─────────┐
                    │  Idle   │
                    └────┬────┘
                         │ tap 选中
                         ▼
                    ┌─────────┐
           ┌────────│ Selected │────────┐
           │        └────┬────┘        │
           │             │             │
    drag角点│      drag形状│      drag旋转│
           │             │        手柄 │
           ▼             ▼             ▼
    ┌──────────┐  ┌──────────┐  ┌──────────┐
    │ Resizing │  │  Moving  │  │ Rotating │
    └──────────┘  └──────────┘  └──────────┘
```

---

## 四、详细实现方案

### 4.1 修复1：直线拖动变箭头 (P0, 15分钟)

**文件**: `SelectableArrowView.swift`

**修改位置**: 第 190-206 行，`handlePan` 方法的 `.changed` 分支

```swift
// 修改前
case .changed:
    let translation = gesture.translation(in: superview)
    center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
    gesture.setTranslation(.zero, in: superview)

    let offset = translation
    arrowNode = ArrowLayerNode(
        startPoint: CGPoint(x: arrowNode.startPoint.x + offset.x, y: arrowNode.startPoint.y + offset.y),
        endPoint: CGPoint(x: arrowNode.endPoint.x + offset.x, y: arrowNode.endPoint.y + offset.y),
        color: arrowNode.color,
        lineWidth: arrowNode.lineWidth,
        zIndex: arrowNode.zIndex
    )
    updateFromNode()
    onNodeUpdated?(arrowNode)

// 修改后
case .changed:
    let translation = gesture.translation(in: superview)
    center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
    gesture.setTranslation(.zero, in: superview)

    // 关键修复：使用 updated() 保留所有属性（包括 hasArrowHead）
    arrowNode = arrowNode.updated(
        startPoint: CGPoint(
            x: arrowNode.startPoint.x + translation.x,
            y: arrowNode.startPoint.y + translation.y
        ),
        endPoint: CGPoint(
            x: arrowNode.endPoint.x + translation.x,
            y: arrowNode.endPoint.y + translation.y
        )
    )
    updateFromNode()
    onNodeUpdated?(arrowNode)
```

---

### 4.2 修复2：形状绘制偏移 (P1, 30分钟)

采用 **统一到 UIKit 层** 的方案，详见之前的 v4 方案文档。核心思路：

1. 移除 SwiftUI 预览层
2. 在 `NativeCanvasView` 中添加 UIKit 预览方法
3. 手势回调只传递坐标，实际渲染在 UIKit 层完成

---

### 4.3 修复3：实现控制点交互 (P1, 2-3小时)

这是本方案的**核心重构**，需要完全重写 `SelectableShapeView`。

#### 4.3.1 控制点枚举定义

```swift
/// 控制点类型
enum ControlHandle: Int, CaseIterable {
    case topLeft = 0
    case topRight = 1
    case bottomRight = 2
    case bottomLeft = 3
    case rotation = 4  // 旋转手柄

    /// 控制点相对于边界框的位置
    func position(in bounds: CGRect, rotationHandleOffset: CGFloat = 30) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: bounds.minX, y: bounds.minY)
        case .topRight:
            return CGPoint(x: bounds.maxX, y: bounds.minY)
        case .bottomRight:
            return CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .bottomLeft:
            return CGPoint(x: bounds.minX, y: bounds.maxY)
        case .rotation:
            return CGPoint(x: bounds.midX, y: bounds.minY - rotationHandleOffset)
        }
    }

    /// 缩放时的锚点（对角点）
    var oppositeCorner: ControlHandle? {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomRight: return .topLeft
        case .bottomLeft: return .topRight
        case .rotation: return nil
        }
    }
}
```

#### 4.3.2 重写 SelectableShapeView

**文件**: `Views/Editor/Canvas/SelectableShapeView.swift`

**完整重写**:

```swift
import UIKit
import SwiftUI

/// 可选择的通用形状视图（支持控制点交互）
class SelectableShapeView: UIView {

    // MARK: - Properties

    var shapeNode: ShapeLayerNode {
        didSet {
            updateFromNode()
        }
    }

    // 图层
    private let shapeLayer = CAShapeLayer()
    private let selectionBorder = CAShapeLayer()
    private var cornerHandleLayers: [CAShapeLayer] = []
    private let rotationHandleLayer = CAShapeLayer()
    private let rotationLinelayer = CAShapeLayer()

    // 控制点配置
    private let handleSize: CGFloat = 12
    private let rotationHandleOffset: CGFloat = 30

    // 选中状态
    var isSelected: Bool = false {
        didSet {
            updateSelectionAppearance()
        }
    }

    // 当前拖动的控制点
    private var activeHandle: ControlHandle?
    private var dragStartPoint: CGPoint = .zero
    private var initialFrame: CGRect = .zero
    private var initialRotation: Double = 0

    // 手势
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    // 回调
    var onNodeUpdated: ((ShapeLayerNode) -> Void)?
    var onSelected: ((UUID) -> Void)?
    var onOperationStart: ((ShapeLayerNode) -> Void)?
    var onOperationEnd: ((ShapeLayerNode, ShapeLayerNode) -> Void)?

    // MARK: - Initialization

    init(shapeNode: ShapeLayerNode) {
        self.shapeNode = shapeNode
        super.init(frame: shapeNode.frame)
        setupViews()
        setupGestures()
        updateFromNode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = .clear
        clipsToBounds = false

        // 形状图层
        shapeLayer.fillColor = shapeNode.isFilled
            ? UIColor(Color.fromHex(shapeNode.color) ?? .black).cgColor
            : UIColor.clear.cgColor
        shapeLayer.strokeColor = UIColor(Color.fromHex(shapeNode.color) ?? .black).cgColor
        shapeLayer.lineWidth = shapeNode.lineWidth
        layer.addSublayer(shapeLayer)

        // 选中边框
        selectionBorder.strokeColor = UIColor.systemBlue.cgColor
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.lineWidth = 1.5
        selectionBorder.lineDashPattern = [4, 4]
        selectionBorder.isHidden = true
        layer.addSublayer(selectionBorder)

        // 旋转手柄连接线
        rotationLinelayer.strokeColor = UIColor.systemBlue.cgColor
        rotationLinelayer.fillColor = UIColor.clear.cgColor
        rotationLinelayer.lineWidth = 1.5
        rotationLinelayer.isHidden = true
        layer.addSublayer(rotationLinelayer)

        // 4个角点控制点
        for _ in 0..<4 {
            let handleLayer = CAShapeLayer()
            handleLayer.fillColor = UIColor.white.cgColor
            handleLayer.strokeColor = UIColor.systemBlue.cgColor
            handleLayer.lineWidth = 2
            handleLayer.isHidden = true
            layer.addSublayer(handleLayer)
            cornerHandleLayers.append(handleLayer)
        }

        // 旋转手柄（圆形）
        rotationHandleLayer.fillColor = UIColor.white.cgColor
        rotationHandleLayer.strokeColor = UIColor.systemBlue.cgColor
        rotationHandleLayer.lineWidth = 2
        rotationHandleLayer.isHidden = true
        layer.addSublayer(rotationHandleLayer)
    }

    private func setupGestures() {
        // 点击选中
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        // 拖拽（移动 / 控制点操作）
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(panGesture)
    }

    // MARK: - Node Sync

    func updateFromNode() {
        frame = shapeNode.frame
        transform = CGAffineTransform(rotationAngle: shapeNode.rotation)
        updateShapePath()
        updateSelectionAppearance()
    }

    private func updateShapePath() {
        let rect = bounds
        let path: UIBezierPath

        switch shapeNode.shapeType {
        case .rectangle:
            path = UIBezierPath(roundedRect: rect, cornerRadius: 4)
        case .roundedRectangle:
            path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
        case .circle:
            let diameter = min(rect.width, rect.height)
            let circleRect = CGRect(
                x: (rect.width - diameter) / 2,
                y: (rect.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            path = UIBezierPath(ovalIn: circleRect)
        case .triangle:
            path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            path.close()
        case .diamond:
            path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: 0, y: rect.midY))
            path.close()
        case .star:
            path = createStarPath(in: rect, points: 5)
        case .hexagon:
            path = createPolygonPath(in: rect, sides: 6)
        case .line, .arrow:
            path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }

        shapeLayer.path = path.cgPath
    }

    private func syncToNode() {
        shapeNode = shapeNode.updated(
            frame: frame,
            rotation: atan2(transform.b, transform.a)
        )
        onNodeUpdated?(shapeNode)
    }

    // MARK: - Selection Appearance

    private func updateSelectionAppearance() {
        let showHandles = isSelected

        selectionBorder.isHidden = !showHandles
        rotationLinelayer.isHidden = !showHandles
        rotationHandleLayer.isHidden = !showHandles
        cornerHandleLayers.forEach { $0.isHidden = !showHandles }

        guard showHandles else { return }

        // 更新选中边框
        let borderRect = bounds
        selectionBorder.path = UIBezierPath(rect: borderRect).cgPath

        // 更新角点控制点
        let corners: [ControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        for (index, corner) in corners.enumerated() {
            let position = corner.position(in: bounds)
            let handleRect = CGRect(
                x: position.x - handleSize / 2,
                y: position.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            cornerHandleLayers[index].path = UIBezierPath(rect: handleRect).cgPath
        }

        // 更新旋转手柄连接线
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
        linePath.addLine(to: CGPoint(x: bounds.midX, y: bounds.minY - rotationHandleOffset))
        rotationLinelayer.path = linePath.cgPath

        // 更新旋转手柄（圆形）
        let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
        let rotationRect = CGRect(
            x: rotationPos.x - handleSize / 2,
            y: rotationPos.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        rotationHandleLayer.path = UIBezierPath(ovalIn: rotationRect).cgPath
    }

    // MARK: - Hit Testing

    /// 检测点击位置对应的控制点
    private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
        guard isSelected else { return nil }

        let hitRadius: CGFloat = handleSize + 10 // 扩大点击区域

        // 先检查旋转手柄
        let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
        if distance(from: point, to: rotationPos) < hitRadius {
            return .rotation
        }

        // 再检查角点
        let corners: [ControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        for corner in corners {
            let cornerPos = corner.position(in: bounds)
            if distance(from: point, to: cornerPos) < hitRadius {
                return corner
            }
        }

        return nil
    }

    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // 扩大点击区域以包含控制点
        let expandedBounds = bounds.insetBy(
            dx: -(handleSize + rotationHandleOffset + 20),
            dy: -(handleSize + rotationHandleOffset + 20)
        )
        return expandedBounds.contains(point)
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onSelected?(shapeNode.id)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)

        switch gesture.state {
        case .began:
            onOperationStart?(shapeNode)

            // 检测是否点击了控制点
            activeHandle = hitTestHandle(at: location)
            dragStartPoint = gesture.location(in: superview)
            initialFrame = frame
            initialRotation = atan2(transform.b, transform.a)

        case .changed:
            let currentPoint = gesture.location(in: superview)

            if let handle = activeHandle {
                switch handle {
                case .rotation:
                    handleRotation(currentPoint: currentPoint)
                default:
                    handleResize(handle: handle, currentPoint: currentPoint)
                }
            } else {
                // 整体移动
                handleMove(currentPoint: currentPoint)
            }

        case .ended, .cancelled:
            syncToNode()
            onOperationEnd?(shapeNode, shapeNode)
            activeHandle = nil

        default:
            break
        }
    }

    // MARK: - Transform Operations

    /// 处理移动
    private func handleMove(currentPoint: CGPoint) {
        let dx = currentPoint.x - dragStartPoint.x
        let dy = currentPoint.y - dragStartPoint.y

        frame = CGRect(
            x: initialFrame.origin.x + dx,
            y: initialFrame.origin.y + dy,
            width: initialFrame.width,
            height: initialFrame.height
        )
    }

    /// 处理缩放（角点拖动）
    private func handleResize(handle: ControlHandle, currentPoint: CGPoint) {
        guard let oppositeCorner = handle.oppositeCorner else { return }

        // 获取锚点位置（在 superview 坐标系中）
        let anchorInLocal = oppositeCorner.position(in: CGRect(origin: .zero, size: initialFrame.size))
        var anchorInSuperview = CGPoint(
            x: initialFrame.origin.x + anchorInLocal.x,
            y: initialFrame.origin.y + anchorInLocal.y
        )

        // 如果有旋转，需要考虑旋转后的锚点位置
        if initialRotation != 0 {
            let centerX = initialFrame.midX
            let centerY = initialFrame.midY
            let cos_r = cos(initialRotation)
            let sin_r = sin(initialRotation)

            let relX = anchorInSuperview.x - centerX
            let relY = anchorInSuperview.y - centerY

            anchorInSuperview = CGPoint(
                x: centerX + relX * cos_r - relY * sin_r,
                y: centerY + relX * sin_r + relY * cos_r
            )
        }

        // 计算新的对角线向量
        let dx = currentPoint.x - anchorInSuperview.x
        let dy = currentPoint.y - anchorInSuperview.y

        // 考虑旋转的影响，将拖动向量转换到未旋转的坐标系
        let cos_neg_r = cos(-initialRotation)
        let sin_neg_r = sin(-initialRotation)
        let localDx = dx * cos_neg_r - dy * sin_neg_r
        let localDy = dx * sin_neg_r + dy * cos_neg_r

        // 计算新尺寸（保持最小尺寸）
        var newWidth = abs(localDx)
        var newHeight = abs(localDy)
        newWidth = max(newWidth, 20)
        newHeight = max(newHeight, 20)

        // 计算新的中心点
        let newCenterX = anchorInSuperview.x + (currentPoint.x - anchorInSuperview.x) / 2
        let newCenterY = anchorInSuperview.y + (currentPoint.y - anchorInSuperview.y) / 2

        // 更新 frame
        frame = CGRect(
            x: newCenterX - newWidth / 2,
            y: newCenterY - newHeight / 2,
            width: newWidth,
            height: newHeight
        )

        // 保持旋转角度不变
        transform = CGAffineTransform(rotationAngle: initialRotation)

        // 更新路径和控制点
        updateShapePath()
        updateSelectionAppearance()
    }

    /// 处理旋转（旋转手柄拖动）
    private func handleRotation(currentPoint: CGPoint) {
        // 计算从中心到当前点的角度
        let centerInSuperview = CGPoint(
            x: frame.midX,
            y: frame.midY
        )

        let angle = atan2(
            currentPoint.y - centerInSuperview.y,
            currentPoint.x - centerInSuperview.x
        )

        // 旋转手柄在顶部，所以需要加 90 度偏移
        let rotation = angle + .pi / 2

        transform = CGAffineTransform(rotationAngle: rotation)
        updateSelectionAppearance()
    }

    // MARK: - Public Methods

    func enableShapeGestures() {
        isUserInteractionEnabled = true
        panGesture.isEnabled = true
        tapGesture.isEnabled = true
    }

    // MARK: - Helper Methods

    private func createStarPath(in rect: CGRect, points: Int) -> UIBezierPath {
        let path = UIBezierPath()
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
        path.close()
        return path
    }

    private func createPolygonPath(in rect: CGRect, sides: Int) -> UIBezierPath {
        let path = UIBezierPath()
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
        path.close()
        return path
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateShapePath()
        if isSelected {
            updateSelectionAppearance()
        }
    }
}
```

#### 4.3.3 同样为 SelectableArrowView 添加控制点

箭头对象也需要控制点交互，但箭头的控制点更简单：
- 两个端点：拖动可以调整起点/终点
- 中间点：整体移动

由于箭头是线性的，不需要旋转手柄（旋转通过调整端点实现）。

**文件**: `SelectableArrowView.swift`

需要添加：
1. 端点控制点的绘制
2. 端点控制点的 hitTest
3. 端点拖动的处理逻辑

---

## 五、实施计划

### Phase 1: P0 紧急修复（15分钟）

| 序号 | 任务 | 文件 |
|-----|------|------|
| 1 | 修复直线变箭头 | SelectableArrowView.swift |

**验证**:
1. 绘制直线 → 选择工具 → 拖动 → 直线保持为直线

### Phase 2: 控制点基础实现（2小时）

| 序号 | 任务 | 文件 |
|-----|------|------|
| 1 | 添加 ControlHandle 枚举 | SelectableShapeView.swift |
| 2 | 绘制控制点 UI | SelectableShapeView.swift |
| 3 | 实现控制点 hitTest | SelectableShapeView.swift |
| 4 | 实现角点缩放逻辑 | SelectableShapeView.swift |
| 5 | 实现旋转手柄逻辑 | SelectableShapeView.swift |

**验证**:
1. 选中形状后显示控制点
2. 拖动角点可以缩放
3. 拖动旋转手柄可以旋转

### Phase 3: 箭头控制点（1小时）

| 序号 | 任务 | 文件 |
|-----|------|------|
| 1 | 绘制端点控制点 | SelectableArrowView.swift |
| 2 | 实现端点拖动 | SelectableArrowView.swift |

### Phase 4: 偏移修复（30分钟）

| 序号 | 任务 | 文件 |
|-----|------|------|
| 1 | UIKit 预览方法 | NativeCanvasView.swift |
| 2 | 集成修改 | NativeEditorView.swift |

---

## 六、测试用例

### 6.1 直线/箭头测试

| 测试项 | 操作步骤 | 预期结果 |
|--------|---------|---------|
| 直线保持 | 绘制直线 → 选择 → 拖动 | 直线保持为直线 |
| 箭头保持 | 绘制箭头 → 选择 → 拖动 | 箭头保持为箭头 |

### 6.2 控制点测试

| 测试项 | 操作步骤 | 预期结果 |
|--------|---------|---------|
| 选中显示控制点 | 点击形状 | 显示 4 个角点 + 旋转手柄 |
| 角点缩放 | 拖动角点 | 形状缩放，对角固定 |
| 旋转手柄 | 拖动旋转手柄 | 形状绕中心旋转 |
| 整体移动 | 拖动形状中心 | 形状移动 |
| 取消选中 | 点击空白区域 | 控制点消失 |

### 6.3 边界测试

| 测试项 | 操作步骤 | 预期结果 |
|--------|---------|---------|
| 最小尺寸 | 缩放到很小 | 保持最小 20x20 |
| 撤销缩放 | 缩放 → 撤销 | 恢复原尺寸 |
| 撤销旋转 | 旋转 → 撤销 | 恢复原角度 |

---

## 七、参考资源

### 控制点交互参考

- [Figma - Selection Tool](https://help.figma.com/hc/en-us/articles/360039957534-Select-layers-and-objects)
- [GitHub - SPUserResizableView](https://github.com/spoletto/SPUserResizableView) - iOS 可调整大小的视图
- [GitHub - YSChartView](https://github.com/nicklockwood/iCarousel) - 带控制点的视图示例
- [Apple Human Interface Guidelines - Direct Manipulation](https://developer.apple.com/design/human-interface-guidelines/direct-manipulation)

### 坐标变换数学

```swift
// 旋转点绕中心点
func rotate(point: CGPoint, around center: CGPoint, by angle: Double) -> CGPoint {
    let cos_a = cos(angle)
    let sin_a = sin(angle)
    let dx = point.x - center.x
    let dy = point.y - center.y
    return CGPoint(
        x: center.x + dx * cos_a - dy * sin_a,
        y: center.y + dx * sin_a + dy * cos_a
    )
}

// 从 transform 提取旋转角度
let rotation = atan2(transform.b, transform.a)
```

---

## 八、UI 规范

### 控制点样式

| 元素 | 样式 |
|------|------|
| 角点控制点 | 白色填充 + 蓝色边框，12x12 方形 |
| 旋转手柄 | 白色填充 + 蓝色边框，12x12 圆形 |
| 旋转连接线 | 蓝色，1.5pt 宽，30pt 长 |
| 选中边框 | 蓝色虚线，4-4 dash pattern |

### 交互反馈

| 状态 | 反馈 |
|------|------|
| 悬停控制点 | 控制点轻微放大（可选） |
| 拖动中 | 实时预览变换效果 |
| 拖动结束 | 记录撤销操作 |

---

## 九、风险评估

### 低风险
- **修复1 (直线变箭头)**: 一行代码修改，风险极低

### 中等风险
- **控制点 hitTest**: 需要正确处理旋转后的坐标
- **缩放锚点计算**: 涉及坐标变换数学

### 较高风险
- **旋转状态下的缩放**: 需要在旋转坐标系中计算
- **与现有系统集成**: 需要确保撤销/恢复正常工作

### 回滚方案
- 保留现有双指手势代码，新增控制点作为补充
- 如果控制点出问题，可以降级到双指手势
