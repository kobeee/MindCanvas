# 图形工具与对象变换优化方案 v1.0

## 一、需求背景

### 1.1 当前问题

1. **箭头对象无法缩放和旋转**：箭头在选择工具下只能拖动，缺少缩放和旋转功能
2. **图形工具（rectangle）无法使用**：点击后没有任何效果
3. **缺少图形选择弹出菜单**：用户期望点击图形工具时，弹出圆形、矩形、三角形等形状选项

### 1.2 期望效果

- 所有画布对象（图片、箭头、矩形、圆形、三角形等）在选择工具状态下都能：
  - **移动**：单指拖拽
  - **缩放**：双指捏合
  - **旋转**：双指旋转
- 图形工具点击后弹出形状选择菜单，包含常用形状

---

## 二、现状分析

### 2.1 代码结构概览

```
当前实现状态：
├── ResizableImageView     ✅ 完整实现（移动+缩放+旋转）
├── SelectableArrowView    ⚠️ 部分实现（仅移动）
├── 矩形/圆形/三角形视图    ❌ 不存在
└── 图形工具弹出菜单        ❌ 不存在
```

### 2.2 SelectableArrowView 问题分析

**文件位置**：`Views/Editor/Canvas/SelectableArrowView.swift`

#### 缺失的功能

| 功能 | ResizableImageView | SelectableArrowView |
|------|:------------------:|:-------------------:|
| UITapGestureRecognizer | ✅ | ✅ |
| UIPanGestureRecognizer | ✅ | ✅ |
| UIPinchGestureRecognizer | ✅ | ❌ |
| UIRotationGestureRecognizer | ✅ | ❌ |
| 手势同时识别 | ✅ | ❌ |

#### 数据模型缺陷

**ArrowLayerNode**（第 7-61 行）只存储起点和终点：
```swift
struct ArrowLayerNode: Codable, Identifiable {
    let id: UUID
    let startPoint: CGPoint    // 起点
    let endPoint: CGPoint      // 终点
    let color: String
    let lineWidth: CGFloat
    let zIndex: Int
    // 缺少 rotation 属性！
    // 缺少 scale 属性！
}
```

对比 **LayerNode**（图片节点）：
```swift
class LayerNode: Identifiable, Codable {
    var frame: CGRect      // 位置和尺寸
    var rotation: Double   // 旋转角度 ✅
    var opacity: Double
    // ...
}
```

### 2.3 图形工具问题分析

**当前状态**：
- `RectangleLayerNode` 数据模型存在
- `RectangleDrawingView` 绘制交互存在
- **缺少渲染视图类**：没有类似 `SelectableRectangleView` 的 UIView 子类
- **回调未连接**：`NativeCanvasView.onRectangleCreated` 回调定义但未使用

**工具切换代码**（NativeCanvasView.swift 第 569-579 行）：
```swift
case .arrow, .rectangle, .text, .annotation:
    // 只配置了画布状态，但没有实际的绘制/创建逻辑
    pencilCanvas.drawingGestureRecognizer.isEnabled = false
    overlayContainerView.isUserInteractionEnabled = true
    objectLayerView.isUserInteractionEnabled = true
```

### 2.4 工具栏问题分析

**当前实现**（CanvasToolbar.swift）：
- 直接遍历 `CanvasTool.mainToolbarTools` 渲染所有工具
- 每个工具按钮点击直接切换工具，无弹出菜单支持

---

## 三、解决方案

### 3.1 整体架构调整

```
重构后架构：
├── Models/Canvas/
│   ├── ShapeLayerNode.swift        [新增] 通用形状节点（替代多个独立节点）
│   └── ShapeType.swift             [新增] 形状类型枚举
├── Views/Editor/Canvas/
│   ├── SelectableShapeView.swift   [新增] 通用可选择形状视图
│   ├── SelectableArrowView.swift   [修改] 添加缩放/旋转支持
│   ├── CanvasToolbar.swift         [修改] 添加弹出菜单支持
│   └── ShapePickerPopover.swift    [新增] 形状选择弹出框
└── NativeCanvasView.swift          [修改] 集成形状管理
```

---

## 四、详细实现方案

### 4.1 Phase 1：箭头视图添加缩放和旋转支持

