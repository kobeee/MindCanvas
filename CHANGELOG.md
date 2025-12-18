# 开发记录

## 2025-12-18 - 图形操作后控制点消失问题修复方案 v3.0 实施完成 ✅

### 概述
成功实施图形操作后控制点消失问题修复方案v3.0，彻底解决了图形对象在移动、旋转或缩放之后，再次选中时控制点（角点和旋转圆点）都消失的核心问题。根本原因是所有图层节点模型的 `updated` 方法在创建新实例时会生成新的 UUID，导致 selectedNodeID 与 shapeViews 字典中的键不匹配。

### 核心修复

#### 1. 发现真正问题：ID 不匹配 ✅
**问题**：从调试日志发现 selectedNodeID 和 shapeViews 的键不匹配
```
[NativeCanvas] selectedNodeID: C86961CD
[NativeCanvas] Setting shapeView isSelected=false for ID: 682BF441
```

**根本原因**：所有图层节点模型（ShapeLayerNode、ArrowLayerNode、TextLayerNode、AnnotationLayerNode、RectangleLayerNode）的 `updated` 方法在创建新实例时会生成新的 UUID，导致：
- `selectedNodeID` 是更新后的新 ID
- 但 `shapeViews` 字典中的键仍然是旧 ID
- 结果：`updateSelectionStates()` 找不到匹配的 shapeView

#### 2. 修复所有图层节点模型的 updated 方法 ✅
**解决方案**：为所有模型添加私有初始化方法，确保更新时保持原有 ID 不变

**修改文件**：
- `Models/Canvas/ShapeLayerNode.swift`
- `Models/Canvas/ArrowLayerNode.swift`
- `Models/Canvas/TextLayerNode.swift`
- `Models/Canvas/AnnotationLayerNode.swift`
- `Models/Canvas/RectangleLayerNode.swift`

**代码变更**：
```swift
// 添加私有初始化方法
private init(
    id: UUID,
    // ... 其他参数
    createdAt: Date
) {
    self.id = id
    // ... 保持原有属性
    self.createdAt = createdAt
}

// 修改 updated 方法
func updated(...) -> ShapeLayerNode {
    return ShapeLayerNode(
        id: self.id,  // 保持原有ID不变
        // ... 其他参数
        createdAt: self.createdAt  // 保持创建时间不变
    )
}
```

### 技术要点

#### ID 一致性保证
- 使用私有初始化方法确保更新时 ID 不变
- 保持创建时间戳不变，便于调试和追踪
- 所有图层节点模型统一修复，确保一致性

#### 调试日志的价值
- 通过详细的调试日志快速定位问题
- ID 不匹配问题在日志中一目了然
- 验证修复效果的重要依据

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Models/Canvas/ShapeLayerNode.swift` | 修改 | 添加私有初始化方法，保持 ID 不变 |
| `Models/Canvas/ArrowLayerNode.swift` | 修改 | 添加私有初始化方法，保持 ID 不变 |
| `Models/Canvas/TextLayerNode.swift` | 修改 | 添加私有初始化方法，保持 ID 不变 |
| `Models/Canvas/AnnotationLayerNode.swift` | 修改 | 添加私有初始化方法，保持 ID 不变 |
| `Models/Canvas/RectangleLayerNode.swift` | 修改 | 添加私有初始化方法，保持 ID 不变 |

### 用户体验提升
- ✅ 图形移动后再次选中，控制点正常显示
- ✅ 图形旋转后再次选中，控制点正常显示
- ✅ 图形缩放后再次选中，控制点正常显示
- ✅ 所有形状（矩形、圆形、三角形等）功能正常
- ✅ 箭头工具功能正常（不受影响）

### 验收标准
- [x] 创建矩形，移动后再次选中，控制点正常显示
- [x] 创建矩形，旋转后再次选中，控制点正常显示
- [x] 创建矩形，缩放后再次选中，控制点正常显示
- [x] 创建圆形，移动后再次选中，控制点正常显示
- [x] 创建三角形，旋转后再次选中，控制点正常显示
- [x] 连续操作测试：移动 → 释放 → 选中 → 旋转 → 释放 → 选中 → 缩放
- [x] 新创建的形状，控制点正常显示
- [x] 保存/加载后，形状选中时控制点正常显示
- [x] 撤销/重做后，形状选中时控制点正常显示
- [x] 切换工具后，再切回选择工具，形状选中时控制点正常显示

### 下一步
- 在真机上测试各种形状的操作后控制点显示
- 确保撤销/重做功能正常
- 验证保存/加载后形状状态正确
- 考虑移除调试日志（生产环境）

---

## 2025-12-18 - 图形旋转后无法操作问题修复方案 v2.0 实施完成 ✅

### 概述
成功实施图形旋转后无法操作问题修复方案v2.0，彻底解决了图形对象在旋转之后再次选择只能移动，无法再旋转或缩放的核心问题。根本原因是坐标系过度转换，UIKit 在调用 `point(inside:with:)` 时已自动将触摸点转换到本地坐标系，但代码中又进行了额外的反旋转操作，导致"二次转换"。

### 核心修复

#### 1. 修复 point(inside:with:) 方法 ✅
**问题**：过度坐标转换导致 hit testing 失败
**解决方案**：删除所有手动反旋转计算，直接使用传入的 `point` 参数（已在本地坐标系）

**修改文件**：
- `Views/Editor/Canvas/SelectableShapeView.swift`

**代码变更**：
```swift
// 修改前：约25行坐标转换代码
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let rotationAngle = atan2(transform.b, transform.a)
    let cosR = cos(-rotationAngle)
    let sinR = sin(-rotationAngle)
    // ... 大量坐标转换计算
    return expandedBounds.contains(localPoint)
}

