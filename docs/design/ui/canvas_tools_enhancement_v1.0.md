# 画布工具增强方案 v1.0

## 概述

本文档针对 MindCanvas 画布工具的三个问题提供完整的修复和增强方案：
1. 图形工具旋转后无法再次旋转/缩放
2. 圆形拖动后持续变形
3. 新增文本工具功能

---

## 问题 1：图形旋转后无法再次旋转/缩放

### 问题描述

图形工具创建的所有图形对象，在旋转之后再次选择，就只能移动，不能再旋转或缩放了。

### 根本原因分析

问题出在 **hit testing 逻辑无法正确识别旋转后的控制点位置**，具体原因链条：

#### 1. `point(inside:with:)` 方法的坐标系问题

**位置**：`SelectableShapeView.swift` 第 355-361 行

```swift
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let expandedBounds = bounds.insetBy(
        dx: -(handleSize + rotationHandleOffset + 20),
        dy: -(handleSize + rotationHandleOffset + 20)
    )
    return expandedBounds.contains(point)
}
```

**问题**：
- 当视图旋转时，`bounds` 是固定的本地坐标系（未旋转的矩形）
- 但实际的控制点已经通过 `transform = CGAffineTransform(rotationAngle:)` 旋转了
- 触摸点也是在旋转后的坐标系中
- 坐标系不匹配导致 touch 事件无法正确穿透到手势识别器

#### 2. `hitTestHandle` 方法的控制点位置计算错误

**位置**：`SelectableShapeView.swift` 第 328-349 行

```swift
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    guard isSelected else { return nil }

    let hitRadius: CGFloat = handleSize + 10

    // 控制点位置基于 bounds（本地坐标，未旋转）
    let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
    if distance(from: point, to: rotationPos) < hitRadius {
        return .rotation
    }
    // ...
}
```

**问题**：
- 控制点位置计算基于 `bounds`（本地坐标，未旋转）
- 触摸点 `point` 是在已旋转的世界坐标系中
- 两个坐标系的对应关系没有被正确转换
- 导致旋转后触摸点和控制点的距离计算错误，hit test 总是失败

#### 3. 为什么只有移动有效

在 `handlePan` 方法中：

```swift
case .changed:
    if let handle = activeHandle {
        // 只有当 activeHandle 不为 nil 时才执行缩放/旋转
        switch handle {
        case .rotation:
            handleRotationImproved(currentPoint: currentPoint)
        default:
            handleResizeFixed(handle: handle, currentPoint: currentPoint)
        }
    } else {
        // 当 activeHandle 为 nil 时执行移动
        handleMoveImproved(currentPoint: currentPoint)
    }
```

由于旋转后 hit test 失败，`activeHandle` 总是为 `nil`，所以总是走移动逻辑。

### 修复方案

#### 修复 1：修正 `point(inside:with:)` 中的坐标系转换

**文件**：`Views/Editor/Canvas/SelectableShapeView.swift`

**修改位置**：第 355-361 行

**修改前**：
```swift
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let expandedBounds = bounds.insetBy(
        dx: -(handleSize + rotationHandleOffset + 20),
        dy: -(handleSize + rotationHandleOffset + 20)
    )
    return expandedBounds.contains(point)
}
```

**修改后**：
```swift
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // 关键：将触摸点从世界坐标系反旋转到本地坐标系
    let rotationAngle = atan2(transform.b, transform.a)
    let cosR = cos(-rotationAngle)  // 反向旋转
    let sinR = sin(-rotationAngle)

    // 相对于中心的点坐标
    let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
    let relativePoint = CGPoint(
        x: point.x - centerPoint.x,
        y: point.y - centerPoint.y
    )

    // 反旋转该点
    let rotatedPoint = CGPoint(
        x: relativePoint.x * cosR - relativePoint.y * sinR,
        y: relativePoint.x * sinR + relativePoint.y * cosR
    )

    // 转换回本地坐标
    let localPoint = CGPoint(
        x: rotatedPoint.x + centerPoint.x,
        y: rotatedPoint.y + centerPoint.y
    )

    // 使用扩展后的本地坐标范围检查
    let expandedBounds = bounds.insetBy(
        dx: -(handleSize + rotationHandleOffset + 20),
        dy: -(handleSize + rotationHandleOffset + 20)
    )
    return expandedBounds.contains(localPoint)
}
```

#### 修复 2：修正 `hitTestHandle` 中的坐标转换

**文件**：`Views/Editor/Canvas/SelectableShapeView.swift`

**修改位置**：第 328-349 行

**修改前**：
```swift
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    guard isSelected else { return nil }

    let hitRadius: CGFloat = handleSize + 10

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
```

