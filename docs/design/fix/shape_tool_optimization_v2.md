# 图形工具与对象变换优化方案 v2.0

## 文档信息

- **版本**: v2.0
- **日期**: 2025-12-15
- **状态**: 待实施
- **优先级**: 高

---

## 一、问题清单

### 1.1 问题1：箭头在选择工具下无法缩放和旋转

**现象描述**:
- 箭头对象可以拖动移动
- 双指捏合/旋转手势无效

**根因分析**:

经过代码审查，发现 `SelectableArrowView` 中已经实现了 `handlePinch` 和 `handleRotate` 方法，但问题在于**箭头视图的 transform 应用逻辑有缺陷**：

```swift
// SelectableArrowView.swift 第 218-231 行
@objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
    case .ended:
        let currentScale = sqrt(transform.a * transform.a + transform.c * transform.c)
        arrowNode = arrowNode.updated(scale: arrowNode.scale * currentScale)
        // 问题：这里重置 transform 只保留旋转，但没有重新绘制箭头路径
        transform = CGAffineTransform(rotationAngle: arrowNode.rotation)
        syncToNode()
        // ...
}
```

**核心问题**：
1. 缩放后 `updateArrowPath()` 未被调用，箭头路径没有根据新的 scale 重新计算
2. `ArrowLayerNode.bounds` 计算正确考虑了 scale，但视图的 `frame` 没有同步更新
3. `updateFromNode()` 方法只设置了 `transform` 的 rotation，没有处理 scale

### 1.2 问题2：图形工具弹出方向错误且样式不佳

**现象描述**:
- 弹出框出现在按钮下方而非上方
- 只有三种形状（圆形、矩形、三角形）
- 样式较为简陋

**根因分析**:

```swift
// CanvasToolbar.swift 第 105 行
.popover(isPresented: $showPicker, arrowEdge: .top) {
    ShapePickerPopover(...)
}
```

`arrowEdge: .top` 表示**箭头指向上方**，即弹出框在按钮下方。这与预期相反。

此外，在 iPhone/iPad compact 模式下，SwiftUI 的 `.popover` 会自动转换为 sheet，需要添加 `presentationCompactAdaptation(.popover)` 来强制使用 popover 样式。

**形状种类不足**：
```swift
// ShapeType.swift 第 38-41 行
static var primaryShapes: [ShapeType] {
    [.rectangle, .circle, .triangle]  // 只有 3 种
}
```

### 1.3 问题3：形状释放后立即消失

**现象描述**:
- 拖动绘制形状时可以看到预览
- 手指释放后形状消失

**根因分析**:

这是**坐标系统不一致**导致的问题：

```swift
// NativeEditorView.swift 第 395-414 行
ShapeDrawingGestureView(...) { rect in
    // 问题：这里的 rect 是 SwiftUI 视图坐标，没有转换为画布内容坐标！
    let shape = ShapeLayerNode(
        frame: rect,  // 直接使用视图坐标
        ...
    )
    viewModel.canvasView?.addShape(shape)
}
```

对比箭头的实现：
```swift
// NativeEditorView.swift 第 344-368 行
ArrowDrawingView(...) { start, end in
    // 箭头正确进行了坐标转换
    let offset = canvasView.pencilCanvas.contentOffset
    let scale = canvasView.pencilCanvas.zoomScale
    let contentStart = CGPoint(
        x: (start.x + offset.x) / scale,
        y: (start.y + offset.y) / scale
    )
    // ...
}
```

**形状的绘制缺少坐标转换！** 这导致：
1. 形状被创建在视图坐标系（例如 x:100, y:200）
2. 而 `objectLayerView` 是 5000x5000 的画布内容坐标系
3. 如果用户在画布中心区域绘制，视图坐标可能是 (300, 400)
4. 但画布 contentOffset 可能是 (2127, 2016)，形状实际应该在 (2427, 2416)
5. 由于坐标不匹配，形状被创建在画布可见区域之外，所以"消失"了

---

## 二、解决方案

### 2.1 架构设计原则

