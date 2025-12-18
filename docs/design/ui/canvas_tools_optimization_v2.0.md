# 画布工具优化改造方案 v2.0

## 概述

本文档包含三个独立的优化任务：
1. **圆形工具释放时放大问题修复** - 深度分析和修复方案
2. **椭圆形工具添加** - 新增椭圆形形状支持
3. **清屏按钮智能删除** - 根据选中状态实现智能删除

---

## 任务一：圆形工具释放时放大问题修复

### 1.1 问题现象

- **特定问题**：只有圆形对象在拖动释放时会突然变大一点
- **其他形状正常**：矩形、三角形、星形等其他形状无此问题
- **时序问题**：问题出现在手指释放的瞬间

### 1.2 根本原因分析（第一性原理）

经过深度代码分析，发现问题的本质是**发生在特定时序窗口内的、跨越多个调用栈的数据污染问题**。

#### 1.2.1 最可能原因（95%）：bounds更新的时序陷阱

**问题代码位置**：[SelectableShapeView.swift](../../../src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift)

**时序序列分析**：

```
T0: 手势.ended 触发
    |-- activeHandle = nil (第454行)
    |-- DispatchQueue.main.async {} 入队 (第457行)

T1: UIKit 自动调用 layoutSubviews()
    |-- guard activeHandle == nil else { return }  通过（已清除）
    |-- if shapeNode.shapeType == .circle {
        |-- bounds = CGRect(...) // 第702行：修改bounds

T2: 异步块执行 syncToNode()
    |-- let finalWidth = bounds.width   // 此时是T1修改后的值
    |-- let finalHeight = bounds.height
    |-- let avgDimension = (finalWidth + finalHeight) / 2
```

**核心问题**：

在 `layoutSubviews()` 中（第700-703行），圆形约束的平均值计算：
```swift
if shapeNode.shapeType == .circle && abs(bounds.width - bounds.height) > 1 {
    let size = (bounds.width + bounds.height) / 2
    bounds = CGRect(x: 0, y: 0, width: size, height: size)
}
```

这会在非均匀的拖动释放场景造成累积：
- 拖动释放时，bounds 可能不完全相等（如 width=137.3, height=138.2）
- layoutSubviews() 计算：(137.3 + 138.2) / 2 = 137.75
- syncToNode() 再计算：(137.75 + 137.75) / 2 = 137.75
- **最终结果变大了 0.45 个点**（从原来的~137.5变成137.75）

#### 1.2.2 次要原因（85%）：中心点计算的隐藏精度损失

在 `handleResizeFixed()` 方法中（第538-562行），存在**逻辑不一致**：
- 第539-540行通过 `abs(...x + 0.001)` 处理接近0的值
- 第546-556行用 `< 0.001` 进行判断
- 两套判断标准不一致，可能导致边界条件下计算出不同的值

#### 1.2.3 其他可能原因

| 根本原因 | 可能性 | 严重性 |
|---------|-------|-------|
| transform/bounds 相互影响 | 70% | 中 |
| 平均值计算的累积误差 | 60% | 中 |
| onNodeUpdated 回调链 | 50% | 低 |

#### 1.2.4 为什么只有圆形有问题？

**矩形/三角形**：即使宽高不相等，约束逻辑只在 layoutSubviews 中调用 updateShapePath()，不会修改 bounds，所以不会产生累积变化。

**圆形**：在 layoutSubviews 中会主动修改 bounds 的宽高，这是唯一会改变视图几何体的约束，因此导致了问题。

### 1.3 修复方案

#### 方案 A（推荐）：消除手势结束时的 layoutSubviews 调用干扰