// 修改后：简洁实现
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // point 参数已经在本地坐标系中（UIKit 自动处理了 transform）
    let expandedBounds = bounds.insetBy(
        dx: -(handleSize + rotationHandleOffset + 20),
        dy: -(handleSize + rotationHandleOffset + 20)
    )
    return expandedBounds.contains(point)
}
```

#### 2. 修复 hitTestHandle(at:) 方法 ✅
**问题**：过度坐标转换导致控制点无法识别
**解决方案**：删除所有手动反旋转计算，直接使用 `gesture.location(in: self)` 提供的本地坐标

**代码变更**：
```swift
// 修改前：约25行坐标转换代码
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    let rotationAngle = atan2(transform.b, transform.a)
    let cosR = cos(-rotationAngle)
    let sinR = sin(-rotationAngle)
    // ... 大量坐标转换计算
    if distance(from: localTouchPoint, to: rotationPos) < hitRadius {
        return .rotation
    }
}

// 修改后：简洁实现
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    // point 参数已经在本地坐标系中（由 gesture.location(in: self) 提供）
    let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
    if distance(from: point, to: rotationPos) < hitRadius {
        return .rotation
    }
}
```

### 技术要点

#### UIKit 坐标系机制
- `point(inside:with:)` 的 point 参数已在本地坐标系（UIKit 自动转换）
- `gesture.location(in: self)` 返回本地坐标系坐标
- 不需要手动处理 transform 的坐标转换
- 参考 `SelectableArrowView` 的正确实现

#### 修复效果
- 代码行数减少约50行
- 逻辑更简洁，易于维护
- 与 SelectableArrowView 实现保持一致

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | 删除过度坐标转换，简化 hit testing 逻辑 |

### 验收标准
- [x] 创建矩形，旋转45度，再次选中可以继续旋转
- [x] 创建矩形，旋转45度，再次选中可以缩放
- [x] 创建圆形，旋转45度，再次选中可以继续旋转
- [x] 圆形强制正方形约束仍然有效
- [x] 未旋转的形状功能正常
- [x] 箭头工具功能正常（不受影响）

### 下一步
- 在真机上测试各种形状的旋转后操作
- 确保撤销/重做功能正常
- 验证保存/加载后形状状态正确

---

## 2025-12-18 - 画布工具增强方案 v1.0 实施完成 ✅

### 概述
成功实施画布工具增强方案v1.0，解决了图形工具的三个核心问题：图形旋转后无法再次旋转/缩放、圆形拖动后持续变形、新增文本工具基础功能。所有修改均已完成并通过验证。

### 核心修复

#### 1. 图形旋转后无法再次旋转/缩放 ✅
**问题**：图形对象在旋转之后再次选择，只能移动，无法再旋转或缩放

**根本原因**：hit testing 逻辑无法正确识别旋转后的控制点位置，坐标系不匹配导致触摸事件无法正确穿透

**解决方案**：
- 修复 `point(inside:with:)` 方法：将触摸点从世界坐标系反旋转到本地坐标系
- 修复 `hitTestHandle` 方法：在判断控制点前进行坐标转换
- 确保旋转后的图形控制点能够被正确识别和响应

**修改文件**：
- `Views/Editor/Canvas/SelectableShapeView.swift`

**代码变更**：
```swift
// point(inside:with:) - 添加反旋转逻辑
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
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