#### 4.1.1 修改 ArrowLayerNode 数据模型

**文件**：`Models/Canvas/ArrowLayerNode.swift`

**修改内容**：

```swift
struct ArrowLayerNode: Codable, Identifiable {
    let id: UUID
    var startPoint: CGPoint
    var endPoint: CGPoint
    let color: String
    let lineWidth: CGFloat
    let zIndex: Int
    let createdAt: Date

    // [新增] 旋转角度（弧度）
    var rotation: Double = 0.0

    // [新增] 缩放比例
    var scale: CGFloat = 1.0

    // [修改] bounds 计算需要考虑缩放
    var bounds: CGRect {
        let minX = min(startPoint.x, endPoint.x)
        let minY = min(startPoint.y, endPoint.y)
        let maxX = max(startPoint.x, endPoint.x)
        let maxY = max(startPoint.y, endPoint.y)

        let baseWidth = max(maxX - minX, 40)
        let baseHeight = max(maxY - minY, 40)

        // 应用缩放
        let scaledWidth = baseWidth * scale
        let scaledHeight = baseHeight * scale

        let centerX = (startPoint.x + endPoint.x) / 2
        let centerY = (startPoint.y + endPoint.y) / 2

        return CGRect(
            x: centerX - scaledWidth / 2,
            y: centerY - scaledHeight / 2,
            width: scaledWidth,
            height: scaledHeight
        )
    }

    // [新增] 获取箭头中心点
    var center: CGPoint {
        CGPoint(
            x: (startPoint.x + endPoint.x) / 2,
            y: (startPoint.y + endPoint.y) / 2
        )
    }
}
```

#### 4.1.2 修改 SelectableArrowView

**文件**：`Views/Editor/Canvas/SelectableArrowView.swift`

**步骤 1：添加缩放和旋转手势属性**

在第 30-31 行后添加：
```swift
private var panGesture: UIPanGestureRecognizer!
private var tapGesture: UITapGestureRecognizer!
private var pinchGesture: UIPinchGestureRecognizer!     // [新增]
private var rotateGesture: UIRotationGestureRecognizer! // [新增]
```

**步骤 2：修改 setupGestures() 方法**

替换第 83-94 行：
```swift
private func setupGestures() {
    // 点击选中
    tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
    addGestureRecognizer(tapGesture)

    // 拖拽移动
    panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    addGestureRecognizer(panGesture)

    // [新增] 缩放
    pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
    addGestureRecognizer(pinchGesture)

    // [新增] 旋转
    rotateGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
    addGestureRecognizer(rotateGesture)

    // 设置手势代理
    panGesture.delegate = self
    pinchGesture.delegate = self
    rotateGesture.delegate = self
}
```

**步骤 3：添加缩放手势处理**

在 `handlePan` 方法后添加：
```swift
@objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
    switch gesture.state {
    case .began:
        onOperationStart?(arrowNode)

    case .changed:
        // 应用缩放变换
        transform = transform.scaledBy(x: gesture.scale, y: gesture.scale)
        gesture.scale = 1.0 // 重置以累积变换

    case .ended:
        // 更新节点的缩放值
        let currentScale = sqrt(transform.a * transform.a + transform.c * transform.c)
        arrowNode = arrowNode.updated(scale: arrowNode.scale * currentScale)

        // 重置变换，只保留旋转
        transform = CGAffineTransform(rotationAngle: arrowNode.rotation)

        syncToNode()
        onOperationEnd?(arrowNode, arrowNode)

    default:
        break
    }
}
```

**步骤 4：添加旋转手势处理**

```swift
@objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
    switch gesture.state {
    case .began:
        onOperationStart?(arrowNode)

    case .changed:
        // 应用旋转变换
        transform = transform.rotated(by: gesture.rotation)
        gesture.rotation = 0 // 重置以累积变换

    case .ended:
        // 从变换矩阵提取旋转角度
        let currentRotation = atan2(transform.b, transform.a)
        arrowNode = arrowNode.updated(rotation: currentRotation)

        syncToNode()
        onOperationEnd?(arrowNode, arrowNode)

    default:
        break
    }
}
```

**步骤 5：修改手势代理方法**

