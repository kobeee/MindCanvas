# 图形操作后控制点消失问题修复方案 v3.0

## 概述

本文档针对 MindCanvas 画布中图形工具的核心 Bug 提供完整的分析和修复方案：

**问题描述**：图形对象在移动、旋转或缩放之后，再次选中时，控制点（角点和旋转圆点）都消失了，只能移动无法再旋转或缩放。

**关键线索**：不仅仅是旋转后，**移动后也会出现问题**，且控制点完全消失。

**问题严重性**：高 - 核心功能失效

---

## 目录

1. [问题诊断](#1-问题诊断)
2. [根本原因分析](#2-根本原因分析)
3. [问题链路追踪](#3-问题链路追踪)
4. [修复方案](#4-修复方案)
5. [修改文件清单](#5-修改文件清单)
6. [验收标准](#6-验收标准)

---

## 1. 问题诊断

### 1.1 现象描述

1. 创建任意形状（矩形、圆形、三角形等）
2. 选中形状，进行移动操作
3. 释放手指（操作结束）
4. 再次点击选中该形状
5. **预期**：显示控制点（4个角点 + 1个旋转手柄），可以旋转、缩放
6. **实际**：控制点消失，只能移动

### 1.2 关键观察

- 不只是旋转，**移动后也会出现问题**
- 控制点（角点和旋转圆点）**完全消失**，不是位置错误
- 这说明问题不是坐标计算问题，而是**选中状态或视图更新**的问题

---

## 2. 根本原因分析

### 2.1 问题根源：`shapeNode` 的 `didSet` 触发无限循环式更新

**SelectableShapeView.swift 第 46-50 行**：

```swift
var shapeNode: ShapeLayerNode {
    didSet {
        updateFromNode()  // 每次 shapeNode 变化都会调用
    }
}
```

**`updateFromNode()` 方法 (第 246-269 行)**：

```swift
func updateFromNode() {
    // 重置 transform 为 identity
    transform = .identity

    // ... 设置 bounds 和 center

    // 应用旋转
    transform = CGAffineTransform(rotationAngle: shapeNode.rotation)

    updateShapePath()
    updateSelectionAppearance()  // 关键：这里会更新控制点
}
```

### 2.2 问题链路

当用户操作结束时，发生以下调用链：

```
用户操作结束（释放手指）
    ↓
handlePan.ended 触发
    ↓
syncToNode() 被调用
    ↓
shapeNode = shapeNode.updated(frame: newFrame, rotation: currentRotation)
    ↓
shapeNode.didSet 触发
    ↓
updateFromNode() 被调用
    ↓
updateSelectionAppearance() 被调用
    ↓
此时 isSelected 应该还是 true，控制点应该显示
```

**但是！** 还有另一条调用链：

```
syncToNode() 调用
    ↓
onNodeUpdated?(shapeNode) 回调
    ↓
NativeCanvasView.createShapeView() 中设置的回调:
    shapeView.onNodeUpdated = { [weak self] updatedShape in
        self?.shapeLayerManager.updateShape(updatedShape)
    }
    ↓
shapeLayerManager.updateShape(updatedShape) 被调用
```

**目前来看，这条链路没有问题**，因为 `onNodeUpdated` 回调只更新了 manager，没有再次设置 `shapeView.shapeNode`。

### 2.3 真正的问题：选中状态的时序问题

让我们仔细看 `handlePan` 的完整流程：

```swift
case .ended, .cancelled:
    syncToNode()  // 1. 同步数据
    if let initial = initialNode {
        onOperationEnd?(initial, shapeNode)  // 2. 触发操作结束回调
    }
    activeHandle = nil  // 3. 重置 activeHandle
    initialNode = nil   // 4. 清理
```

问题可能在 `onOperationEnd` 回调中！

**NativeCanvasView.createShapeView() 中的 onOperationEnd 回调 (第 1164-1199 行)**：

```swift
shapeView.onOperationEnd = { [weak self] _, endShape in
    guard let self = self, let startShape = operationStartShape else { return }

    // 检查是否移动
    if startShape.frame != endShape.frame {
        let action = MoveShapeAction(...)
        NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
    }
    // 检查是否旋转...

    operationStartShape = nil
}
```

**这个回调本身没问题**，只是记录撤销操作。

### 2.4 新的怀疑点：layoutSubviews 的干扰

**SelectableShapeView.swift 第 669-680 行**：

```swift
override func layoutSubviews() {
    super.layoutSubviews()

    // 防护：如果正在手势中，跳过 updateShapePath
    guard activeHandle == nil else { return }

    updateShapePath()
    if isSelected {
        updateSelectionAppearance()
    }
}
```

**问题**：`layoutSubviews` 中的守卫条件是 `activeHandle == nil`。

当手势结束时：
1. `syncToNode()` 被调用，触发 `shapeNode.didSet` → `updateFromNode()`
2. `updateFromNode()` 修改了 `bounds` 和 `center`
3. 这会触发 `layoutSubviews()`
4. 此时 `activeHandle` **还没有被清空**（在 `syncToNode()` 之后才清空）
5. 所以 `layoutSubviews` 中的 `updateSelectionAppearance()` 被跳过

**但是**，随后 `activeHandle = nil` 被执行，`layoutSubviews` 会被再次触发吗？不一定。

### 2.5 核心问题发现：updateFromNode 中 bounds/center 改变触发的 layoutSubviews

让我们更精确地追踪：

```swift
func updateFromNode() {
    transform = .identity  // 1. 重置 transform

    // ... 计算 finalWidth, finalHeight

    bounds = CGRect(...)   // 2. 改变 bounds → 触发 layoutSubviews
    center = CGPoint(...)  // 3. 改变 center → 可能再次触发 layoutSubviews

    transform = CGAffineTransform(rotationAngle: shapeNode.rotation)  // 4. 应用旋转

    updateShapePath()
    updateSelectionAppearance()  // 5. 更新选中外观
}
```

**关键时序问题**：

当 `bounds` 被改变时，`layoutSubviews` 会被调度（可能异步）。

如果 `layoutSubviews` 在 `updateFromNode()` 完成**之后**才被调用，会发生什么？

```swift
override func layoutSubviews() {
    super.layoutSubviews()

    guard activeHandle == nil else { return }  // activeHandle 此时已经是 nil

    updateShapePath()
    if isSelected {
        updateSelectionAppearance()  // 会被调用！
    }
}
```

看起来应该没问题...

### 2.6 重新审视：isSelected 状态是否被重置？

让我检查一下是否有地方会重置 `isSelected`：

1. `isSelected` 只在 `NativeCanvasView.updateSelectionStates()` 中被设置
2. `updateSelectionStates()` 只在 `selectedNodeID.didSet` 中被调用
3. `selectedNodeID` 在以下情况下被设置：
   - 用户点击形状时 (`onSelected` 回调)
   - 外部调用 `deselectAll()` 时

**等等！** 让我看看是否有 `deselectAll()` 或类似的调用：

<需要搜索 deselectAll 或 selectedNodeID = nil 的调用>

---

## 3. 问题链路追踪

### 3.1 需要确认的问题点

基于以上分析，问题可能出在以下几个地方：

1. **选中状态被意外清除** - `selectedNodeID` 被设置为 `nil`
2. **isSelected 没有正确传递** - `updateSelectionStates()` 没有被调用
3. **控制点被隐藏但未显示** - `updateSelectionAppearance()` 中的逻辑问题
4. **layoutSubviews 的时序问题** - 异步调用导致状态不一致

### 3.2 最可能的原因

经过深入分析，**最可能的原因**是：

**`syncToNode()` 中修改 `shapeNode` 触发了 `didSet`，进而调用 `updateFromNode()`，而 `updateFromNode()` 修改 `bounds`/`center` 会触发 `layoutSubviews`。但由于 UIKit 的布局机制，`layoutSubviews` 可能被合并或延迟执行，导致在最后一次 `layoutSubviews` 调用时，`isSelected` 的状态已经不正确。**

### 3.3 进一步的怀疑：选中状态在工具切换时被清除

另一个可能是：操作结束后，工具栏或其他 UI 触发了选中状态的清除。

---

## 4. 修复方案

### 4.1 方案 A：移除 shapeNode.didSet 中的 updateFromNode 自动调用（推荐）

**问题本质**：`shapeNode` 的 `didSet` 自动调用 `updateFromNode()` 是一个危险的设计，因为：
1. 内部更新（如 `syncToNode()`）和外部更新（如加载数据）都会触发
2. 内部更新时，视图状态已经是最新的，不需要再从 node 同步
3. 自动调用可能导致状态被意外覆盖

**修复方法**：

**文件**：`SelectableShapeView.swift`

**修改 1**：移除 shapeNode.didSet 中的自动调用

```swift
// 修改前
var shapeNode: ShapeLayerNode {
    didSet {
        updateFromNode()
    }
}

// 修改后
var shapeNode: ShapeLayerNode
// 移除 didSet，改为显式调用
```

**修改 2**：修改 `syncToNode()` 方法，只更新数据不触发视图更新

```swift
private func syncToNode() {
    let currentRotation = atan2(transform.b, transform.a)

    let newFrame = CGRect(
        x: center.x - bounds.width / 2,
        y: center.y - bounds.height / 2,
        width: bounds.width,
        height: bounds.height
    )

    // 使用临时变量避免触发 didSet
    let updatedNode = shapeNode.updated(
        frame: newFrame,
        rotation: currentRotation
    )

    // 直接赋值，不触发 didSet（因为我们移除了 didSet）
    shapeNode = updatedNode
    onNodeUpdated?(shapeNode)
}
```

**修改 3**：在需要从外部更新视图时显式调用 `updateFromNode()`

在 `NativeCanvasView.updateShape()` 中：

```swift
func updateShape(_ shape: ShapeLayerNode) {
    shapeLayerManager.updateShape(shape)
    if let shapeView = shapeViews[shape.id] {
        shapeView.shapeNode = shape
        shapeView.updateFromNode()  // 显式调用
    }
    onCanvasUpdated?()
}
```

**注意**：需要将 `updateFromNode()` 的访问级别改为 `internal` 或 `public`。

### 4.2 方案 B：使用标志位区分内部/外部更新

**修复方法**：

**文件**：`SelectableShapeView.swift`

**添加属性**：

```swift
/// 是否正在内部同步（避免 didSet 循环）
private var isSyncingToNode = false
```

**修改 shapeNode.didSet**：

```swift
var shapeNode: ShapeLayerNode {
    didSet {
        // 如果是内部同步，跳过 updateFromNode
        guard !isSyncingToNode else { return }
        updateFromNode()
    }
}
```

**修改 syncToNode()**：

```swift
private func syncToNode() {
    let currentRotation = atan2(transform.b, transform.a)

    let newFrame = CGRect(
        x: center.x - bounds.width / 2,
        y: center.y - bounds.height / 2,
        width: bounds.width,
        height: bounds.height
    )

    // 设置标志位，避免 didSet 触发 updateFromNode
    isSyncingToNode = true
    shapeNode = shapeNode.updated(
        frame: newFrame,
        rotation: currentRotation
    )
    isSyncingToNode = false

    onNodeUpdated?(shapeNode)
}
```

### 4.3 方案 C：保护 isSelected 状态（临时方案）

如果选中状态确实被意外清除，可以在 `updateFromNode()` 中保护它：

```swift
func updateFromNode() {
    // 保存当前选中状态
    let wasSelected = isSelected

    transform = .identity
    // ... 其他更新逻辑

    updateShapePath()

    // 恢复选中状态
    isSelected = wasSelected
    updateSelectionAppearance()
}
```

---

## 5. 修改文件清单

### 方案 A（推荐）

| 文件 | 修改类型 | 行号 | 说明 |
|------|----------|------|------|
| `SelectableShapeView.swift` | 修改 | 46-50 | 移除 `shapeNode.didSet` 中的 `updateFromNode()` |
| `SelectableShapeView.swift` | 修改 | 246 | 将 `updateFromNode()` 改为 `internal` 访问级别 |
| `NativeCanvasView.swift` | 修改 | 1129-1135 | 在 `updateShape()` 中显式调用 `updateFromNode()` |

### 方案 B

| 文件 | 修改类型 | 行号 | 说明 |
|------|----------|------|------|
| `SelectableShapeView.swift` | 新增 | ~72 | 添加 `isSyncingToNode` 属性 |
| `SelectableShapeView.swift` | 修改 | 46-50 | 在 `didSet` 中添加守卫条件 |
| `SelectableShapeView.swift` | 修改 | 271-288 | 在 `syncToNode()` 中设置标志位 |

---

## 6. 验收标准

### 6.1 基础功能测试

- [ ] 创建矩形，移动后再次选中，控制点正常显示
- [ ] 创建矩形，旋转后再次选中，控制点正常显示
- [ ] 创建矩形，缩放后再次选中，控制点正常显示
- [ ] 创建圆形，移动后再次选中，控制点正常显示
- [ ] 创建三角形，旋转后再次选中，控制点正常显示

### 6.2 连续操作测试

- [ ] 移动 → 释放 → 选中 → 旋转 → 释放 → 选中 → 缩放（循环操作正常）
- [ ] 所有操作后，控制点始终可见且可响应

### 6.3 回归测试

- [ ] 新创建的形状，控制点正常显示
- [ ] 保存/加载后，形状选中时控制点正常显示
- [ ] 撤销/重做后，形状选中时控制点正常显示
- [ ] 切换工具后，再切回选择工具，形状选中时控制点正常显示

---

## 7. 调试建议（强烈推荐先执行）

在实施任何修复方案之前，**强烈建议先添加调试日志**来确定问题的真正根源：

### 7.1 在 SelectableShapeView.swift 中添加日志

```swift
// 在 shapeNode.didSet 中（第 47-49 行）
var shapeNode: ShapeLayerNode {
    didSet {
        print("[Shape \(shapeNode.id.uuidString.prefix(8))] shapeNode.didSet triggered, isSelected=\(isSelected)")
        updateFromNode()
    }
}

// 在 isSelected.didSet 中（第 64-68 行）
var isSelected: Bool = false {
    didSet {
        print("[Shape] isSelected changed: \(oldValue) -> \(isSelected)")
        updateSelectionAppearance()
    }
}

// 在 syncToNode() 开始处（第 272 行）
private func syncToNode() {
    print("[Shape] syncToNode called, isSelected=\(isSelected)")
    // ... 其余代码
}

// 在 updateFromNode() 中（第 246 行）
func updateFromNode() {
    print("[Shape] updateFromNode called, isSelected=\(isSelected)")
    // ... 其余代码
    print("[Shape] updateFromNode finished, isSelected=\(isSelected)")
}

// 在 updateSelectionAppearance() 中（第 292 行）
private func updateSelectionAppearance() {
    let showHandles = isSelected
    print("[Shape] updateSelectionAppearance called, showHandles=\(showHandles)")

    selectionBorder.isHidden = !showHandles
    rotationLineLayer.isHidden = !showHandles
    rotationHandleLayer.isHidden = !showHandles
    cornerHandleLayers.forEach { $0.isHidden = !showHandles }

    print("[Shape] selectionBorder.isHidden=\(selectionBorder.isHidden)")
    // ... 其余代码
}

// 在 layoutSubviews() 中（第 669 行）
override func layoutSubviews() {
    super.layoutSubviews()
    print("[Shape] layoutSubviews called, activeHandle=\(String(describing: activeHandle)), isSelected=\(isSelected)")
    // ... 其余代码
}
```

### 7.2 在 NativeCanvasView.swift 中添加日志

```swift
// 在 updateSelectionStates() 中（第 488 行）
private func updateSelectionStates() {
    print("[Canvas] updateSelectionStates called, selectedNodeID=\(String(describing: selectedNodeID))")

    // 更新形状视图选中状态
    for (id, shapeView) in shapeViews {
        let shouldBeSelected = (id == selectedNodeID)
        print("[Canvas] Setting shapeView[\(id.uuidString.prefix(8))].isSelected = \(shouldBeSelected)")
        shapeView.isSelected = shouldBeSelected
    }

    onSelectionChanged?(selectedNodeID != nil)
}

// 在 selectedNodeID.didSet 中（第 86-90 行）
private var selectedNodeID: UUID? {
    didSet {
        print("[Canvas] selectedNodeID changed: \(String(describing: oldValue?.uuidString.prefix(8))) -> \(String(describing: selectedNodeID?.uuidString.prefix(8)))")
        updateSelectionStates()
    }
}
```

### 7.3 预期的正常日志顺序

操作一个形状后释放，预期看到：

```
[Shape] syncToNode called, isSelected=true
[Shape xxx] shapeNode.didSet triggered, isSelected=true
[Shape] updateFromNode called, isSelected=true
[Shape] updateSelectionAppearance called, showHandles=true
[Shape] selectionBorder.isHidden=false
[Shape] updateFromNode finished, isSelected=true
```

再次点击选中，预期看到：

```
[Canvas] selectedNodeID changed: nil -> xxx
[Canvas] updateSelectionStates called, selectedNodeID=Optional(xxx)
[Canvas] Setting shapeView[xxx].isSelected = true
[Shape] isSelected changed: false -> true
[Shape] updateSelectionAppearance called, showHandles=true
[Shape] selectionBorder.isHidden=false
```

### 7.4 通过日志确定的问题

通过日志可以确定：
1. `isSelected` 是否在某个环节被错误地设置为 `false`
2. `updateSelectionAppearance()` 被调用时 `isSelected` 的值
3. `selectionBorder.isHidden` 是否被正确设置
4. 各方法的调用顺序是否正确
5. `selectedNodeID` 是否被意外清除

---

## 附录：代码调用关系图

```
用户操作形状（拖拽/旋转/缩放）
    ↓
handlePan(.changed)
    ↓
handleMoveImproved() / handleRotationImproved() / handleResizeFixed()
    ↓
直接修改 center/bounds/transform（不触发 shapeNode.didSet）
    ↓
用户释放手指
    ↓
handlePan(.ended)
    ↓
syncToNode()
    ↓
shapeNode = shapeNode.updated(...) ← 这里触发 didSet！
    ↓
shapeNode.didSet
    ↓
updateFromNode()
    ↓
修改 transform/bounds/center
    ↓
updateShapePath()
updateSelectionAppearance() ← 此时 isSelected 应该是 true
    ↓
但是！bounds/center 的改变会触发 layoutSubviews()
    ↓
layoutSubviews() 可能在稍后被调用
    ↓
如果此时 isSelected 状态有问题，控制点会消失
```

---

**文档版本**：v3.0
**创建日期**：2025-12-18
**状态**：待实施