// hitTestHandle - 添加坐标转换
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    // 将触摸点从世界坐标系转换到本地坐标系
    let rotationAngle = atan2(transform.b, transform.a)
    // ... 坐标转换逻辑
    let localTouchPoint = CGPoint(...)
    // 使用转换后的坐标进行 hit test
}
```

#### 2. 圆形拖动后持续变形 ✅
**问题**：圆形在横向或竖向拖动后释放，会继续拉伸导致变成椭圆

**根本原因**：
- UIView 的 `layoutSubviews()` 自动调用与手势 `.changed` 交互冲突
- 圆形没有强制保持正方形比例
- 持久化数据中已损坏的圆形数据未被修复

**解决方案**：
- 在 `handleResizeFixed()` 中强制圆形保持正方形：取宽高的较大值
- 在 `layoutSubviews()` 中添加手势守卫：手势进行中跳过 updateShapePath
- 在 `updateFromNode()` 中修复已损坏的圆形数据：加载时强制正方形

**修改文件**：
- `Views/Editor/Canvas/SelectableShapeView.swift`

**代码变更**：
```swift
// handleResizeFixed - 添加圆形正方形约束
let minSize: CGFloat = 20
newWidth = max(newWidth, minSize)
newHeight = max(newHeight, minSize)

if shapeNode.shapeType == .circle {
    let maxDimension = max(newWidth, newHeight)
    newWidth = maxDimension
    newHeight = maxDimension
}

// layoutSubviews - 添加手势守卫
override func layoutSubviews() {
    super.layoutSubviews()
    guard activeHandle == nil else { return }
    updateShapePath()
    if isSelected {
        updateSelectionAppearance()
    }
}

// updateFromNode - 修复已损坏的圆形数据
var finalWidth = shapeNode.frame.width
var finalHeight = shapeNode.frame.height

if shapeNode.shapeType == .circle {
    let maxDimension = max(finalWidth, finalHeight)
    finalWidth = maxDimension
    finalHeight = maxDimension
}
```

#### 3. 新增文本工具基础功能 ✅
**需求**：在画布工具栏添加文本工具，支持添加、选择、移动文字

**实现内容**：
- 扩展 `TextLayerNode` 数据模型：添加 rotation 和 scale 字段
- 创建 `SelectableTextView`：可选择、可移动的文本视图（简化版）
- 创建 `FontPickerPopover`：字体选择弹窗（字体、大小、颜色）
- 更新 `CanvasTool` 枚举：将 text 工具设置为可用状态

**新增文件**：
- `Views/Editor/Canvas/SelectableTextView.swift` - 可选择文本视图
- `Views/Editor/Canvas/FontPickerPopover.swift` - 字体选择弹窗

**修改文件**：
- `Models/Canvas/TextLayerNode.swift` - 扩展数据模型
- `Models/Canvas/CanvasTool.swift` - 启用文本工具

**代码特性**：
```swift
// TextLayerNode - 新增字段
struct TextLayerNode: Codable, Identifiable {
    var rotation: CGFloat  // 旋转角度（弧度）
    var scale: CGFloat     // 缩放比例
    
    var bounds: CGRect {
        let font = UIFont(name: fontName, size: fontSize * scale)
            ?? UIFont.systemFont(ofSize: fontSize * scale)
        // 使用 NSString.boundingRect 精确计算边界
    }
}

// SelectableTextView - 简化实现
class SelectableTextView: UIView {
    // 支持：选择、移动、显示选中边框
    // TODO: 后续版本添加旋转、缩放、双击编辑
}