替换第 247-252 行的 `shouldRecognizeSimultaneouslyWith` 实现：
```swift
func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
) -> Bool {
    // 允许缩放和旋转同时进行
    if (gestureRecognizer == pinchGesture && otherGestureRecognizer == rotateGesture) ||
       (gestureRecognizer == rotateGesture && otherGestureRecognizer == pinchGesture) {
        return true
    }
    return false
}
```

**步骤 6：修改 enableArrowGestures() 方法**

```swift
func enableArrowGestures() {
    isUserInteractionEnabled = true
    panGesture.isEnabled = true
    tapGesture.isEnabled = true
    pinchGesture.isEnabled = true   // [新增]
    rotateGesture.isEnabled = true  // [新增]
}
```

**步骤 7：修改 updateFromNode() 方法**

```swift
func updateFromNode() {
    frame = arrowNode.bounds
    transform = CGAffineTransform(rotationAngle: arrowNode.rotation) // [新增]
    updateArrowPath()
    updateSelectionAppearance()
}
```

#### 4.1.3 修改 NativeCanvasView 撤销操作

**文件**：`Views/Editor/Canvas/NativeCanvasView.swift`

修改 `createArrowView` 方法（第 402-416 行），添加缩放和旋转的撤销支持：

```swift
arrowView.onOperationEnd = { [weak self] _, endArrow in
    guard let self = self, let startArrow = operationStartArrow else { return }

    // 检查是否移动
    if startArrow.startPoint != endArrow.startPoint || startArrow.endPoint != endArrow.endPoint {
        let action = MoveArrowAction(
            arrowID: startArrow.id,
            fromArrow: startArrow,
            toArrow: endArrow,
            canvasView: self
        )
        NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
    }
    // [新增] 检查是否缩放
    else if abs(startArrow.scale - endArrow.scale) > 0.01 {
        let action = ScaleArrowAction(
            arrowID: startArrow.id,
            fromArrow: startArrow,
            toArrow: endArrow,
            canvasView: self
        )
        NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
    }
    // [新增] 检查是否旋转
    else if abs(startArrow.rotation - endArrow.rotation) > 0.001 {
        let action = RotateArrowAction(
            arrowID: startArrow.id,
            fromArrow: startArrow,
            toArrow: endArrow,
            canvasView: self
        )
        NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
    }

    operationStartArrow = nil
}
```

#### 4.1.4 新增撤销操作类

**文件**：`Models/Canvas/CanvasAction.swift`

添加以下类：

```swift
// MARK: - 箭头缩放操作
class ScaleArrowAction: CanvasAction {
    let arrowID: UUID
    let fromArrow: ArrowLayerNode
    let toArrow: ArrowLayerNode
    weak var canvasView: NativeCanvasView?

    init(arrowID: UUID, fromArrow: ArrowLayerNode, toArrow: ArrowLayerNode, canvasView: NativeCanvasView) {
        self.arrowID = arrowID
        self.fromArrow = fromArrow
        self.toArrow = toArrow
        self.canvasView = canvasView
    }

    func execute() {
        canvasView?.updateArrow(toArrow)
    }

    func undo() {
        canvasView?.updateArrow(fromArrow)
    }
}

// MARK: - 箭头旋转操作
class RotateArrowAction: CanvasAction {
    let arrowID: UUID
    let fromArrow: ArrowLayerNode
    let toArrow: ArrowLayerNode
    weak var canvasView: NativeCanvasView?

    init(arrowID: UUID, fromArrow: ArrowLayerNode, toArrow: ArrowLayerNode, canvasView: NativeCanvasView) {
        self.arrowID = arrowID
        self.fromArrow = fromArrow
        self.toArrow = toArrow
        self.canvasView = canvasView
    }

    func execute() {
        canvasView?.updateArrow(toArrow)
    }

    func undo() {
        canvasView?.updateArrow(fromArrow)
    }
}
```

---

### 4.2 Phase 2：图形工具弹出菜单

#### 4.2.1 新增形状类型枚举

**新建文件**：`Models/Canvas/ShapeType.swift`