**修改后**：
```swift
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    guard isSelected else { return nil }

    let hitRadius: CGFloat = handleSize + 10

    // 关键：将触摸点从世界坐标系转换到本地坐标系
    let rotationAngle = atan2(transform.b, transform.a)
    let cosR = cos(-rotationAngle)  // 反向旋转
    let sinR = sin(-rotationAngle)

    // 相对于中心的点坐标
    let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
    let relativePoint = CGPoint(
        x: point.x - centerPoint.x,
        y: point.y - centerPoint.y
    )

    // 反旋转该点
    let rotatedPoint = CGPoint(
        x: relativePoint.x * cosR - relativePoint.y * sinR,
        y: relativePoint.x * sinR + relativePoint.y * cosR
    )

    // 转换回本地坐标
    let localTouchPoint = CGPoint(
        x: rotatedPoint.x + centerPoint.x,
        y: rotatedPoint.y + centerPoint.y
    )

    // 先检查旋转手柄
    let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
    if distance(from: localTouchPoint, to: rotationPos) < hitRadius {
        return .rotation
    }

    // 再检查角点
    let corners: [ControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
    for corner in corners {
        let cornerPos = corner.position(in: bounds)
        if distance(from: localTouchPoint, to: cornerPos) < hitRadius {
            return corner
        }
    }

    return nil
}
```

#### 修复 3：优化 `handlePan` 中的坐标处理

**文件**：`Views/Editor/Canvas/SelectableShapeView.swift`

**修改位置**：第 369-433 行 的 `.began` 分支

在 `.began` 分支中，将触摸点转换到本地坐标系再进行 hit test：

**修改位置**：`case .began:` 内部，约第 377 行附近

**修改前**：
```swift
case .began:
    // 保存初始状态
    initialNode = shapeNode
    onOperationStart?(shapeNode)

    activeHandle = hitTestHandle(at: locationInSelf)
    // ...
```

**修改后**：
```swift
case .began:
    // 保存初始状态
    initialNode = shapeNode
    onOperationStart?(shapeNode)

    // 关键修复：将触摸点转换到本地坐标系再进行 hit test
    // (注意：如果已经在 hitTestHandle 内部做了转换，这里就不需要再转换)
    // 以下是双重保险，确保 hitTestHandle 拿到的是正确的本地坐标
    activeHandle = hitTestHandle(at: locationInSelf)
    // ...
```

**注意**：由于我们已经在 `hitTestHandle` 方法内部做了坐标转换，`handlePan` 这里不需要额外修改。但需要确保 `locationInSelf` 传入的是视图坐标系中的点（这是 UIKit 默认行为，是正确的）。

### 修改文件清单

| 文件 | 修改类型 | 修改内容 |
|-----|---------|---------|
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | `point(inside:with:)` 添加反旋转逻辑 |
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | `hitTestHandle` 添加反旋转逻辑 |

### 验收标准

- [ ] 创建任意形状（矩形、圆形、三角形等）
- [ ] 旋转形状 45 度
- [ ] 再次点击形状，确认能够选中
- [ ] 拖拽角点，确认能够缩放
- [ ] 拖拽旋转控制点，确认能够继续旋转
- [ ] 移动形状，确认移动功能正常

---

## 问题 2：圆形拖动后持续变形

### 问题描述

图形工具里的圆形，在选择后，在画布横向拖出图形时，释放后还会继续横向进行拉伸导致变形；竖向拖动时也会竖向再次拉伸。

### 根本原因分析

问题出在 **UIView 的 `layoutSubviews()` 自动调用与手势 `.changed` 的交互冲突**，加上**圆形没有强制保持正方形比例**。

#### 1. `layoutSubviews()` 的自动触发导致状态被覆盖

**位置**：`SelectableShapeView.swift` 第 647-653 行

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    updateShapePath()
    if isSelected {
        updateSelectionAppearance()
    }
}
```

**问题链路**：
1. 当手势处于 `.changed` 状态时，`handleResizeFixed()` 连续更新 `bounds` 和 `center`
2. 这些属性变化会自动触发 `layoutSubviews()` 回调
3. `layoutSubviews()` 中调用的 `updateShapePath()` 会根据当前的 bounds 重新计算形状路径
4. 对于圆形，这会导致额外的隐式拉伸

#### 2. 圆形没有强制保持正方形比例

**位置**：`createShapePath()` 方法第 198-199 行

```swift
case .circle:
    return UIBezierPath(ovalIn: rect)
```

圆形使用 `UIBezierPath(ovalIn: rect)` 绘制，会严格按照 rect 的宽高绘制椭圆。当 `bounds` 从矩形变化时：
- `handleResizeFixed()` 计算 newWidth 和 newHeight（可能不相等）
- 设置 `bounds = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)`
- 触发 `layoutSubviews()`
- `updateShapePath()` 用非正方形的 rect 调用 `UIBezierPath(ovalIn:)`
- 结果：圆形被拉成椭圆

#### 3. 二阶拉伸问题

1. 拖拽中：用户拖动右边界向右 -> bounds.width 增加 -> 圆形变宽
2. 释放时：`syncToNode()` 将当前的 bounds（已经是长方形）保存到 `ShapeLayerNode.frame`
3. 再次选中时：`updateFromNode()` 从保存的已拉伸的 frame 恢复
4. 再拖拽：基于拉伸后的初始状态继续拉伸 -> 二阶拉伸

### 修复方案

采用综合修复方案，同时解决三个层面的问题：

#### 修复 1：在 `handleResizeFixed()` 中强制圆形保持正方形

**文件**：`Views/Editor/Canvas/SelectableShapeView.swift`

**修改位置**：`handleResizeFixed` 方法，约第 452-529 行

在计算 `newWidth` 和 `newHeight` 之后，添加圆形的特殊处理：

**修改位置**：约第 484-486 行之后

**插入以下代码**（在最小尺寸限制之后）：

```swift
// 最小尺寸限制
let minSize: CGFloat = 20
newWidth = max(newWidth, minSize)
newHeight = max(newHeight, minSize)