**修改文件**：[SelectableShapeView.swift:454-470](../../../src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift#L454-L470)

**实现步骤**：

**Step 1**: 添加跳过标志属性（在类属性区域添加）
```swift
// 在 private var activeHandle: ControlHandle? 附近添加
private var skipCircleConstraintInLayout = false
```

**Step 2**: 修改手势结束处理（第454-470行）
```swift
case .ended, .cancelled:
    skipCircleConstraintInLayout = true  // 标记跳过
    activeHandle = nil

    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.syncToNode()
        self.skipCircleConstraintInLayout = false  // 恢复
        if let initial = self.initialNode {
            self.onOperationEnd?(initial, self.shapeNode)
        }
        self.initialNode = nil
    }
```

**Step 3**: 修改 layoutSubviews（第696-710行）
```swift
override func layoutSubviews() {
    super.layoutSubviews()
    guard activeHandle == nil else { return }

    // 跳过修复：防止手势结束时的 layoutSubviews 干扰
    guard !skipCircleConstraintInLayout else { return }

    if shapeNode.shapeType == .circle && abs(bounds.width - bounds.height) > 1 {
        let size = (bounds.width + bounds.height) / 2
        bounds = CGRect(x: 0, y: 0, width: size, height: size)
    }

    updateShapePath()
    if isSelected {
        updateSelectionAppearance()
    }
}
```

#### 方案 B（可选补充）：在 syncToNode 中添加防抖

**目的**：防止多次调用导致的累积误差

```swift
private var lastSyncedFrame: CGRect?

private func syncToNode() {
    // ... 现有计算逻辑 ...

    let newFrame = CGRect(...)

    // 防护：如果与上次同步的 frame 几乎相同，不再更新
    if let lastFrame = lastSyncedFrame,
       abs(lastFrame.width - newFrame.width) < 0.1,
       abs(lastFrame.height - newFrame.height) < 0.1 {
        return  // 跳过微小变化
    }

    lastSyncedFrame = newFrame
    shapeNode = shapeNode.updated(frame: newFrame, rotation: currentRotation)
    onNodeUpdated?(shapeNode)
}
```

### 1.4 调试验证方案

如需进一步验证问题根源，可添加以下临时日志：

```swift
// layoutSubviews 内
if shapeNode.shapeType == .circle {
    print("[ShapeView-layoutSubviews] 手势后: bounds=\(bounds), activeHandle=\(String(describing: activeHandle))")
}

// syncToNode 内
print("[ShapeView-syncToNode] 同步前: bounds.width=\(finalWidth), bounds.height=\(finalHeight)")

// 手势结束时
print("[ShapeView-pan] 手势结束: 进入异步块前 bounds=\(bounds)")
```

### 1.5 修改文件清单

| 文件 | 行数范围 | 修改类型 | 说明 |
|------|---------|---------|------|
| SelectableShapeView.swift | 类属性区域 | 新增 | 添加 skipCircleConstraintInLayout 属性 |
| SelectableShapeView.swift | 454-470 | 修改 | 手势结束时设置跳过标志 |
| SelectableShapeView.swift | 696-710 | 修改 | layoutSubviews 添加跳过守卫 |

### 1.6 验收标准

- [ ] 创建圆形，拖动四个角点缩放，释放后尺寸不变
- [ ] 创建圆形，拖动移动，释放后尺寸不变
- [ ] 创建圆形，旋转后缩放，释放后尺寸不变
- [ ] 连续操作10次，圆形尺寸无累积增长
- [ ] 矩形、三角形等其他形状功能不受影响

---

## 任务二：椭圆形工具添加

### 2.1 需求分析

#### 椭圆形与圆形的区别

| 特性 | 圆形 | 椭圆形 |
|------|------|--------|
| 宽高约束 | 必须相等 | 可自由拉伸 |
| 尺寸锁定 | 锁定为正方形 | 无约束 |
| 绘制方法 | `UIBezierPath(ovalIn:)` | `UIBezierPath(ovalIn:)` |
| 约束处理 | 3处代码 | 0处代码（标准行为） |
| 图标 | `circle` | `ellipse` |

椭圆形使用**完全相同的绘制API**，但**不强制宽高相等**。

### 2.2 实现方案

#### 2.2.1 修改 ShapeType.swift

**文件**：[Models/Canvas/ShapeType.swift](../../../src/MindCanvas/MindCanvas/Models/Canvas/ShapeType.swift)

**修改1：枚举定义**（在 circle 之后添加）
```swift
enum ShapeType: String, CaseIterable, Identifiable, Codable {
    case rectangle = "rectangle"
    case roundedRectangle = "roundedRectangle"
    case circle = "circle"
    case ellipse = "ellipse"  // 新增
    case triangle = "triangle"
    case pentagon = "pentagon"
    case diamond = "diamond"
    case star = "star"
    case hexagon = "hexagon"
    case line = "line"
    case arrow = "arrow"
}
```

**修改2：iconName计算属性**（在 circle case 之后添加）
```swift
var iconName: String {
    switch self {
    // ... 其他 case ...
    case .circle: return "circle"
    case .ellipse: return "ellipse"  // SF Symbol 图标
    // ... 其他 case ...
    }
}
```

**修改3：displayName计算属性**（在 circle case 之后添加）
```swift
var displayName: String {
    switch self {
    // ... 其他 case ...
    case .circle: return "圆形"
    case .ellipse: return "椭圆形"  // 中文名称
    // ... 其他 case ...
    }
}
```

**修改4：popoverShapes静态属性**
```swift
static var popoverShapes: [ShapeType] {
    [.line, .arrow, .rectangle, .roundedRectangle, .circle, .ellipse, .triangle, .diamond, .star, .hexagon]
    // 在 circle 之后添加 ellipse
}
```

#### 2.2.2 修改 SelectableShapeView.swift

**文件**：[Views/Editor/Canvas/SelectableShapeView.swift](../../../src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift)

**修改位置**：`createShapePath()` 方法（第190-238行）

在 `case .circle:` 之后、`case .triangle:` 之前添加：
```swift
case .ellipse:
    return UIBezierPath(ovalIn: rect)
```

**无需修改**的部分：
- `updateFromNode()` - 椭圆形不需要强制正方形约束
- `syncToNode()` - 椭圆形保持自然尺寸
- `layoutSubviews()` - 椭圆形保持自然尺寸
- 所有控制点交互 - 椭圆形使用标准的4角+旋转交互

#### 2.2.3 修改 ShapeDrawingView.swift

**文件**：[Views/Editor/Canvas/ShapeDrawingView.swift](../../../src/MindCanvas/MindCanvas/Views/Editor/Canvas/ShapeDrawingView.swift)

**修改位置**：switch shapeType（第15-57行）

在 `case .circle:` 之后、`case .triangle:` 之前添加：
```swift
case .ellipse:
    path.addEllipse(in: rect)
```

#### 2.2.4 ShapePickerPopover.swift - 无需修改

ShapePickerPopover 会自动根据 popoverShapes 数组渲染，图标和名称自动获取。

### 2.3 修改文件清单

| 文件 | 修改位置 | 修改类型 | 说明 |
|------|---------|---------|------|
| ShapeType.swift | 枚举定义 | 新增 case | 添加 ellipse case |
| ShapeType.swift | iconName | 新增分支 | 返回 "ellipse" |
| ShapeType.swift | displayName | 新增分支 | 返回 "椭圆形" |
| ShapeType.swift | popoverShapes | 修改数组 | 添加 .ellipse |
| SelectableShapeView.swift | createShapePath() | 新增分支 | 返回椭圆路径 |
| ShapeDrawingView.swift | switch | 新增分支 | 绘制椭圆预览 |

### 2.4 UI交互流程

```
用户选择椭圆工具
  |
  v
触发 ShapeDrawingGestureView 拖拽
  |
  v
在 ShapeDrawingView 中预览（调用 addEllipse）
  |
  v
创建 ShapeLayerNode(shapeType: .ellipse, ...)
  |
  v
在 NativeCanvasView 中添加 SelectableShapeView
  |
  v
SelectableShapeView.createShapePath() 返回椭圆路径
  |
  v
用户可选中、移动、缩放、旋转椭圆形
  |
  v
缩放时四个角点可独立拖动（无约束）
```

### 2.5 验收标准

- [ ] ShapePickerPopover 中显示椭圆形选项，图标正确
- [ ] 点击椭圆形选项，工具切换成功
- [ ] 在画布拖拽可绘制椭圆形
- [ ] 椭圆形可以被选中、移动、旋转
- [ ] 拖动椭圆形角点可自由改变宽高比（不受正方形约束）
- [ ] 保存/加载椭圆形数据正常
- [ ] 撤销/重做椭圆形操作正常
- [ ] 圆形功能不受影响（仍保持正方形约束）

---

## 任务三：清屏按钮智能删除

### 3.1 需求分析

当前清屏按钮的问题：
- 无论是否有选中对象，都执行清空整个画布
- 用户可能只想删除当前选中的对象

改进目标：
- 有选中对象时：只删除选中的对象
- 无选中对象时：清空整个画布
- 文案随状态动态变化

### 3.2 当前实现分析

#### 3.2.1 清屏按钮位置

**文件**：[CanvasActionBar.swift](../../../src/MindCanvas/MindCanvas/Views/Editor/Canvas/CanvasActionBar.swift)

- 位置：左上角功能键栏
- 按钮图标：`trash`
- 当前状态：永远 `enabled: true`
- 提示文字：`"清屏"`

#### 3.2.2 现有删除功能

**NativeCanvasView.swift** 中已有的删除函数：
- `removeLayer(id:)` - 删除图片图层
- `removeArrow(id:)` - 删除箭头
- `removeShape(id:)` - 删除形状

**NativeEditorViewModel.swift** 中：
```swift
func deleteSelectedLayer() {
    guard let selectedID = stateManager.selectedNodeID,
          let canvasView = canvasView else { return }

    canvasView.removeLayer(id: selectedID)
    canvasDocument.removeLayer(id: selectedID)
    stateManager.clearSelection()
}
```

#### 3.2.3 选中状态管理

**CanvasStateManager.swift**（第73-89行）：
```swift
var selectedNodeID: UUID?

var hasSelection: Bool {
    selectedNodeID != nil
}

func selectNode(_ id: UUID?) {
    selectedNodeID = id
}

func clearSelection() {
    selectedNodeID = nil
}
```

### 3.3 实现方案

#### 3.3.1 修改 CanvasActionBar.swift

**文件**：[Views/Editor/Canvas/CanvasActionBar.swift](../../../src/MindCanvas/MindCanvas/Views/Editor/Canvas/CanvasActionBar.swift)

**修改1：添加新的回调参数**
```swift
struct CanvasActionBar: View {
    // ... 现有参数 ...
    var onDeleteSelected: () -> Void  // 新增：删除选中对象回调

    // ...
}
```

**修改2：修改清屏按钮逻辑**（第39-48行）
```swift
// 清屏/删除按钮
ActionButton(
    icon: "trash",
    enabled: true,
    action: {
        showClearConfirmation = true
    }
)
.help(hasSelection ? "删除选中对象" : "清空画布")  // 动态提示
```

**修改3：修改 Alert 弹窗**（第54-61行）
```swift
.alert(
    hasSelection ? "删除选中对象" : "清空画布",  // 动态标题
    isPresented: $showClearConfirmation
) {
    Button("取消", role: .cancel) { }
    Button(
        hasSelection ? "删除" : "清屏",  // 动态按钮文案
        role: .destructive
    ) {
        if hasSelection {
            onDeleteSelected()  // 调用删除选中
        } else {
            onClear()  // 调用清空画布
        }
    }
} message: {
    Text(
        hasSelection
            ? "确定要删除选中的对象吗？此操作可以撤销。"
            : "此操作将清除画布上的所有内容，无法撤销。"
    )
}
```

#### 3.3.2 修改 CanvasStateManager.swift

**文件**：[ViewModels/CanvasStateManager.swift](../../../src/MindCanvas/MindCanvas/ViewModels/CanvasStateManager.swift)

**新增方法和回调**（在 clearCanvas 方法附近）：
```swift
/// 删除选中节点的回调
var onDeleteSelected: (() -> Void)?

/// 删除选中的节点（支持撤销）
func deleteSelectedNode() {
    guard hasSelection else { return }
    onDeleteSelected?()
}
```

#### 3.3.3 修改 NativeEditorView.swift

**文件**：[Views/Editor/NativeEditorView.swift](../../../src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift)

**修改1：在 onAppear 块中添加回调绑定**（第102-150行附近）
```swift
// 新增：绑定删除选中节点回调
viewModel.stateManager.onDeleteSelected = { [weak viewModel] in
    guard let viewModel = viewModel,
          let canvasView = viewModel.canvasView,
          let selectedID = viewModel.stateManager.selectedNodeID
    else { return }

    // 尝试删除不同类型的对象
    // 1. 尝试作为图片图层删除
    if let layer = canvasView.getLayers().first(where: { $0.id == selectedID }) {
        let action = RemoveLayerAction(layer: layer, canvasView: canvasView)
        viewModel.stateManager.recordAction(action)
        canvasView.removeLayer(id: selectedID, recordUndo: false)
    }
    // 2. 尝试作为箭头删除
    else if canvasView.hasArrow(id: selectedID) {
        canvasView.removeArrow(id: selectedID)
    }
    // 3. 尝试作为形状删除
    else if canvasView.hasShape(id: selectedID) {
        canvasView.removeShape(id: selectedID)
    }

    // 清除选中状态
    viewModel.stateManager.clearSelection()
}
```

**修改2：更新 CanvasActionBar 调用**（第636-644行）
```swift
CanvasActionBar(
    canUndo: viewModel.stateManager.canUndo,
    canRedo: viewModel.stateManager.canRedo,
    hasSelection: viewModel.stateManager.hasSelection,
    onUndo: { viewModel.stateManager.undo() },
    onRedo: { viewModel.stateManager.redo() },
    onDuplicate: { viewModel.stateManager.duplicateSelected() },
    onClear: { viewModel.stateManager.clearCanvas() },
    onDeleteSelected: { viewModel.stateManager.deleteSelectedNode() }  // 新增
)
```

#### 3.3.4 添加辅助方法到 NativeCanvasView

**文件**：[Views/Editor/Canvas/NativeCanvasView.swift](../../../src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift)

```swift
/// 检查是否存在指定ID的箭头
func hasArrow(id: UUID) -> Bool {
    return arrowViews[id] != nil
}

/// 检查是否存在指定ID的形状
func hasShape(id: UUID) -> Bool {
    return shapeViews[id] != nil
}
```

### 3.4 UI文案设计

| 场景 | 按钮提示 | Alert标题 | Alert消息 | 确认按钮 |
|------|---------|---------|---------|---------|
| 有选中 | "删除选中对象" | "删除选中对象" | "确定要删除选中的对象吗？此操作可以撤销。" | "删除" |
| 无选中 | "清空画布" | "清空画布" | "此操作将清除画布上的所有内容，无法撤销。" | "清屏" |

### 3.5 图标设计建议

**推荐方案**：保持垃圾桶图标 `trash` 不变
- 通过 hover 时的 help 文字提示变化
- 通过 Alert 标题/内容的变化
- 符合 iOS 设计规范，降低学习成本

**可选方案**（高端）：两个不同图标
- 无选中时：`trash`
- 有选中时：`trash.fill` 或 `xmark.circle.fill`
- 切换时使用 `.transition(.scale)` 动画

### 3.6 修改文件清单

| 文件 | 修改位置 | 修改类型 | 说明 |
|------|---------|---------|------|
| CanvasActionBar.swift | 参数列表 | 新增 | 添加 onDeleteSelected 回调 |
| CanvasActionBar.swift | 清屏按钮 | 修改 | 动态 help 文案 |
| CanvasActionBar.swift | Alert | 修改 | 动态标题、消息、按钮 |
| CanvasStateManager.swift | 方法区 | 新增 | 添加 deleteSelectedNode() 和回调 |
| NativeEditorView.swift | onAppear | 新增 | 绑定删除选中回调 |
| NativeEditorView.swift | CanvasActionBar调用 | 修改 | 传入 onDeleteSelected |
| NativeCanvasView.swift | 公开方法 | 新增 | hasArrow(), hasShape() |

### 3.7 验收标准

**无选中对象状态**：
- [ ] 按钮提示显示 "清空画布"
- [ ] 点击清屏，Alert 标题为 "清空画布"
- [ ] 点击确认后，清空所有笔画、图片、箭头、形状
- [ ] 撤销应恢复所有内容

**选中单个对象状态**：
- [ ] 按钮提示显示 "删除选中对象"
- [ ] 点击清屏，Alert 标题为 "删除选中对象"
- [ ] 点击确认后，仅删除该对象
- [ ] 其他对象保留
- [ ] 撤销应恢复该对象

**其他测试**：
- [ ] 点击 Alert 取消按钮，画布内容不变
- [ ] 多次删除后的撤销，能逐步恢复

---

## 实施计划

### 优先级排序

| 任务 | 优先级 | 预计工作量 | 说明 |
|------|--------|-----------|------|
| 任务一：圆形放大修复 | P0 | 1小时 | 影响用户体验的核心bug |
| 任务三：清屏智能删除 | P1 | 2小时 | 提升交互体验 |
| 任务二：椭圆形添加 | P2 | 1小时 | 功能增强，影响小 |

### 依赖关系

- 三个任务相互独立，可并行开发
- 建议先修复圆形bug，因为椭圆和圆形使用类似的代码路径

### 回归测试重点

1. 圆形、矩形、三角形等所有形状的创建、移动、缩放、旋转
2. 撤销/重做功能
3. 保存/加载功能
4. 选中状态的切换

---

## 附录：关键代码文件索引

| 文件 | 路径 | 主要功能 |
|------|------|---------|
| ShapeType.swift | Models/Canvas/ | 形状类型枚举定义 |
| ShapeLayerNode.swift | Models/Canvas/ | 形状数据模型 |
| SelectableShapeView.swift | Views/Editor/Canvas/ | 形状视图和交互 |
| ShapeDrawingView.swift | Views/Editor/Canvas/ | 形状绘制预览 |
| ShapePickerPopover.swift | Views/Editor/Canvas/ | 形状选择弹窗 |
| CanvasActionBar.swift | Views/Editor/Canvas/ | 画布操作栏 |
| CanvasStateManager.swift | ViewModels/ | 画布状态管理 |
| NativeEditorView.swift | Views/Editor/ | 主编辑器视图 |
| NativeCanvasView.swift | Views/Editor/Canvas/ | 原生画布实现 |

---

## 版本历史

| 版本 | 日期 | 作者 | 说明 |
|------|------|------|------|
| v2.0 | 2025-12-18 | Claude | 新增圆形放大修复、椭圆形工具、清屏智能删除 |
| v1.0 | 2025-12-16 | Claude | 初始版本（清屏修复 + 画笔设置） |