```swift
import Foundation

/// 形状类型枚举
enum ShapeType: String, CaseIterable, Identifiable, Codable {
    case rectangle = "rectangle"
    case circle = "circle"
    case triangle = "triangle"
    case diamond = "diamond"      // 菱形
    case star = "star"            // 五角星
    case hexagon = "hexagon"      // 六边形

    var id: String { rawValue }

    /// SF Symbol 图标名
    var iconName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .triangle: return "triangle"
        case .diamond: return "diamond"
        case .star: return "star"
        case .hexagon: return "hexagon"
        }
    }

    /// 显示名称
    var displayName: String {
        switch self {
        case .rectangle: return "矩形"
        case .circle: return "圆形"
        case .triangle: return "三角形"
        case .diamond: return "菱形"
        case .star: return "五角星"
        case .hexagon: return "六边形"
        }
    }

    /// 主选择器显示的形状（第一批支持）
    static var primaryShapes: [ShapeType] {
        [.rectangle, .circle, .triangle]
    }

    /// 所有可用形状
    static var allShapes: [ShapeType] {
        allCases
    }
}
```

#### 4.2.2 新增形状选择弹出框

**新建文件**：`Views/Editor/Canvas/ShapePickerPopover.swift`

```swift
import SwiftUI

/// 形状选择弹出框
struct ShapePickerPopover: View {
    let shapes: [ShapeType]
    let onShapeSelected: (ShapeType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            Text("选择形状")
                .font(.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()

            // 形状网格
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(shapes) { shape in
                    ShapeButton(shape: shape) {
                        onShapeSelected(shape)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}

/// 形状按钮
private struct ShapeButton: View {
    let shape: ShapeType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: shape.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(Theme.Colors.primaryText)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )

                Text(shape.displayName)
                    .font(.caption2)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ShapePickerPopover(shapes: ShapeType.primaryShapes) { shape in
        print("Selected: \(shape.displayName)")
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}
```

#### 4.2.3 修改 CanvasToolbar

**文件**：`Views/Editor/Canvas/CanvasToolbar.swift`

```swift
import SwiftUI

/// 底部工具栏
struct CanvasToolbar: View {
    @Binding var currentTool: CanvasTool
    var onImageImport: () -> Void
    var onShapeSelected: ((ShapeType) -> Void)?  // [新增]

    // [新增] 形状选择器弹出状态
    @State private var showShapePicker = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(CanvasTool.mainToolbarTools, id: \.self) { tool in
                if tool == .rectangle {
                    // [新增] 图形工具特殊处理 - 弹出选择器
                    ShapeToolButton(
                        tool: tool,
                        isSelected: currentTool == tool,
                        showPicker: $showShapePicker,
                        onShapeSelected: { shape in
                            showShapePicker = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentTool = .rectangle
                            }
                            onShapeSelected?(shape)
                        }
                    )
                } else {
                    ToolButton(
                        tool: tool,
                        isSelected: currentTool == tool,
                        action: {
                            if tool == .image {
                                onImageImport()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    currentTool = tool
                                }
                            }
                        }
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 形状工具按钮（带弹出选择器）

private struct ShapeToolButton: View {
    let tool: CanvasTool
    let isSelected: Bool
    @Binding var showPicker: Bool
    let onShapeSelected: (ShapeType) -> Void

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
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            ShapePickerPopover(shapes: ShapeType.primaryShapes) { shape in
                onShapeSelected(shape)
            }
        }
    }
}

// MARK: - 普通工具按钮

private struct ToolButton: View {
    let tool: CanvasTool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
    }
}
```

#### 4.2.4 修改 NativeEditorView

**文件**：`Views/Editor/NativeEditorView.swift`

在 `NativeCanvasContainer` 中更新 CanvasToolbar 调用：

```swift
// 底部：工具栏
VStack {
    Spacer()
    CanvasToolbar(
        currentTool: $viewModel.stateManager.currentTool,
        onImageImport: onImageImport,
        onShapeSelected: { shapeType in
            viewModel.selectedShapeType = shapeType
        }
    )
    .padding(.bottom, Theme.Spacing.xl)
}
```

在 `NativeEditorViewModel` 中添加：
```swift
/// 当前选中的形状类型
var selectedShapeType: ShapeType = .rectangle
```

---

### 4.3 Phase 3：通用形状视图实现

#### 4.3.1 新增 ShapeLayerNode 数据模型