// 新增：圆形强制正方形比例
if shapeNode.shapeType == .circle {
    let maxDimension = max(newWidth, newHeight)
    newWidth = maxDimension
    newHeight = maxDimension
}

// Step 5 及以后保持不变...
```

**完整的修改后代码片段**：

```swift
/// 修复后的缩放方法 - 使用增量计算，避免第一帧跳变
private func handleResizeFixed(handle: ControlHandle, currentPoint: CGPoint) {
    guard let oppositeCorner = handle.oppositeCorner else { return }

    // Step 1-4: 计算新尺寸（保持现有逻辑）
    let anchorLocalOffset = anchorOffset(for: oppositeCorner)
    let cosR = cos(initialRotation)
    let sinR = sin(initialRotation)

    let anchorInSuperview = CGPoint(
        x: initialCenter.x + anchorLocalOffset.x * cosR - anchorLocalOffset.y * sinR,
        y: initialCenter.y + anchorLocalOffset.x * sinR + anchorLocalOffset.y * cosR
    )

    let dragDeltaX = currentPoint.x - dragStartPoint.x
    let dragDeltaY = currentPoint.y - dragStartPoint.y

    let cosNegR = cos(-initialRotation)
    let sinNegR = sin(-initialRotation)
    let localDeltaX = dragDeltaX * cosNegR - dragDeltaY * sinNegR
    let localDeltaY = dragDeltaX * sinNegR + dragDeltaY * cosNegR

    let widthSign: CGFloat = (handle == .topLeft || handle == .bottomLeft) ? -1 : 1
    let heightSign: CGFloat = (handle == .topLeft || handle == .topRight) ? -1 : 1

    var newWidth = initialBounds.width + localDeltaX * widthSign
    var newHeight = initialBounds.height + localDeltaY * heightSign

    // 最小尺寸限制
    let minSize: CGFloat = 20
    newWidth = max(newWidth, minSize)
    newHeight = max(newHeight, minSize)

    // 新增：圆形强制正方形比例
    if shapeNode.shapeType == .circle {
        let maxDimension = max(newWidth, newHeight)
        newWidth = maxDimension
        newHeight = maxDimension
    }

    // Step 5 及以后保持不变...
    let newHalfWidth = newWidth / 2
    let newHalfHeight = newHeight / 2

    // ... 其余代码保持不变
}
```

#### 修复 2：在 `layoutSubviews` 中添加手势守卫

**文件**：`Views/Editor/Canvas/SelectableShapeView.swift`

**修改位置**：第 647-653 行

**修改前**：
```swift
override func layoutSubviews() {
    super.layoutSubviews()
    updateShapePath()
    if isSelected {
        updateSelectionAppearance()
    }
}
```

**修改后**：
```swift
override func layoutSubviews() {
    super.layoutSubviews()

    // 防护：如果正在手势中，跳过 updateShapePath
    // 因为 handleResizeFixed 已经调用过了
    guard activeHandle == nil else { return }

    updateShapePath()
    if isSelected {
        updateSelectionAppearance()
    }
}
```

#### 修复 3：在 `updateFromNode()` 中修复已损坏的圆形数据

**文件**：`Views/Editor/Canvas/SelectableShapeView.swift`

**修改位置**：`updateFromNode()` 方法，约第 246-259 行

**修改前**：
```swift
func updateFromNode() {
    // 重置 transform 为 identity
    transform = .identity

    // 设置 bounds 和 center
    bounds = CGRect(x: 0, y: 0, width: shapeNode.frame.width, height: shapeNode.frame.height)
    center = CGPoint(x: shapeNode.frame.midX, y: shapeNode.frame.midY)

    // 应用旋转
    transform = CGAffineTransform(rotationAngle: shapeNode.rotation)

    updateShapePath()
    updateSelectionAppearance()
}
```

**修改后**：
```swift
func updateFromNode() {
    // 重置 transform 为 identity
    transform = .identity

    var finalWidth = shapeNode.frame.width
    var finalHeight = shapeNode.frame.height

    // 修复圆形的宽高（防止加载已损坏的数据）
    if shapeNode.shapeType == .circle {
        let maxDimension = max(finalWidth, finalHeight)
        finalWidth = maxDimension
        finalHeight = maxDimension
    }

    // 设置 bounds 和 center
    bounds = CGRect(x: 0, y: 0, width: finalWidth, height: finalHeight)
    center = CGPoint(x: shapeNode.frame.midX, y: shapeNode.frame.midY)

    // 应用旋转
    transform = CGAffineTransform(rotationAngle: shapeNode.rotation)

    updateShapePath()
    updateSelectionAppearance()
}
```

### 修改文件清单

| 文件 | 修改类型 | 修改内容 |
|-----|---------|---------|
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | `handleResizeFixed()` 添加圆形正方形约束 |
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | `layoutSubviews()` 添加手势守卫 |
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | `updateFromNode()` 修复已损坏的圆形数据 |

### 验收标准

- [ ] 创建圆形，横向拖拽绘制，释放后圆形保持正圆
- [ ] 创建圆形，竖向拖拽绘制，释放后圆形保持正圆
- [ ] 选中圆形，拖拽角点缩放，圆形保持正圆
- [ ] 选中圆形，旋转后再缩放，圆形保持正圆
- [ ] 关闭并重新打开项目，之前创建的圆形仍然保持正圆

---

## 问题 3：新增文本工具功能

### 需求描述

给画布下的工具栏加上文本工具（'T' 图标），实现以下功能：
1. 点击 T 图标，弹出字体选择列表
2. 在画布上添加可编辑文字
3. 使用选择工具时可以选择、旋转、缩放文字
4. 文字能被选框截图截取到

### 技术方案

#### 架构概览

```
新增文件：
├── Models/Canvas/TextLayerNode.swift          # 已有，需扩展
├── Views/Editor/Canvas/SelectableTextView.swift    # 新增
├── Views/Editor/Canvas/FontPickerPopover.swift     # 新增
└── Extensions/UIFont+Available.swift               # 新增
```

#### 数据模型扩展

**文件**：`Models/Canvas/TextLayerNode.swift`

现有模型已包含基础字段，需要扩展以支持变换：

**修改后的完整模型**：

```swift
import Foundation
import CoreGraphics
import UIKit