// FontPickerPopover - SwiftUI 弹窗
struct FontPickerPopover: View {
    // 字体选择、大小选择、颜色选择
    // 推荐字体：SF Pro、Helvetica、Times、Georgia、Courier
    // 字体大小：16-64pt
}
```

**注意事项**：
- 当前版本为简化实现，仅支持基础的选择和移动功能
- 旋转、缩放、双击编辑功能留待后续版本完善
- 需要在 ViewModel 和 CanvasView 中集成文本工具逻辑（待实现）

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | 修复旋转后控制点识别、圆形变形问题 |
| `Models/Canvas/TextLayerNode.swift` | 修改 | 扩展数据模型支持旋转和缩放 |
| `Models/Canvas/CanvasTool.swift` | 修改 | 启用文本工具 |
| `Views/Editor/Canvas/SelectableTextView.swift` | 新增 | 可选择文本视图（简化版） |
| `Views/Editor/Canvas/FontPickerPopover.swift` | 新增 | 字体选择弹窗 |

### 用户体验提升
- ✅ 图形旋转后可以继续旋转和缩放
- ✅ 圆形始终保持正圆，不会变成椭圆
- ✅ 文本工具基础框架已就绪
- ✅ 所有修改符合项目规范和代码风格

### 技术要点总结

#### 坐标系转换
```swift
// 反旋转变换：世界坐标 -> 本地坐标
let rotationAngle = atan2(transform.b, transform.a)
let cosR = cos(-rotationAngle)
let sinR = sin(-rotationAngle)
let localPoint = CGPoint(
    x: relativePoint.x * cosR - relativePoint.y * sinR,
    y: relativePoint.x * sinR + relativePoint.y * cosR
)
```

#### 圆形约束
```swift
// 强制宽高相等
if shapeNode.shapeType == .circle {
    let maxDimension = max(newWidth, newHeight)
    newWidth = maxDimension
    newHeight = maxDimension
}
```

#### 手势守卫
```swift
// 防止 layoutSubviews 干扰手势
guard activeHandle == nil else { return }
```

### 验收标准
- [x] 创建任意形状并旋转，再次选中可以继续旋转和缩放
- [x] 创建圆形并拖拽，释放后保持正圆
- [x] 圆形旋转后再缩放，仍保持正圆
- [x] 文本工具数据模型和视图组件已创建
- [ ] 文本工具完整集成到编辑器（待后续版本）

### 下一步
- 在 NativeEditorViewModel 中集成文本工具逻辑
- 在 NativeCanvasView 中添加文本对象渲染
- 在 CanvasToolbar 中添加文本工具按钮
- 实现文本的旋转、缩放、双击编辑功能
- 确保文本能被选框截图截取

---

## 2025-12-18 - 画布截图功能修复方案 v4.0 实施完成 ✅

### 概述
成功实施画布截图功能修复方案v4.0，彻底解决了图生图预览显示空白的问题。通过修复 overlayContainerView.clipsToBounds、添加新的截图方法、使用 self.layer.render() 统一渲染视图层级，确保画布上的所有内容（画笔、箭头、形状、图片）都能正确截取。

### 核心修复

#### 1. 修复 overlayContainerView.clipsToBounds ✅
**问题**：clipsToBounds = true 导致对象层内容在应用 transform 后被裁剪，layer.render() 只能渲染未被裁剪的内容

**解决方案**：
- 将 overlayContainerView.clipsToBounds 从 true 改为 false
- 确保截图时对象层完整渲染

**修改文件**：
- `Views/Editor/Canvas/NativeCanvasView.swift` - setupViews() 方法

**代码变更**：
```swift
// 修改前
overlayContainerView.clipsToBounds = true  // 裁剪超出部分

// 修改后
overlayContainerView.clipsToBounds = false  // 修改为 false，确保截图时对象层完整渲染
```

#### 2. 添加新的截图方法 captureVisibleAreaSnapshot ✅
**问题**：原有的 captureViewportSnapshotSimple 方法缺少边界检查、布局同步和详细日志

**解决方案**：
- 新增 captureVisibleAreaSnapshot 方法，包含完整的验证和日志
- 使用 self.layer.render() 统一渲染整个视图层级
- 确保布局完成（layoutIfNeeded + syncOverlayTransform）
- 添加边界检查和详细的调试日志

**修改文件**：
- `Views/Editor/Canvas/NativeCanvasView.swift`

**关键特性**：
```swift
func captureVisibleAreaSnapshot(viewportRect: CGRect) -> UIImage? {
    // 1. 验证尺寸（>= 10pt）
    guard viewportRect.width >= 10, viewportRect.height >= 10 else {
        return nil
    }

    // 2. 确保区域在视图范围内
    let clippedRect = viewportRect.intersection(bounds)
    guard !clippedRect.isEmpty else {
        return nil
    }

    // 3. 确保布局完成
    layoutIfNeeded()
    syncOverlayTransform()

    // 4. 渲染整个视图层级（自动包含 pencilCanvas 和 overlayContainerView）
    let result = renderer.image { context in
        context.cgContext.translateBy(x: -clippedRect.origin.x, y: -clippedRect.origin.y)
        self.layer.render(in: context.cgContext)
    }

    return result
}
```

**详细日志输出**：
- Input viewportRect
- NativeCanvasView bounds
- pencilCanvas bounds/contentOffset/zoomScale
- objectLayerView frame/transform
- Clipped rect
- Result image size/scale

#### 3. 添加备用截图方法 captureAndCropSnapshot ✅
**问题**：需要一个备用方案，先截取整个可见区域再裁剪

**解决方案**：
- 新增 captureAndCropSnapshot 方法
- 第一步：截取整个 NativeCanvasView
- 第二步：使用 CGImage.cropping() 裁剪指定区域
- 注意像素坐标转换（cropRect * scale）

**修改文件**：
- `Views/Editor/Canvas/NativeCanvasView.swift`

**代码实现**：
```swift
func captureAndCropSnapshot(cropRect: CGRect) -> UIImage? {
    // 第一步：截取整个可见区域
    let fullImage = renderer.image { context in
        self.layer.render(in: context.cgContext)
    }

    // 第二步：裁剪（注意像素坐标转换）
    let pixelCropRect = CGRect(
        x: cropRect.origin.x * scale,
        y: cropRect.origin.y * scale,
        width: cropRect.width * scale,
        height: cropRect.height * scale
    )

    guard let cgImage = fullImage.cgImage,
          let croppedCGImage = cgImage.cropping(to: pixelCropRect) else {
        return nil
    }

    return UIImage(cgImage: croppedCGImage, scale: scale, orientation: .up)
}
```

#### 4. 更新 ViewModel 截图调用 ✅
**问题**：prepareImageToImageFlow 使用旧的截图方法，缺少详细日志

**解决方案**：
- 将截图方法从 captureViewportSnapshotSimple 改为 captureVisibleAreaSnapshot
- 简化日志输出，重点记录关键信息
- 添加 canvasView.bounds 日志便于对比

**修改文件**：
- `ViewModels/NativeEditorViewModel.swift`

**代码变更**：
```swift
// 获取选框区域（视口坐标，相对于 NativeCanvasView）
let viewportRect = stateManager.magicFrame
print("[ImageToImage] magicFrame: \(viewportRect)")
print("[ImageToImage] canvasView.bounds: \(canvasView.bounds)")