**新建文件**：`Models/Canvas/ShapeLayerNode.swift`

```swift
import Foundation
import CoreGraphics

/// 通用形状图层节点
struct ShapeLayerNode: Codable, Identifiable {
    let id: UUID
    var frame: CGRect           // 位置和尺寸
    var rotation: Double        // 旋转角度（弧度）
    let shapeType: ShapeType    // 形状类型
    let color: String           // 填充/描边颜色
    let lineWidth: CGFloat      // 描边宽度
    let isFilled: Bool          // 是否填充
    let zIndex: Int
    let createdAt: Date

    /// 形状中心点
    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    /// 创建形状图层
    init(
        frame: CGRect,
        shapeType: ShapeType,
        color: String = "#000000",
        lineWidth: CGFloat = 2,
        isFilled: Bool = false,
        rotation: Double = 0,
        zIndex: Int = 0
    ) {
        self.id = UUID()
        self.frame = frame
        self.rotation = rotation
        self.shapeType = shapeType
        self.color = color
        self.lineWidth = lineWidth
        self.isFilled = isFilled
        self.zIndex = zIndex
        self.createdAt = Date()
    }

    /// 更新形状属性
    func updated(
        frame: CGRect? = nil,
        rotation: Double? = nil,
        color: String? = nil,
        lineWidth: CGFloat? = nil,
        isFilled: Bool? = nil,
        zIndex: Int? = nil
    ) -> ShapeLayerNode {
        var node = self
        if let frame = frame { node.frame = frame }
        if let rotation = rotation { node.rotation = rotation }
        // 其他属性由于是 let，需要创建新实例
        return ShapeLayerNode(
            frame: frame ?? self.frame,
            shapeType: self.shapeType,
            color: color ?? self.color,
            lineWidth: lineWidth ?? self.lineWidth,
            isFilled: isFilled ?? self.isFilled,
            rotation: rotation ?? self.rotation,
            zIndex: zIndex ?? self.zIndex
        )
    }
}

/// 形状图层管理器
class ShapeLayerManager: ObservableObject {
    @Published var shapes: [ShapeLayerNode] = []

    func addShape(_ shape: ShapeLayerNode) {
        shapes.append(shape)
        sortByZIndex()
    }

    func removeShape(id: UUID) {
        shapes.removeAll { $0.id == id }
    }

    func updateShape(_ shape: ShapeLayerNode) {
        if let index = shapes.firstIndex(where: { $0.id == shape.id }) {
            shapes[index] = shape
            sortByZIndex()
        }
    }

    private func sortByZIndex() {
        shapes.sort { $0.zIndex < $1.zIndex }
    }

    func getNextZIndex() -> Int {
        (shapes.map(\.zIndex).max() ?? 0) + 1
    }

    func clearAll() {
        shapes.removeAll()
    }
}
```

#### 4.3.2 新增 SelectableShapeView

**新建文件**：`Views/Editor/Canvas/SelectableShapeView.swift`