/// 文字图层节点
struct TextLayerNode: Codable, Identifiable {
    let id: UUID
    var position: CGPoint           // 中心位置
    var text: String                // 文字内容
    var fontSize: CGFloat           // 字体大小
    var color: String               // 颜色（十六进制）
    var fontName: String            // 字体名称
    var rotation: CGFloat           // 旋转角度（弧度）- 新增
    var scale: CGFloat              // 缩放比例 - 新增
    let zIndex: Int
    let createdAt: Date

    /// 计算精确的边界框
    var bounds: CGRect {
        let font = UIFont(name: fontName, size: fontSize * scale)
            ?? UIFont.systemFont(ofSize: fontSize * scale)

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let nsString = text as NSString
        let size = nsString.boundingRect(
            with: CGSize(width: .infinity, height: .infinity),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).size

        return CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// 创建文字图层
    init(
        position: CGPoint,
        text: String,
        fontSize: CGFloat = 24,
        color: String = "#000000",
        fontName: String = ".SF Pro Display",
        rotation: CGFloat = 0,
        scale: CGFloat = 1.0,
        zIndex: Int = 0
    ) {
        self.id = UUID()
        self.position = position
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.fontName = fontName
        self.rotation = rotation
        self.scale = scale
        self.zIndex = zIndex
        self.createdAt = Date()
    }

    /// 更新文字属性
    func updated(
        position: CGPoint? = nil,
        text: String? = nil,
        fontSize: CGFloat? = nil,
        color: String? = nil,
        fontName: String? = nil,
        rotation: CGFloat? = nil,
        scale: CGFloat? = nil
    ) -> TextLayerNode {
        var node = TextLayerNode(
            position: position ?? self.position,
            text: text ?? self.text,
            fontSize: fontSize ?? self.fontSize,
            color: color ?? self.color,
            fontName: fontName ?? self.fontName,
            rotation: rotation ?? self.rotation,
            scale: scale ?? self.scale,
            zIndex: self.zIndex
        )
        return node
    }
}
```

#### 新增可选择文本视图

**文件**：`Views/Editor/Canvas/SelectableTextView.swift`

参考 `SelectableShapeView` 的实现模式，创建可选择、可旋转、可缩放的文本视图：

```swift
import UIKit

/// 可选择的文本视图（支持控制点交互）
class SelectableTextView: UIView {

    // MARK: - Properties

    var textNode: TextLayerNode {
        didSet {
            updateFromNode()
        }
    }

    // 文本图层
    private let textLayer = CATextLayer()

    // 选中边框
    private let selectionBorder = CAShapeLayer()
    private var cornerHandleLayers: [CAShapeLayer] = []
    private let rotationHandleLayer = CAShapeLayer()
    private let rotationLineLayer = CAShapeLayer()

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

    // 初始状态 (手势开始时保存)
    private var initialBounds: CGRect = .zero
    private var initialCenter: CGPoint = .zero
    private var initialRotation: CGFloat = 0
    private var initialTouchAngle: CGFloat = 0
    private var initialNode: TextLayerNode?

    // 手势
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    private var doubleTapGesture: UITapGestureRecognizer!

    // 回调
    var onNodeUpdated: ((TextLayerNode) -> Void)?
    var onSelected: ((UUID) -> Void)?
    var onOperationStart: ((TextLayerNode) -> Void)?
    var onOperationEnd: ((TextLayerNode, TextLayerNode) -> Void)?
    var onDoubleClick: ((TextLayerNode) -> Void)?  // 双击编辑

    // MARK: - Initialization

    init(textNode: TextLayerNode) {
        self.textNode = textNode
        let bounds = textNode.bounds
        super.init(frame: bounds)
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
        isOpaque = false
        clipsToBounds = false

        // 配置文本图层
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.alignmentMode = .center
        textLayer.isWrapped = true
        layer.addSublayer(textLayer)

        // 添加选中边框
        layer.addSublayer(selectionBorder)

        // 添加控制点
        for _ in 0..<4 {
            let handleLayer = CAShapeLayer()
            layer.addSublayer(handleLayer)
            cornerHandleLayers.append(handleLayer)
        }

        // 添加旋转连接线和手柄
        layer.addSublayer(rotationLineLayer)
        layer.addSublayer(rotationHandleLayer)

        updateSelectionStyle()
    }