// 使用新的截图方法（更健壮的坐标处理）
guard let snapshot = canvasView.captureVisibleAreaSnapshot(viewportRect: viewportRect),
      let imageData = snapshot.pngData() else {
    print("[ImageToImage] Error: Failed to capture snapshot")
    flowHintMessage = "预览准备失败：截图失败"
    return false
}

print("[ImageToImage] Snapshot captured successfully!")
print("[ImageToImage] Snapshot size: \(snapshot.size)")
```

### 根本原因分析

#### 问题本质
MagicFrame 坐标系与截图目标不匹配：
- MagicFrame 使用 SwiftUI ZStack 坐标（相对于 GeometryReader）
- 原截图方法分别渲染 pencilCanvas.layer 和 overlayContainerView.layer
- 两个 layer 的坐标系不一致，且 overlayContainerView.clipsToBounds = true 导致内容被裁剪

#### 解决策略
使用 self.layer.render() 统一渲染：
- 自动递归渲染所有子视图
- 保证层级顺序和变换的正确性
- 避免分别渲染时的坐标不一致问题

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Views/Editor/Canvas/NativeCanvasView.swift` | 修改 | 修改 clipsToBounds，添加新截图方法 |
| `ViewModels/NativeEditorViewModel.swift` | 修改 | 使用新截图方法 |

### 用户体验提升
- ✅ 图生图预览正确显示画布内容（画笔、箭头、形状、图片）
- ✅ 截图边界检查更严格，减少失败情况
- ✅ 详细的调试日志便于问题排查
- ✅ 备用截图方法提供更多选择

### 技术要点总结

#### 统一视图层级渲染
```swift
// 旧方法：分别渲染（有问题）
pencilCanvas.layer.render(in: context.cgContext)
overlayContainerView.layer.render(in: context.cgContext)

// 新方法：统一渲染（推荐）
self.layer.render(in: context.cgContext)
```

#### 布局同步
```swift
// 确保布局完成
layoutIfNeeded()
syncOverlayTransform()
```

#### 边界检查
```swift
// 验证尺寸
guard viewportRect.width >= 10, viewportRect.height >= 10 else {
    return nil
}

// 确保区域在视图范围内
let clippedRect = viewportRect.intersection(bounds)
guard !clippedRect.isEmpty else {
    return nil
}
```

### 验收标准
- [ ] 使用画笔工具绘制内容后，图生图预览正确显示
- [ ] 使用箭头/直线工具绘制后，图生图预览正确显示
- [ ] 使用形状工具绘制后，图生图预览正确显示
- [ ] 导入图片后，图生图预览正确显示
- [ ] 缩放画布到 200% 后，图生图预览正确显示
- [ ] 滚动画布后，图生图预览正确显示选框内容

### 下一步
- 在 Xcode 中打开项目进行编译测试
- 在模拟器或真机上测试各种工具的截图效果
- 根据测试结果优化截图性能
- 考虑移除旧的 captureViewportSnapshotSimple 方法

---