```swift
import UIKit

/// 可选择的通用形状视图
/// 支持选择、拖拽、缩放和旋转
class SelectableShapeView: UIView {

    // MARK: - Properties

    var shapeNode: ShapeLayerNode {
        didSet {
            updateFromNode()
        }
    }

    private let shapeLayer = CAShapeLayer()
    private let selectionBorder = CAShapeLayer()

    var isSelected: Bool = false {
        didSet {
            updateSelectionAppearance()
        }
    }

    // 手势识别器
    private var tapGesture: UITapGestureRecognizer!
    private var panGesture: UIPanGestureRecognizer!
    private var pinchGesture: UIPinchGestureRecognizer!
    private var rotateGesture: UIRotationGestureRecognizer!

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
        shapeLayer.fillColor = shapeNode.isFilled ? UIColor(Color.fromHex(shapeNode.color) ?? .black).cgColor : UIColor.clear.cgColor
        shapeLayer.strokeColor = UIColor(Color.fromHex(shapeNode.color) ?? .black).cgColor
        shapeLayer.lineWidth = shapeNode.lineWidth
        layer.addSublayer(shapeLayer)

        // 选中边框
        selectionBorder.strokeColor = UIColor.systemBlue.cgColor
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.lineWidth = 2
        selectionBorder.lineDashPattern = [6, 3]
        selectionBorder.isHidden = true
        layer.addSublayer(selectionBorder)
    }

    private func setupGestures() {
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(panGesture)

        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        addGestureRecognizer(pinchGesture)

        rotateGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        addGestureRecognizer(rotateGesture)

        panGesture.delegate = self
        pinchGesture.delegate = self
        rotateGesture.delegate = self
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
        }

        shapeLayer.path = path.cgPath
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onSelected?(shapeNode.id)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            onOperationStart?(shapeNode)
        case .changed:
            let translation = gesture.translation(in: superview)
            center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
            gesture.setTranslation(.zero, in: superview)
        case .ended:
            syncToNode()
            onOperationEnd?(shapeNode, shapeNode)
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            onOperationStart?(shapeNode)
        case .changed:
            transform = transform.scaledBy(x: gesture.scale, y: gesture.scale)
            gesture.scale = 1.0
        case .ended:
            // 更新 frame 尺寸
            let newWidth = bounds.width * abs(transform.a)
            let newHeight = bounds.height * abs(transform.d)
            bounds.size = CGSize(width: newWidth, height: newHeight)
            transform = CGAffineTransform(rotationAngle: shapeNode.rotation)
            syncToNode()
            onOperationEnd?(shapeNode, shapeNode)
        default:
            break
        }
    }

    @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            onOperationStart?(shapeNode)
        case .changed:
            transform = transform.rotated(by: gesture.rotation)
            gesture.rotation = 0
        case .ended:
            syncToNode()
            onOperationEnd?(shapeNode, shapeNode)
        default:
            break
        }
    }

    private func syncToNode() {
        shapeNode = shapeNode.updated(
            frame: frame,
            rotation: atan2(transform.b, transform.a)
        )
        onNodeUpdated?(shapeNode)
    }

    // MARK: - Appearance

    private func updateSelectionAppearance() {
        selectionBorder.isHidden = !isSelected
        if isSelected {
            let borderRect = bounds.insetBy(dx: -8, dy: -8)
            selectionBorder.path = UIBezierPath(rect: borderRect).cgPath
        }
    }

    func enableShapeGestures() {
        isUserInteractionEnabled = true
        panGesture.isEnabled = true
        tapGesture.isEnabled = true
        pinchGesture.isEnabled = true
        rotateGesture.isEnabled = true
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
            let borderRect = bounds.insetBy(dx: -8, dy: -8)
            selectionBorder.path = UIBezierPath(rect: borderRect).cgPath
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SelectableShapeView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // 允许缩放和旋转同时进行
        if (gestureRecognizer == pinchGesture && otherGestureRecognizer == rotateGesture) ||
           (gestureRecognizer == rotateGesture && otherGestureRecognizer == pinchGesture) {
            return true
        }
        return false
    }
}
```

#### 4.3.3 集成到 NativeCanvasView

**文件**：`Views/Editor/Canvas/NativeCanvasView.swift`

**步骤 1：添加形状管理属性**

```swift
// 在类属性区域添加
private var shapeLayerManager = ShapeLayerManager()
private var shapeViews: [UUID: SelectableShapeView] = [:]
var onShapeCreated: ((ShapeLayerNode) -> Void)?
```

**步骤 2：添加形状管理方法**