    private func setupGestures() {
        // 点击手势
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        // 双击手势（编辑文字）
        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)

        // 让单击等待双击失败
        tapGesture.require(toFail: doubleTapGesture)

        // 拖拽手势
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
    }

    private func updateSelectionStyle() {
        // 选中边框样式
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.strokeColor = UIColor.systemBlue.cgColor
        selectionBorder.lineWidth = 1.5
        selectionBorder.lineDashPattern = [4, 4]

        // 控制点样式
        for handleLayer in cornerHandleLayers {
            handleLayer.fillColor = UIColor.white.cgColor
            handleLayer.strokeColor = UIColor.systemBlue.cgColor
            handleLayer.lineWidth = 2
        }

        // 旋转连接线样式
        rotationLineLayer.fillColor = UIColor.clear.cgColor
        rotationLineLayer.strokeColor = UIColor.systemBlue.cgColor
        rotationLineLayer.lineWidth = 1.5

        // 旋转手柄样式
        rotationHandleLayer.fillColor = UIColor.white.cgColor
        rotationHandleLayer.strokeColor = UIColor.systemBlue.cgColor
        rotationHandleLayer.lineWidth = 2
    }

    // MARK: - Update Methods

    func updateFromNode() {
        transform = .identity

        // 更新文本图层
        textLayer.string = textNode.text

        let font = UIFont(name: textNode.fontName, size: textNode.fontSize * textNode.scale)
            ?? UIFont.systemFont(ofSize: textNode.fontSize * textNode.scale)
        textLayer.font = font.fontName as CFString
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = UIColor_fromHex(textNode.color).cgColor

        // 计算边界
        let textBounds = textNode.bounds
        bounds = CGRect(origin: .zero, size: textBounds.size)
        center = textNode.position

        // 更新文本图层位置
        textLayer.frame = bounds

        // 应用旋转
        transform = CGAffineTransform(rotationAngle: textNode.rotation)

        updateSelectionAppearance()
    }

    private func syncToNode() {
        let currentRotation = atan2(transform.b, transform.a)

        textNode = textNode.updated(
            position: center,
            rotation: currentRotation
        )
        onNodeUpdated?(textNode)
    }

    private func updateSelectionAppearance() {
        let showHandles = isSelected

        selectionBorder.isHidden = !showHandles
        rotationLineLayer.isHidden = !showHandles
        rotationHandleLayer.isHidden = !showHandles
        cornerHandleLayers.forEach { $0.isHidden = !showHandles }

        guard showHandles else { return }

        // 更新选中边框
        selectionBorder.path = UIBezierPath(rect: bounds).cgPath

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
        rotationLineLayer.path = linePath.cgPath

        // 更新旋转手柄
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

    private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
        guard isSelected else { return nil }

        let hitRadius: CGFloat = handleSize + 10

        // 坐标转换（与 SelectableShapeView 相同的逻辑）
        let rotationAngle = atan2(transform.b, transform.a)
        let cosR = cos(-rotationAngle)
        let sinR = sin(-rotationAngle)

        let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        let relativePoint = CGPoint(x: point.x - centerPoint.x, y: point.y - centerPoint.y)
        let rotatedPoint = CGPoint(
            x: relativePoint.x * cosR - relativePoint.y * sinR,
            y: relativePoint.x * sinR + relativePoint.y * cosR
        )
        let localTouchPoint = CGPoint(x: rotatedPoint.x + centerPoint.x, y: rotatedPoint.y + centerPoint.y)

        // 先检查旋转手柄
        let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
        if distance(from: localTouchPoint, to: rotationPos) < hitRadius {
            return .rotation
        }

        // 再检查角点
        let corners: [ControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        for corner in corners {
            let cornerPos = corner.position(in: bounds)
            if distance(from: localTouchPoint, to: cornerPos) < hitRadius {
                return corner
            }
        }

        return nil
    }

    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // 与 SelectableShapeView 相同的坐标转换逻辑
        let rotationAngle = atan2(transform.b, transform.a)
        let cosR = cos(-rotationAngle)
        let sinR = sin(-rotationAngle)

        let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        let relativePoint = CGPoint(x: point.x - centerPoint.x, y: point.y - centerPoint.y)
        let rotatedPoint = CGPoint(
            x: relativePoint.x * cosR - relativePoint.y * sinR,
            y: relativePoint.x * sinR + relativePoint.y * cosR
        )
        let localPoint = CGPoint(x: rotatedPoint.x + centerPoint.x, y: rotatedPoint.y + centerPoint.y)

        let expandedBounds = bounds.insetBy(
            dx: -(handleSize + rotationHandleOffset + 20),
            dy: -(handleSize + rotationHandleOffset + 20)
        )
        return expandedBounds.contains(localPoint)
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onSelected?(textNode.id)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        onDoubleClick?(textNode)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let locationInSelf = gesture.location(in: self)

        switch gesture.state {
        case .began:
            initialNode = textNode
            onOperationStart?(textNode)
            activeHandle = hitTestHandle(at: locationInSelf)
            initialCenter = center
            initialBounds = bounds
            initialRotation = atan2(transform.b, transform.a)

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
                    handleRotation(currentPoint: currentPoint)
                default:
                    handleResize(handle: handle, currentPoint: currentPoint)
                }
            } else {
                handleMove(currentPoint: currentPoint)
            }