参考 [Figma Shape Tools](https://help.figma.com/hc/en-us/articles/360040450133-Shape-tools) 和 [Figma Draw](https://www.figma.com/draw/) 的设计：

1. **统一对象模型**：所有可绘制对象（箭头、直线、形状）使用统一的变换属性（position, scale, rotation）
2. **坐标系一致性**：所有对象的坐标都在画布内容坐标系中
3. **手势处理统一**：所有可选择对象支持相同的手势操作（拖拽、缩放、旋转）
4. **UI 直觉性**：弹出菜单位置符合预期，样式现代美观

### 2.2 形状类型扩展

参考 Figma 的形状工具，扩展形状类型：

| 类型 | 图标 | 说明 |
|------|------|------|
| 矩形 | `rectangle` | 基础矩形 |
| 圆形 | `circle` | 圆/椭圆 |
| 三角形 | `triangle` | 等边三角形 |
| 菱形 | `diamond` | 菱形 |
| 五角星 | `star` | 五角星 |
| 六边形 | `hexagon` | 正六边形 |
| **箭头** | `arrow.right` | **从箭头工具移入** |
| **直线** | `line.diagonal` | **新增** |
| 圆角矩形 | `rectangle.roundedcorners` | **新增** |

---

## 三、详细实现方案

### 3.1 Phase 1：修复形状消失问题（最高优先级）

#### 3.1.1 修改 ShapeDrawingGestureView 添加坐标转换

**文件**: `Views/Editor/Canvas/ShapeDrawingView.swift`

在 `ShapeDrawingGestureView` 的 `onEnded` 回调中，需要将视图坐标转换为画布内容坐标。但由于 `ShapeDrawingGestureView` 无法直接访问 `canvasView`，需要修改回调签名：

**修改前**:
```swift
let onShapeCreated: (CGRect) -> Void
```

**修改后**:
```swift
/// 形状创建回调，传入视图坐标系的矩形
/// 调用方负责进行坐标转换
let onShapeCreated: (CGRect) -> Void
```

**真正的修复在 NativeEditorView.swift**:

**文件**: `Views/Editor/NativeEditorView.swift`

找到第 403-414 行的形状创建回调，添加坐标转换：

```swift
// 形状绘制手势
ShapeDrawingGestureView(
    isDrawing: $isDrawingRectangle,
    startPoint: $rectangleStartPoint,
    endPoint: $rectangleEndPoint,
    shapeType: viewModel.selectedShapeType,
    color: Color.fromHex(viewModel.stateManager.rectangleColor) ?? .blue,
    lineWidth: viewModel.stateManager.rectangleLineWidth,
    isFilled: viewModel.stateManager.rectangleIsFilled
) { viewportRect in
    // [修复] 坐标转换：SwiftUI 视图坐标 -> 画布内容坐标
    guard let canvasView = viewModel.canvasView else { return }

    let offset = canvasView.pencilCanvas.contentOffset
    let scale = canvasView.pencilCanvas.zoomScale

    // 转换矩形的每个坐标
    let contentRect = CGRect(
        x: (viewportRect.origin.x + offset.x) / scale,
        y: (viewportRect.origin.y + offset.y) / scale,
        width: viewportRect.width / scale,
        height: viewportRect.height / scale
    )

    // 创建形状图层（使用内容坐标）
    let shape = ShapeLayerNode(
        frame: contentRect,
        shapeType: viewModel.selectedShapeType,
        color: viewModel.stateManager.rectangleColor,
        lineWidth: viewModel.stateManager.rectangleLineWidth,
        isFilled: viewModel.stateManager.rectangleIsFilled,
        zIndex: canvasView.getShapeLayerManager().getNextZIndex()
    )
    canvasView.addShape(shape)
}
```

#### 3.1.2 修改 ShapeDrawingView 预览位置

形状预览也需要考虑坐标系统。当前的预览是在 SwiftUI 层渲染的，位置是正确的（因为是视图坐标）。但为了一致性，建议：

**方案 A（推荐）**: 保持现有预览逻辑不变，因为预览本身就应该在视图坐标系中显示

**方案 B**: 如果发现预览有问题，可以考虑将预览也移到 UIKit 层（与箭头预览类似）

### 3.2 Phase 2：修复箭头缩放和旋转

#### 3.2.1 修改 SelectableArrowView 的变换逻辑

**文件**: `Views/Editor/Canvas/SelectableArrowView.swift`

**问题核心**：当前的实现在手势结束时重置了 transform，但没有正确更新视图的 frame 和箭头路径。

**修改 updateFromNode() 方法**（第 111-116 行）:

```swift
/// 从节点更新视图
func updateFromNode() {
    // [修复] 先重置 transform，再设置 frame
    transform = .identity
    frame = arrowNode.bounds

    // 应用旋转（scale 已经体现在 bounds 计算中）
    transform = CGAffineTransform(rotationAngle: arrowNode.rotation)

    updateArrowPath()
    updateSelectionAppearance()
}
```

**修改 handlePinch() 方法**（第 208-232 行）:

```swift
@objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
    switch gesture.state {
    case .began:
        onOperationStart?(arrowNode)

    case .changed:
        // 应用缩放变换到视觉效果
        transform = transform.scaledBy(x: gesture.scale, y: gesture.scale)
        gesture.scale = 1.0

    case .ended:
        // [修复] 计算累积的缩放比例
        let currentScaleX = sqrt(transform.a * transform.a + transform.c * transform.c)
        let newScale = arrowNode.scale * currentScaleX

        // 更新节点数据
        arrowNode = arrowNode.updated(scale: newScale)

        // [修复] 重新从节点同步视图（这会重新计算 frame 和 path）
        updateFromNode()

        syncToNode()
        onOperationEnd?(arrowNode, arrowNode)

    default:
        break
    }
}
```

**修改 handleRotate() 方法**（第 234-255 行）:

```swift
@objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
    switch gesture.state {
    case .began:
        onOperationStart?(arrowNode)

    case .changed:
        // 应用旋转变换到视觉效果
        transform = transform.rotated(by: gesture.rotation)
        gesture.rotation = 0

    case .ended:
        // [修复] 从当前 transform 提取旋转角度
        let currentRotation = atan2(transform.b, transform.a)

        // 更新节点数据
        arrowNode = arrowNode.updated(rotation: currentRotation)

        // [修复] 重新从节点同步视图
        updateFromNode()

        syncToNode()
        onOperationEnd?(arrowNode, arrowNode)

    default:
        break
    }
}
```

#### 3.2.2 修改 updateArrowPath() 考虑缩放

**文件**: `Views/Editor/Canvas/SelectableArrowView.swift`

当前的 `updateArrowPath()` 方法没有考虑缩放。由于 `bounds` 已经根据 scale 计算好了尺寸，路径绘制应该使用 bounds 的相对坐标：

```swift
/// 更新箭头路径
private func updateArrowPath() {
    let path = UIBezierPath()

    // [修复] 获取缩放后的 bounds
    let scaledBounds = bounds

    // 计算原始起点终点相对于中心的偏移
    let originalCenter = arrowNode.center
    let originalStartOffset = CGPoint(
        x: arrowNode.startPoint.x - originalCenter.x,
        y: arrowNode.startPoint.y - originalCenter.y
    )
    let originalEndOffset = CGPoint(
        x: arrowNode.endPoint.x - originalCenter.x,
        y: arrowNode.endPoint.y - originalCenter.y
    )

    // 应用缩放
    let scale = arrowNode.scale
    let localStart = CGPoint(
        x: scaledBounds.width / 2 + originalStartOffset.x * scale,
        y: scaledBounds.height / 2 + originalStartOffset.y * scale
    )
    let localEnd = CGPoint(
        x: scaledBounds.width / 2 + originalEndOffset.x * scale,
        y: scaledBounds.height / 2 + originalEndOffset.y * scale
    )

    // 绘制箭头主线
    path.move(to: localStart)
    path.addLine(to: localEnd)

    // 计算箭头角度
    let angle = atan2(localEnd.y - localStart.y, localEnd.x - localStart.x)

    // 箭头大小也需要缩放
    let arrowLength: CGFloat = 20 * scale
    let arrowAngle: CGFloat = .pi / 6

    // 绘制箭头两侧
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

    arrowLayer.path = path.cgPath
}
```

### 3.3 Phase 3：重构形状选择弹出菜单

#### 3.3.1 扩展 ShapeType 枚举

**文件**: `Models/Canvas/ShapeType.swift`

```swift
import Foundation

/// 形状类型枚举
enum ShapeType: String, CaseIterable, Identifiable, Codable {
    // 基础形状
    case rectangle = "rectangle"
    case roundedRectangle = "roundedRectangle"  // [新增]
    case circle = "circle"
    case triangle = "triangle"
    case diamond = "diamond"
    case star = "star"
    case hexagon = "hexagon"

    // 线条类（从箭头工具移入）
    case line = "line"      // [新增]
    case arrow = "arrow"    // [新增，原箭头工具]

    var id: String { rawValue }

    /// SF Symbol 图标名
    var iconName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .roundedRectangle: return "rectangle.roundedcorners"
        case .circle: return "circle"
        case .triangle: return "triangle"
        case .diamond: return "diamond"
        case .star: return "star"
        case .hexagon: return "hexagon"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.right"
        }
    }

    /// 显示名称
    var displayName: String {
        switch self {
        case .rectangle: return "矩形"
        case .roundedRectangle: return "圆角矩形"
        case .circle: return "圆形"
        case .triangle: return "三角形"
        case .diamond: return "菱形"
        case .star: return "五角星"
        case .hexagon: return "六边形"
        case .line: return "直线"
        case .arrow: return "箭头"
        }
    }

    /// 是否为线条类型（直线/箭头）
    var isLineType: Bool {
        self == .line || self == .arrow
    }

    /// 弹出菜单显示的所有形状
    static var popoverShapes: [ShapeType] {
        [.line, .arrow, .rectangle, .roundedRectangle, .circle, .triangle, .diamond, .star, .hexagon]
    }
}
```

#### 3.3.2 重新设计 ShapePickerPopover

**文件**: `Views/Editor/Canvas/ShapePickerPopover.swift`

参考 [SwiftUI Popovers](https://www.swiftyplace.com/blog/swiftui-popovers-and-popups) 和 [aheze/Popovers](https://github.com/aheze/Popovers) 的设计最佳实践：

```swift
import SwiftUI

/// 形状选择弹出框（重新设计）
struct ShapePickerPopover: View {
    let shapes: [ShapeType]
    let onShapeSelected: (ShapeType) -> Void
    @Environment(\.dismiss) private var dismiss

    // 分组：线条类和形状类
    private var lineShapes: [ShapeType] {
        shapes.filter { $0.isLineType }
    }

    private var basicShapes: [ShapeType] {
        shapes.filter { !$0.isLineType }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 线条工具（第一行）
            if !lineShapes.isEmpty {
                HStack(spacing: 12) {
                    ForEach(lineShapes) { shape in
                        ShapePickerButton(shape: shape) {
                            onShapeSelected(shape)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()
                    .padding(.horizontal, 12)
            }

            // 基础形状（网格布局）
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(basicShapes) { shape in
                    ShapePickerButton(shape: shape) {
                        onShapeSelected(shape)
                        dismiss()
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        )
        // [关键] iOS 16.4+ 强制使用 popover 样式，避免在 iPhone 上变成 sheet
        .presentationCompactAdaptation(.popover)
    }
}

/// 形状按钮（现代化设计）
private struct ShapePickerButton: View {
    let shape: ShapeType
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // 图标
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isPressed ? Color.blue.opacity(0.15) : Color.clear)
                        .frame(width: 48, height: 48)

                    Image(systemName: shape.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.primary, Color.primary.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                // 名称
                Text(shape.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(ShapePickerButtonStyle(isPressed: $isPressed))
    }
}

/// 自定义按钮样式
private struct ShapePickerButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

#Preview {
    ShapePickerPopover(shapes: ShapeType.popoverShapes) { shape in
        print("Selected: \(shape.displayName)")
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
```

#### 3.3.3 修改 CanvasToolbar 弹出方向

**文件**: `Views/Editor/Canvas/CanvasToolbar.swift`

```swift
// 修改第 105 行
.popover(isPresented: $showPicker, arrowEdge: .bottom) {  // [修复] 改为 .bottom
    ShapePickerPopover(shapes: ShapeType.popoverShapes) { shape in
        onShapeSelected(shape)
    }
}
```

**解释**：
- `arrowEdge: .bottom` 表示弹出框的箭头指向下方，即弹出框在按钮上方
- 这符合"工具栏在底部，弹出菜单向上展开"的直觉

#### 3.3.4 统一工具栏，移除独立的箭头工具

**文件**: `Models/Canvas/CanvasTool.swift`

```swift
enum CanvasTool: String, CaseIterable, Identifiable {
    case select = "select"
    case pan = "pan"
    case pen = "pen"
    case eraser = "eraser"
    case shape = "shape"       // [修改] 原 rectangle，改名为 shape
    // case arrow = "arrow"    // [移除] 箭头工具移入形状选择器
    case text = "text"
    case annotation = "annotation"
    case image = "image"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .select: return "选择"
        case .pan: return "平移"
        case .pen: return "画笔"
        case .eraser: return "橡皮擦"
        case .shape: return "形状"  // [修改]
        case .text: return "文字"
        case .annotation: return "标注"
        case .image: return "图片"
        }
    }

    var iconName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pan: return "hand.raised"
        case .pen: return "pencil.tip"
        case .eraser: return "eraser"
        case .shape: return "square.on.circle"  // [修改] 更直观的图标
        case .text: return "textformat"
        case .annotation: return "note.text"
        case .image: return "photo"
        }
    }

    /// 主工具栏显示的工具
    static var mainToolbarTools: [CanvasTool] {
        [.select, .pan, .pen, .eraser, .shape, .text, .image]  // [修改] 移除独立箭头
    }
}
```

### 3.4 Phase 4：统一直线/箭头处理

由于将箭头移入形状工具，需要处理两种情况：
1. 用户选择 `ShapeType.arrow` 时，应该调用原有的箭头创建逻辑
2. 用户选择 `ShapeType.line` 时，创建一条直线（无箭头）

#### 3.4.1 修改 NativeEditorView 处理形状类型

**文件**: `Views/Editor/NativeEditorView.swift`

在 `NativeCanvasContainer` 中修改形状工具的处理逻辑：

```swift
// 形状绘制层（包含直线和箭头）
if viewModel.stateManager.currentTool == .shape {
    ZStack {
        // 根据选中的形状类型显示不同的预览
        if viewModel.selectedShapeType.isLineType {
            // 线条类型（直线/箭头）
            if isDrawingRectangle, let start = rectangleStartPoint, let end = rectangleEndPoint {
                if viewModel.selectedShapeType == .arrow {
                    ArrowView(
                        startPoint: start,
                        endPoint: end,
                        color: Color.fromHex(viewModel.stateManager.rectangleColor) ?? .blue,
                        lineWidth: viewModel.stateManager.rectangleLineWidth
                    )
                } else {
                    // 直线
                    Path { path in
                        path.move(to: start)
                        path.addLine(to: end)
                    }
                    .stroke(
                        Color.fromHex(viewModel.stateManager.rectangleColor) ?? .blue,
                        style: StrokeStyle(
                            lineWidth: viewModel.stateManager.rectangleLineWidth,
                            lineCap: .round
                        )
                    )
                }
            }

            // 线条绘制手势
            LineDrawingGestureView(
                isDrawing: $isDrawingRectangle,
                startPoint: $rectangleStartPoint,
                endPoint: $rectangleEndPoint
            ) { start, end in
                guard let canvasView = viewModel.canvasView else { return }

                // 坐标转换
                let offset = canvasView.pencilCanvas.contentOffset
                let scale = canvasView.pencilCanvas.zoomScale
                let contentStart = CGPoint(
                    x: (start.x + offset.x) / scale,
                    y: (start.y + offset.y) / scale
                )
                let contentEnd = CGPoint(
                    x: (end.x + offset.x) / scale,
                    y: (end.y + offset.y) / scale
                )

                if viewModel.selectedShapeType == .arrow {
                    // 创建箭头
                    let arrow = ArrowLayerNode(
                        startPoint: contentStart,
                        endPoint: contentEnd,
                        color: viewModel.stateManager.rectangleColor,
                        lineWidth: viewModel.stateManager.rectangleLineWidth,
                        zIndex: canvasView.getArrowLayerManager().getNextZIndex()
                    )
                    canvasView.addArrow(arrow)
                } else {
                    // 创建直线（使用 ShapeLayerNode 或新增 LineLayerNode）
                    let line = LineLayerNode(
                        startPoint: contentStart,
                        endPoint: contentEnd,
                        color: viewModel.stateManager.rectangleColor,
                        lineWidth: viewModel.stateManager.rectangleLineWidth,
                        zIndex: canvasView.getShapeLayerManager().getNextZIndex()
                    )
                    canvasView.addLine(line)
                }
            }
        } else {
            // 形状类型（矩形、圆形等）
            // ... 现有的形状绘制逻辑
        }
    }
}
```

#### 3.4.2 新增 LineLayerNode（可选）

如果需要支持直线作为独立对象，可以新增：

**新建文件**: `Models/Canvas/LineLayerNode.swift`

```swift
import Foundation
import CoreGraphics
import Combine

/// 直线图层节点
struct LineLayerNode: Codable, Identifiable {
    let id: UUID
    var startPoint: CGPoint
    var endPoint: CGPoint
    let color: String
    let lineWidth: CGFloat
    let zIndex: Int
    let createdAt: Date
    var rotation: Double = 0.0
    var scale: CGFloat = 1.0

    var bounds: CGRect {
        // 与 ArrowLayerNode 类似的 bounds 计算
        let minX = min(startPoint.x, endPoint.x)
        let minY = min(startPoint.y, endPoint.y)
        let maxX = max(startPoint.x, endPoint.x)
        let maxY = max(startPoint.y, endPoint.y)

        let baseWidth = max(maxX - minX, 40)
        let baseHeight = max(maxY - minY, 40)
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

    init(startPoint: CGPoint, endPoint: CGPoint, color: String = "#000000", lineWidth: CGFloat = 2, zIndex: Int = 0) {
        self.id = UUID()
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.zIndex = zIndex
        self.createdAt = Date()
    }
}
```

**或者**，更简单的方案是复用 `ArrowLayerNode`，添加一个 `hasArrowHead` 属性。

---

## 四、文件修改清单

### 4.1 需要修改的文件

| 文件 | 修改类型 | 修改内容 | 优先级 |
|------|---------|---------|--------|
| `Views/Editor/NativeEditorView.swift` | 修改 | 形状创建添加坐标转换 | P0 |
| `Views/Editor/Canvas/SelectableArrowView.swift` | 修改 | 修复缩放/旋转变换逻辑 | P0 |
| `Views/Editor/Canvas/ShapePickerPopover.swift` | 重写 | 新设计的弹出菜单 | P1 |
| `Views/Editor/Canvas/CanvasToolbar.swift` | 修改 | 弹出方向改为 .bottom | P1 |
| `Models/Canvas/ShapeType.swift` | 修改 | 添加 line/arrow/roundedRectangle | P1 |
| `Models/Canvas/CanvasTool.swift` | 修改 | 移除独立箭头工具 | P2 |
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | 支持 roundedRectangle 路径绘制 | P2 |

### 4.2 可能需要新增的文件

| 文件 | 说明 | 优先级 |
|------|------|--------|
| `Views/Editor/Canvas/LineDrawingGestureView.swift` | 直线绘制手势视图（可选） | P2 |
| `Views/Editor/Canvas/SelectableLineView.swift` | 可选择直线视图（可选） | P2 |
| `Models/Canvas/LineLayerNode.swift` | 直线数据模型（可选） | P2 |

---

## 五、实施步骤

### 5.1 第一阶段（P0 - 必须立即修复）

**目标**: 修复形状消失和箭头变换问题

1. **修复形状消失**
   - 修改 `NativeEditorView.swift` 第 403-414 行
   - 添加视图坐标到画布坐标的转换
   - 验证：创建形状后不消失，位置正确

2. **修复箭头缩放/旋转**
   - 修改 `SelectableArrowView.swift` 的 `updateFromNode()`
   - 修改 `handlePinch()` 和 `handleRotate()` 方法
   - 验证：双指捏合可缩放，双指旋转可旋转

### 5.2 第二阶段（P1 - 优化体验）

**目标**: 改善形状选择器 UI/UX

1. **重新设计弹出菜单**
   - 重写 `ShapePickerPopover.swift`
   - 添加更多形状类型
   - 弹出方向改为向上

2. **修改工具栏**
   - 更新 `CanvasToolbar.swift` 的 popover 配置
   - 添加 `presentationCompactAdaptation(.popover)`

### 5.3 第三阶段（P2 - 功能扩展）

**目标**: 统一工具架构

1. **整合箭头/直线到形状工具**
   - 修改 `CanvasTool.swift` 移除独立箭头
   - 在形状选择器中添加箭头/直线选项

2. **添加直线支持**
   - 新增 LineLayerNode（或扩展 ArrowLayerNode）
   - 实现直线的创建和编辑

---

## 六、测试用例

### 6.1 形状创建测试

| 测试项 | 操作 | 预期结果 |
|--------|------|----------|
| 形状创建 | 选择图形工具 -> 选择矩形 -> 在画布拖拽 | 矩形创建成功，位置正确，不消失 |
| 缩放状态下创建 | 放大画布到 200% -> 创建形状 | 形状创建在正确位置 |
| 滚动后创建 | 滚动画布到其他区域 -> 创建形状 | 形状创建在当前可见区域 |

### 6.2 箭头变换测试

| 测试项 | 操作 | 预期结果 |
|--------|------|----------|
| 箭头缩放 | 选择工具 -> 选中箭头 -> 双指捏合 | 箭头等比例缩放，路径正确重绘 |
| 箭头旋转 | 选择工具 -> 选中箭头 -> 双指旋转 | 箭头绕中心旋转 |
| 缩放+旋转 | 同时进行缩放和旋转 | 两种变换同时生效 |
| 撤销缩放 | 缩放后点击撤销 | 恢复原始大小 |
| 撤销旋转 | 旋转后点击撤销 | 恢复原始角度 |

### 6.3 弹出菜单测试

| 测试项 | 操作 | 预期结果 |
|--------|------|----------|
| 弹出方向 | 点击图形工具按钮 | 菜单在按钮上方弹出 |
| 形状种类 | 查看弹出菜单 | 包含箭头、直线、矩形、圆角矩形、圆形、三角形、菱形、五角星、六边形 |
| iPhone 显示 | 在 iPhone 上点击 | 仍显示为 popover，不是 sheet |
| 选择形状 | 点击某个形状 | 菜单关闭，工具切换成功 |

---

## 七、参考资源

### 设计参考
- [Figma Shape Tools](https://help.figma.com/hc/en-us/articles/360040450133-Shape-tools)
- [Figma Draw](https://www.figma.com/draw/)

### 技术参考
- [SwiftUI Popovers and Popup Menus](https://www.swiftyplace.com/blog/swiftui-popovers-and-popups)
- [aheze/Popovers](https://github.com/aheze/Popovers)
- [presentationCompactAdaptation](https://developer.apple.com/documentation/swiftui/view/presentationcompactadaptation(_:))

---

## 八、风险与注意事项

1. **坐标转换精度**
   - 浮点数计算可能产生微小误差
   - 建议在坐标转换时使用 `round()` 或 `floor()` 保证像素对齐

2. **手势冲突**
   - 缩放和旋转同时进行时，需确保两个手势可以同时识别
   - 已通过 `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` 处理

3. **撤销一致性**
   - 每种变换操作（移动、缩放、旋转）应该独立记录撤销
   - 避免多种操作混合在一个撤销步骤中

4. **向后兼容**
   - 如果移除独立的箭头工具，需要处理旧版本保存的工具状态
   - 建议在加载时自动迁移

5. **性能考虑**
   - 频繁的变换操作不应导致卡顿
   - 避免在手势回调中做复杂计算或频繁的视图重建