```swift
// MARK: - Shape Operations

func addShape(_ shape: ShapeLayerNode, recordUndo: Bool = true) {
    shapeLayerManager.addShape(shape)
    createShapeView(for: shape)

    if recordUndo {
        let action = AddShapeAction(shape: shape, canvasView: self)
        NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
    }
}

func removeShape(id: UUID, recordUndo: Bool = true) {
    guard let shape = shapeLayerManager.shapes.first(where: { $0.id == id }) else { return }

    shapeViews[id]?.removeFromSuperview()
    shapeViews.removeValue(forKey: id)
    shapeLayerManager.removeShape(id: id)

    if recordUndo {
        let action = RemoveShapeAction(shape: shape, canvasView: self)
        NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
    }
}

func updateShape(_ shape: ShapeLayerNode) {
    shapeLayerManager.updateShape(shape)
    shapeViews[shape.id]?.shapeNode = shape
}

private func createShapeView(for shape: ShapeLayerNode) {
    let shapeView = SelectableShapeView(shapeNode: shape)

    var operationStartShape: ShapeLayerNode?

    shapeView.onNodeUpdated = { [weak self] updatedShape in
        self?.shapeLayerManager.updateShape(updatedShape)
    }

    shapeView.onSelected = { [weak self] shapeID in
        self?.selectedNodeID = shapeID
    }

    shapeView.onOperationStart = { shape in
        operationStartShape = shape
    }

    shapeView.onOperationEnd = { [weak self] _, endShape in
        guard let self = self, let startShape = operationStartShape else { return }

        // 检查变换类型并记录撤销操作
        if startShape.frame.origin != endShape.frame.origin &&
           startShape.frame.size == endShape.frame.size {
            // 移动
            let action = MoveShapeAction(
                shapeID: startShape.id,
                fromShape: startShape,
                toShape: endShape,
                canvasView: self
            )
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        } else if startShape.frame.size != endShape.frame.size {
            // 缩放
            let action = ScaleShapeAction(
                shapeID: startShape.id,
                fromShape: startShape,
                toShape: endShape,
                canvasView: self
            )
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        } else if abs(startShape.rotation - endShape.rotation) > 0.001 {
            // 旋转
            let action = RotateShapeAction(
                shapeID: startShape.id,
                fromShape: startShape,
                toShape: endShape,
                canvasView: self
            )
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }

        operationStartShape = nil
    }

    shapeViews[shape.id] = shapeView
    objectLayerView.addSubview(shapeView)

    if currentTool == .select || currentTool == .rectangle {
        shapeView.enableShapeGestures()
    }
}
```

**步骤 3：修改 updateSelectionStates()**

```swift
private func updateSelectionStates() {
    // 更新图片视图选中状态
    for (id, imageView) in imageViews {
        imageView.isSelected = (id == selectedNodeID)
    }

    // 更新箭头视图选中状态
    for (id, arrowView) in arrowViews {
        arrowView.isSelected = (id == selectedNodeID)
    }

    // [新增] 更新形状视图选中状态
    for (id, shapeView) in shapeViews {
        shapeView.isSelected = (id == selectedNodeID)
    }

    onSelectionChanged?(selectedNodeID != nil)
}
```

**步骤 4：修改 updateForTool() 中的 .select 分支**

```swift
case .select:
    // ... 现有代码 ...

    // 确保所有对象的手势都能正常工作
    for imageView in imageViews.values {
        imageView.enableObjectGestures()
    }
    for arrowView in arrowViews.values {
        arrowView.enableArrowGestures()
    }
    // [新增]
    for shapeView in shapeViews.values {
        shapeView.enableShapeGestures()
    }
```

---

## 五、文件修改清单

### 5.1 需要修改的文件

| 文件路径 | 修改类型 | 修改内容 |
|---------|---------|---------|
| `Models/Canvas/ArrowLayerNode.swift` | 修改 | 添加 rotation、scale 属性 |
| `Views/Editor/Canvas/SelectableArrowView.swift` | 修改 | 添加缩放/旋转手势 |
| `Views/Editor/Canvas/CanvasToolbar.swift` | 修改 | 添加形状选择弹出菜单 |
| `Views/Editor/Canvas/NativeCanvasView.swift` | 修改 | 集成形状管理 |
| `Views/Editor/NativeEditorView.swift` | 修改 | 连接形状选择回调 |
| `ViewModels/NativeEditorViewModel.swift` | 修改 | 添加 selectedShapeType 属性 |
| `Models/Canvas/CanvasAction.swift` | 修改 | 添加形状相关撤销操作 |

### 5.2 需要新建的文件

| 文件路径 | 说明 |
|---------|------|
| `Models/Canvas/ShapeType.swift` | 形状类型枚举 |
| `Models/Canvas/ShapeLayerNode.swift` | 通用形状数据模型 |
| `Views/Editor/Canvas/ShapePickerPopover.swift` | 形状选择弹出框 |
| `Views/Editor/Canvas/SelectableShapeView.swift` | 通用可选择形状视图 |

### 5.3 可以删除的文件（可选）