        case .ended, .cancelled:
            syncToNode()
            if let initial = initialNode {
                onOperationEnd?(initial, textNode)
            }
            activeHandle = nil
            initialNode = nil

        default:
            break
        }
    }

    private func handleMove(currentPoint: CGPoint) {
        let dx = currentPoint.x - dragStartPoint.x
        let dy = currentPoint.y - dragStartPoint.y
        center = CGPoint(x: initialCenter.x + dx, y: initialCenter.y + dy)
    }

    private func handleRotation(currentPoint: CGPoint) {
        let currentTouchAngle = atan2(
            currentPoint.y - initialCenter.y,
            currentPoint.x - initialCenter.x
        )
        let deltaAngle = currentTouchAngle - initialTouchAngle
        let newRotation = initialRotation + deltaAngle
        transform = CGAffineTransform(rotationAngle: newRotation)
        updateSelectionAppearance()
    }

    private func handleResize(handle: ControlHandle, currentPoint: CGPoint) {
        // 简化的缩放实现：根据拖拽距离计算缩放因子
        let dragDeltaX = currentPoint.x - dragStartPoint.x
        let dragDeltaY = currentPoint.y - dragStartPoint.y

        // 计算缩放因子
        let scaleFactor = 1.0 + (dragDeltaX + dragDeltaY) / 200.0
        let newScale = max(0.5, min(3.0, textNode.scale * scaleFactor))

        // 更新字体大小
        textNode = textNode.updated(scale: newScale)

        // 重新计算边界
        let textBounds = textNode.bounds
        bounds = CGRect(origin: .zero, size: textBounds.size)
        textLayer.frame = bounds

        updateSelectionAppearance()
    }

    // MARK: - Public Methods

    func enableTextGestures() {
        isUserInteractionEnabled = true
        panGesture.isEnabled = true
        tapGesture.isEnabled = true
        doubleTapGesture.isEnabled = true
    }

    // MARK: - Helper Methods

    private func UIColor_fromHex(_ hex: String) -> UIColor {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SelectableTextView: UIGestureRecognizerDelegate {}
```

#### 新增字体选择弹窗

**文件**：`Views/Editor/Canvas/FontPickerPopover.swift`

```swift
import SwiftUI

/// 字体选择弹窗
struct FontPickerPopover: View {
    @Binding var selectedFont: String
    @Binding var fontSize: CGFloat
    @Binding var textColor: Color
    let onConfirm: () -> Void

    // 推荐字体列表
    private let recommendedFonts: [(name: String, displayName: String)] = [
        (".SF Pro Display", "SF Pro"),
        ("Helvetica Neue", "Helvetica"),
        ("Times New Roman", "Times"),
        ("Georgia", "Georgia"),
        ("Courier New", "Courier"),
        ("Marker Felt", "Marker Felt"),
        ("Bradley Hand", "Bradley Hand"),
        ("Noteworthy", "Noteworthy"),
        ("Papyrus", "Papyrus"),
        ("Menlo", "Menlo"),
    ]

    // 字体大小选项
    private let fontSizes: [CGFloat] = [12, 16, 20, 24, 32, 48, 64, 96]

    var body: some View {
        VStack(spacing: 16) {
            // 标题
            Text("文字设置")
                .font(.headline)
                .padding(.top, 8)

            Divider()

            // 字体选择
            VStack(alignment: .leading, spacing: 8) {
                Text("字体")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recommendedFonts, id: \.name) { font in
                            FontButton(
                                fontName: font.name,
                                displayName: font.displayName,
                                isSelected: selectedFont == font.name,
                                action: {
                                    selectedFont = font.name
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            // 字体大小
            VStack(alignment: .leading, spacing: 8) {
                Text("大小")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(fontSizes, id: \.self) { size in
                            Button {
                                fontSize = size
                            } label: {
                                Text("\(Int(size))")
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(fontSize == size ? Color.blue : Color.gray.opacity(0.1))
                                    )
                                    .foregroundColor(fontSize == size ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            // 颜色选择
            VStack(alignment: .leading, spacing: 8) {
                Text("颜色")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ColorPicker("", selection: $textColor)
                    .labelsHidden()
            }

            Divider()

            // 确认按钮
            Button {
                onConfirm()
            } label: {
                Text("添加文字")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .frame(width: 320)
    }
}

// MARK: - 字体按钮

private struct FontButton: View {
    let fontName: String
    let displayName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(displayName)
                .font(.custom(fontName, size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.1))
                )
                .foregroundColor(isSelected ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FontPickerPopover(
        selectedFont: .constant(".SF Pro Display"),
        fontSize: .constant(24),
        textColor: .constant(.black),
        onConfirm: {}
    )
}
```

#### 工具栏集成

**文件**：`Views/Editor/Canvas/CanvasToolbar.swift`

在工具按钮循环中添加文本工具的处理：

**修改位置**：`body` 中的 `ForEach` 循环内，添加 `case .text:` 分支

```swift
case .text:
    // 文字工具特殊处理 - 弹出字体选择器
    TextToolButton(
        tool: tool,
        isSelected: currentTool == tool,
        showPicker: $showTextPicker,
        selectedFont: $selectedFont,
        fontSize: $fontSize,
        textColor: $textColor,
        onConfirm: {
            showTextPicker = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentTool = .text
            }
            onTextToolSelected?(selectedFont, fontSize, textColor)
        }
    )
```

**新增状态变量**（在 `CanvasToolbar` 结构体中）：

```swift
@State private var showTextPicker = false
@State private var selectedFont = ".SF Pro Display"
@State private var fontSize: CGFloat = 24
@State private var textColor: Color = .black

// 新增回调
var onTextToolSelected: ((String, CGFloat, Color) -> Void)?
```

**新增 `TextToolButton` 组件**：

```swift
// MARK: - 文字工具按钮（带弹出选择器）

private struct TextToolButton: View {
    let tool: CanvasTool
    let isSelected: Bool
    @Binding var showPicker: Bool
    @Binding var selectedFont: String
    @Binding var fontSize: CGFloat
    @Binding var textColor: Color
    let onConfirm: () -> Void

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            Image(systemName: tool.iconName)
                .font(.system(size: 22))
                .foregroundColor(isSelected ? .white : Theme.Colors.secondaryText)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .fill(isSelected ? Theme.Colors.brandBlue : Color.clear)
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .help(tool.displayName)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            FontPickerPopover(
                selectedFont: $selectedFont,
                fontSize: $fontSize,
                textColor: $textColor,
                onConfirm: onConfirm
            )
        }
    }
}
```

#### 启用文字工具

**文件**：`Models/Canvas/CanvasTool.swift`

**修改位置**：`isMainToolbarTool` 属性

**修改前**：
```swift
var isMainToolbarTool: Bool {
    switch self {
    case .select, .pan, .pen, .eraser, .rectangle, .image:
        return true
    case .arrow:
        return false
    case .text, .annotation:  // 功能未完整实现，暂不显示
        return false
    }
}
```

**修改后**：
```swift
var isMainToolbarTool: Bool {
    switch self {
    case .select, .pan, .pen, .eraser, .rectangle, .image, .text:  // 启用文字工具
        return true
    case .arrow:
        return false
    case .annotation:
        return false
    }
}
```

#### NativeCanvasView 集成

**文件**：`Views/Editor/Canvas/NativeCanvasView.swift`

添加文本视图管理：

**新增属性**（约第 80 行附近）：

```swift
/// 文字视图字典 (nodeID -> SelectableTextView)
var textViews: [UUID: SelectableTextView] = [:]
```

**新增方法**（约第 1250 行附近）：

```swift
// MARK: - 文字视图管理

/// 创建文字视图
private func createTextView(for text: TextLayerNode) {
    let textView = SelectableTextView(textNode: text)

    var operationStartText: TextLayerNode?

    textView.onNodeUpdated = { [weak self] updatedText in
        self?.textLayerManager.updateText(updatedText)
    }

    textView.onSelected = { [weak self] textID in
        self?.selectedNodeID = textID
    }

    textView.onOperationStart = { text in
        operationStartText = text
    }

    textView.onOperationEnd = { [weak self] _, endText in
        guard let self = self, let startText = operationStartText else { return }

        // 检查是否移动
        if startText.position != endText.position {
            let action = MoveTextAction(
                textID: startText.id,
                fromText: startText,
                toText: endText,
                canvasView: self
            )
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
        // 检查是否旋转
        else if abs(startText.rotation - endText.rotation) > 0.001 {
            let action = RotateTextAction(
                textID: startText.id,
                fromText: startText,
                toText: endText,
                canvasView: self
            )
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
        // 检查是否缩放
        else if abs(startText.scale - endText.scale) > 0.01 {
            let action = ScaleTextAction(
                textID: startText.id,
                fromText: startText,
                toText: endText,
                canvasView: self
            )
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }

        operationStartText = nil
    }

    textView.onDoubleClick = { [weak self] text in
        // 触发编辑模式
        // TODO: 实现双击编辑
    }

    textViews[text.id] = textView
    objectLayerView.addSubview(textView)

    // 根据当前工具状态设置手势
    if currentTool == .select || currentTool == .text {
        textView.enableTextGestures()
    }
}

/// 添加文字（重写现有方法）
func addTextWithView(_ text: TextLayerNode, recordUndo: Bool = true) {
    if recordUndo {
        let action = AddTextAction(text: text, canvasView: self)
        NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
    }
    textLayerManager.addText(text)
    createTextView(for: text)
    onTextCreated?(text)
    onCanvasUpdated?()
}

/// 移除文字视图
func removeTextView(id: UUID) {
    textLayerManager.removeText(id: id)
    textViews[id]?.removeFromSuperview()
    textViews.removeValue(forKey: id)
    onCanvasUpdated?()
}

/// 更新文字视图
func updateTextView(_ text: TextLayerNode) {
    textLayerManager.updateText(text)
    if let textView = textViews[text.id] {
        textView.textNode = text
    }
    onCanvasUpdated?()
}
```

**修改 `updateForTool` 方法**，确保文字视图手势正确启用：

在 `case .select:` 分支中添加：

```swift
// 确保所有文字的手势都能正常工作
for textView in textViews.values {
    textView.enableTextGestures()
}
```

**修改 `updateSelectionStates` 方法**，添加文字视图选中状态更新：

```swift
private func updateSelectionStates() {
    // ... 现有代码

    // 更新文字视图选中状态
    for (id, textView) in textViews {
        textView.isSelected = (id == selectedNodeID)
    }

    onSelectionChanged?(selectedNodeID != nil)
}
```

**修改 `removeAllLayers` 方法**，清理文字视图：

```swift
func removeAllLayers() {
    // ... 现有代码

    // 清理文字视图
    textViews.values.forEach { $0.removeFromSuperview() }
    textViews.removeAll()

    // ... 其余代码
}
```

### 修改文件清单

| 文件 | 修改类型 | 修改内容 |
|-----|---------|---------|
| `Models/Canvas/TextLayerNode.swift` | 修改 | 添加 rotation 和 scale 字段 |
| `Models/Canvas/CanvasTool.swift` | 修改 | 启用文字工具在工具栏显示 |
| `Views/Editor/Canvas/SelectableTextView.swift` | 新增 | 可选择的文字视图 |
| `Views/Editor/Canvas/FontPickerPopover.swift` | 新增 | 字体选择弹窗 |
| `Views/Editor/Canvas/CanvasToolbar.swift` | 修改 | 添加文字工具按钮 |
| `Views/Editor/Canvas/NativeCanvasView.swift` | 修改 | 集成文字视图管理 |
| `Views/Editor/NativeEditorView.swift` | 修改 | 处理文字创建流程 |

### 推荐字体清单

| 字体名称 | 显示名 | 类型 | 适用场景 |
|---------|--------|------|---------|
| .SF Pro Display | SF Pro | 系统标准 | 通用文本 |
| Helvetica Neue | Helvetica | 无衬线 | 现代设计 |
| Times New Roman | Times | 衬线 | 正式文档 |
| Georgia | Georgia | 衬线 | 阅读文本 |
| Courier New | Courier | 等宽 | 代码/数据 |
| Marker Felt | Marker Felt | 手写 | 艺术创作 |
| Bradley Hand | Bradley Hand | 手写 | 个人笔记 |
| Noteworthy | Noteworthy | 手写 | 卡通风格 |
| Papyrus | Papyrus | 艺术 | 古典风格 |
| Menlo | Menlo | 等宽 | 技术文档 |

### 验收标准

- [ ] 工具栏显示文字工具图标（T）
- [ ] 点击文字工具弹出字体选择器
- [ ] 可以选择不同字体、字号、颜色
- [ ] 点击画布可以创建文字
- [ ] 使用选择工具可以选中文字
- [ ] 可以拖拽移动文字
- [ ] 可以拖拽角点缩放文字
- [ ] 可以拖拽旋转点旋转文字
- [ ] 旋转后仍可以缩放和移动
- [ ] 文字可以被选框截图截取

---

## 实施计划

### 第一阶段：Bug 修复（优先级高）

| 任务 | 文件 | 预估工时 |
|------|------|---------|
| 修复图形旋转后无法操作 | SelectableShapeView.swift | 1h |
| 修复圆形持续变形 | SelectableShapeView.swift | 1h |
| 测试验证 | - | 1h |

### 第二阶段：文本工具基础功能

| 任务 | 文件 | 预估工时 |
|------|------|---------|
| 扩展 TextLayerNode 数据模型 | TextLayerNode.swift | 0.5h |
| 创建 SelectableTextView | SelectableTextView.swift | 3h |
| 创建 FontPickerPopover | FontPickerPopover.swift | 1h |
| 工具栏集成 | CanvasToolbar.swift | 1h |
| NativeCanvasView 集成 | NativeCanvasView.swift | 2h |
| 启用文字工具 | CanvasTool.swift | 0.5h |

### 第三阶段：测试与优化

| 任务 | 预估工时 |
|------|---------|
| 功能测试 | 2h |
| 截图功能验证 | 1h |
| 性能优化 | 1h |

**总计预估工时：约 14 小时**

---

## 注意事项

1. **坐标系转换**：所有触摸点在与本地坐标系中的对象比较前，必须先通过反向旋转变换将其转换到本地坐标系
2. **字体缓存**：考虑实现字体缓存以提升性能
3. **撤销/重做**：确保所有文字操作都正确记录撤销操作
4. **截图兼容**：使用 CATextLayer 而非 SwiftUI Text 以确保截图正确
5. **代码一致性**：文字视图的实现应与形状视图保持一致的架构模式

---

## 附录：ControlHandle 枚举定义

确保 `SelectableTextView` 使用与 `SelectableShapeView` 相同的 `ControlHandle` 枚举。如果该枚举定义在 `SelectableShapeView.swift` 文件内部，需要将其提取到单独文件或使用相同的定义：

```swift
/// 控制点类型
enum ControlHandle: Int, CaseIterable {
    case topLeft = 0
    case topRight = 1
    case bottomRight = 2
    case bottomLeft = 3
    case rotation = 4

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