| 文件路径 | 说明 |
|---------|------|
| `Models/Canvas/RectangleLayerNode.swift` | 被 ShapeLayerNode 替代 |
| `Views/Editor/Canvas/RectangleView.swift` | 被 SelectableShapeView 替代 |

---

## 六、实施步骤

### 6.1 Phase 1：箭头缩放旋转（预计 2-3 小时）

1. 修改 `ArrowLayerNode` 添加 rotation 和 scale 属性
2. 修改 `SelectableArrowView` 添加缩放和旋转手势
3. 添加对应的撤销操作类
4. 测试验证

### 6.2 Phase 2：图形工具弹出菜单（预计 1-2 小时）

1. 创建 `ShapeType.swift`
2. 创建 `ShapePickerPopover.swift`
3. 修改 `CanvasToolbar.swift`
4. 测试验证

### 6.3 Phase 3：通用形状视图（预计 3-4 小时）

1. 创建 `ShapeLayerNode.swift`
2. 创建 `SelectableShapeView.swift`
3. 集成到 `NativeCanvasView`
4. 添加撤销操作支持
5. 测试验证

---

## 七、测试用例

### 7.1 箭头变换测试

| 测试项 | 操作步骤 | 预期结果 |
|-------|---------|---------|
| 箭头移动 | 选择工具 → 单指拖拽箭头 | 箭头跟随手指移动 |
| 箭头缩放 | 选择工具 → 双指捏合箭头 | 箭头等比例缩放 |
| 箭头旋转 | 选择工具 → 双指旋转箭头 | 箭头绕中心旋转 |
| 同时缩放旋转 | 双指同时捏合和旋转 | 箭头同时缩放和旋转 |
| 撤销移动 | 移动箭头 → 点击撤销 | 箭头回到原位置 |
| 撤销缩放 | 缩放箭头 → 点击撤销 | 箭头恢复原尺寸 |
| 撤销旋转 | 旋转箭头 → 点击撤销 | 箭头恢复原角度 |

### 7.2 图形工具测试

| 测试项 | 操作步骤 | 预期结果 |
|-------|---------|---------|
| 弹出菜单 | 点击图形工具按钮 | 弹出形状选择菜单 |
| 选择矩形 | 弹出菜单 → 点击矩形 | 工具切换为矩形，菜单关闭 |
| 选择圆形 | 弹出菜单 → 点击圆形 | 工具切换为圆形，菜单关闭 |
| 选择三角形 | 弹出菜单 → 点击三角形 | 工具切换为三角形，菜单关闭 |

### 7.3 形状变换测试

| 测试项 | 操作步骤 | 预期结果 |
|-------|---------|---------|
| 创建矩形 | 选择矩形工具 → 画布拖拽 | 创建矩形并保持可见 |
| 创建圆形 | 选择圆形工具 → 画布拖拽 | 创建圆形并保持可见 |
| 形状移动 | 选择工具 → 拖拽形状 | 形状跟随移动 |
| 形状缩放 | 选择工具 → 双指捏合形状 | 形状等比例缩放 |
| 形状旋转 | 选择工具 → 双指旋转形状 | 形状绕中心旋转 |

---

## 八、参考资料

- [Moving and Transforming Views with Gestures - CodePath](https://guides.codepath.com/ios/Moving-and-Transforming-Views-with-Gestures)
- [CGAffineTransform - Hacking with Swift](https://www.hackingwithswift.com/example-code/uikit/how-to-scale-stretch-move-and-rotate-uiviews-using-cgaffinetransform)
- [aheze/Popovers - GitHub](https://github.com/aheze/Popovers)
- [SwiftUI Popovers and Popup Menus](https://www.swiftyplace.com/blog/swiftui-popovers-and-popups)

---

## 九、风险与注意事项

1. **手势冲突**：确保缩放和旋转手势可以同时识别，需正确实现 `UIGestureRecognizerDelegate`
2. **坐标系统**：变换后需正确同步 frame 和 transform，避免坐标漂移
3. **性能考虑**：频繁的变换操作不应导致卡顿，避免在手势回调中做复杂计算
4. **撤销栈溢出**：确保撤销操作正确实现，避免内存泄漏
5. **向后兼容**：新的数据模型需要兼容旧版本保存的数据
