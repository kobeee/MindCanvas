# 图形旋转后无法操作问题修复方案 v2.0

## 概述

本文档针对 MindCanvas 画布中图形工具的核心 Bug 提供完整的分析和修复方案：

**问题描述**：图形对象在旋转之后再次选择，只能移动，不能再旋转或缩放。

**问题严重性**：高 - 严重影响用户体验，核心功能失效

**根本原因**：**坐标系过度转换**。UIKit 在调用 `point(inside:with:)` 时已自动将触摸点转换到本地坐标系，但代码中又进行了额外的反旋转操作，导致"二次转换"，坐标完全错乱。

---

## 目录

1. [问题诊断](#1-问题诊断)
2. [根本原因分析](#2-根本原因分析)
3. [UIKit 坐标系机制](#3-uikit-坐标系机制)
4. [正确实现参考](#4-正确实现参考)
5. [修复方案](#5-修复方案)
6. [修改文件清单](#6-修改文件清单)
7. [验收标准](#7-验收标准)

---

## 1. 问题诊断

### 1.1 现象描述

1. 创建任意形状（矩形、圆形、三角形等）
2. 旋转形状（如旋转 45 度）
3. 释放手指，再次点击选中该形状
4. **预期**：可以继续旋转、缩放、移动
5. **实际**：只能移动，无法旋转或缩放

### 1.2 问题追踪

通过代码分析，问题链路如下：

```
用户触摸形状
    ↓
UIKit 调用 point(inside:with:) ← 问题1：过度坐标转换
    ↓
命中后，panGesture.began 触发
    ↓
调用 hitTestHandle(at: locationInSelf) ← 问题2：过度坐标转换
    ↓
hitTestHandle 返回 nil（应该返回控制点类型）
    ↓
activeHandle = nil
    ↓
panGesture.changed 时只执行 handleMoveImproved()
    ↓
形状只能移动，无法旋转/缩放
```

### 1.3 问题定位

问题集中在两个方法：

| 方法 | 位置 | 问题 |
|------|------|------|
| `point(inside:with:)` | 第 389-420 行 | 过度的手动反旋转计算 |
| `hitTestHandle(at:)` | 第 338-383 行 | 过度的手动反旋转计算 |

---

## 2. 根本原因分析

### 2.1 错误的假设

当前代码基于一个**错误的假设**：

> "point(inside:with:) 接收的 point 参数是父视图坐标系（世界坐标系），需要手动反旋转到本地坐标系"

这个假设是**错误的**！

### 2.2 UIKit 的实际行为

UIKit 在调用 `point(inside:with:)` 之前，会自动将触摸点从父视图坐标系转换到目标视图的本地坐标系。这个转换**已经考虑了 transform**。

同样，`gesture.location(in: self)` 返回的坐标也是本地坐标系。

### 2.3 当前代码的错误

**SelectableShapeView.swift 第 389-420 行**：

```swift
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // 错误：point 已经是本地坐标系，不需要反旋转！
    let rotationAngle = atan2(transform.b, transform.a)
    let cosR = cos(-rotationAngle)  // 反向旋转
    let sinR = sin(-rotationAngle)

    let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
    let relativePoint = CGPoint(
        x: point.x - centerPoint.x,  // 错误：point 已经是本地坐标！
        y: point.y - centerPoint.y
    )

    // 反旋转该点 - 这是多余的操作！
    let rotatedPoint = CGPoint(
        x: relativePoint.x * cosR - relativePoint.y * sinR,
        y: relativePoint.x * sinR + relativePoint.y * cosR
    )

    let localPoint = CGPoint(
        x: rotatedPoint.x + centerPoint.x,
        y: rotatedPoint.y + centerPoint.y
    )

    let expandedBounds = bounds.insetBy(...)
    return expandedBounds.contains(localPoint)  // 使用了错误的 localPoint
}
```

**问题**：
- `point` 参数已经在本地坐标系中
- 代码又进行了一次反旋转
- 相当于把本地坐标"反旋转"到了一个错误的坐标系
- 旋转角度越大，偏差越大
- 最终导致 hit test 失败

### 2.4 hitTestHandle 的同样问题

**SelectableShapeView.swift 第 338-383 行**：

```swift
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    guard isSelected else { return nil }

    let hitRadius: CGFloat = handleSize + 10

    // 错误：point 已经是本地坐标系！
    let rotationAngle = atan2(transform.b, transform.a)
    let cosR = cos(-rotationAngle)
    let sinR = sin(-rotationAngle)

    // 这些计算全是多余的...
    let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
    let relativePoint = CGPoint(
        x: point.x - centerPoint.x,
        y: point.y - centerPoint.y
    )

    let rotatedPoint = CGPoint(
        x: relativePoint.x * cosR - relativePoint.y * sinR,
        y: relativePoint.x * sinR + relativePoint.y * cosR
    )

    let localTouchPoint = CGPoint(
        x: rotatedPoint.x + centerPoint.x,
        y: rotatedPoint.y + centerPoint.y
    )

    // 使用了错误的 localTouchPoint 进行距离检测
    let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
    if distance(from: localTouchPoint, to: rotationPos) < hitRadius {
        return .rotation
    }
    // ...
}
```

**结果**：
- `hitTestHandle` 总是返回 `nil`
- `activeHandle` 始终为 `nil`
- `handlePan.changed` 只执行移动逻辑

---

## 3. UIKit 坐标系机制

### 3.1 官方文档说明

根据 Apple 官方文档：

> **UIView.transform**：指定相对于视图 bounds 中心应用的变换。
>
> **重要**：如果此属性不是恒等变换（identity transform），则 frame 属性的值是**未定义的**，因此应该被忽略。

### 3.2 坐标系转换规则

| 场景 | 坐标系 | 说明 |
|------|--------|------|
| `point(inside:with:)` 的 point 参数 | **本地坐标系** | UIKit 自动转换，无需手动处理 |
| `gesture.location(in: self)` | **本地坐标系** | 相对于 self 的 bounds |
| `gesture.location(in: superview)` | **父视图坐标系** | 相对于 superview 的 bounds |
| `bounds` | **本地坐标系** | 永远不受 transform 影响 |
| `frame` | **父视图坐标系** | 有 transform 时是**未定义的** |
| `center` | **父视图坐标系** | 始终有效，即使有 transform |

### 3.3 转换流程图

```
触摸事件发生（屏幕坐标）
        ↓
UIKit 遍历视图层级
        ↓
对于每个视图，调用 hitTest(_:with:)
        ↓
hitTest 内部调用 point(inside:with:)
        ↓
传入的 point 已经是目标视图的本地坐标系！
（UIKit 自动应用了 transform 的逆矩阵）
        ↓
你的代码只需要检查 bounds.contains(point)
```

### 3.4 关键结论

**你不需要手动处理 transform 的坐标转换！**

UIKit 已经帮你做了。你的代码只需要：

1. 在 `point(inside:with:)` 中直接使用 `point` 参数
2. 在手势回调中，`gesture.location(in: self)` 已经是本地坐标

---

## 4. 正确实现参考

### 4.1 SelectableArrowView 的实现（正确）

同一个项目中的 `SelectableArrowView` 实现是正确的：

**SelectableArrowView.swift 第 251-254 行**：

```swift
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // 正确：直接使用 point，它已经在本地坐标系
    let expandedBounds = bounds.insetBy(dx: -(handleSize + 20), dy: -(handleSize + 20))
    return expandedBounds.contains(point)
}
```

**SelectableArrowView.swift 第 231-244 行**：

```swift
private func hitTestHandle(at point: CGPoint) -> ArrowHandle? {
    guard isSelected else { return nil }

    let hitRadius: CGFloat = handleSize + 10

    // 正确：直接使用 point 进行距离检测
    let endpoints: [ArrowHandle] = [.startPoint, .endPoint]
    for endpoint in endpoints {
        let endpointPos = endpoint.position(for: arrowNode, in: bounds)
        if distance(from: point, to: endpointPos) < hitRadius {
            return endpoint
        }
    }

    return nil
}
```

### 4.2 为什么箭头可以正常工作

`SelectableArrowView` 没有使用旋转控制点，但其 `point(inside:with:)` 和 `hitTestHandle` 的实现是正确的：

- 直接使用传入的 `point` 参数
- 不做任何额外的坐标转换
- 控制点位置基于 `bounds`（本地坐标系）
- 距离检测直接比较本地坐标

---

## 5. 修复方案

### 5.1 修复 `point(inside:with:)` 方法

**文件**：`Views/Editor/Canvas/SelectableShapeView.swift`

**位置**：第 389-420 行

**修改前**：

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

**修改后**：

```swift
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // point 参数已经在本地坐标系中（UIKit 自动处理了 transform）
    // 直接使用扩展后的 bounds 进行范围检查
    let expandedBounds = bounds.insetBy(
        dx: -(handleSize + rotationHandleOffset + 20),
        dy: -(handleSize + rotationHandleOffset + 20)
    )
    return expandedBounds.contains(point)
}
```

### 5.2 修复 `hitTestHandle(at:)` 方法

**文件**：`Views/Editor/Canvas/SelectableShapeView.swift`

**位置**：第 338-383 行

**修改前**：

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

**修改后**：

```swift
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    guard isSelected else { return nil }

    let hitRadius: CGFloat = handleSize + 10

    // point 参数已经在本地坐标系中（由 gesture.location(in: self) 提供）
    // 直接使用 point 进行距离检测

    // 先检查旋转手柄（优先级更高）
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

### 5.3 修复总结

| 修改项 | 行数 | 变化 |
|-------|------|------|
| `point(inside:with:)` | 389-420 → 389-395 | 删除约 25 行坐标转换代码 |
| `hitTestHandle(at:)` | 338-383 → 338-358 | 删除约 25 行坐标转换代码 |

**核心改动**：删除所有手动反旋转计算，直接使用传入的 `point` 参数。

---

## 6. 修改文件清单

| 文件 | 修改类型 | 行号 | 说明 |
|------|----------|------|------|
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | 338-383 | 简化 `hitTestHandle(at:)` 方法 |
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | 389-420 | 简化 `point(inside:with:)` 方法 |

**修改文件数量**：1 个

**代码行数变化**：减少约 50 行

---

## 7. 验收标准

### 7.1 基础功能测试

- [ ] 创建矩形，旋转 45 度，再次选中可以继续旋转
- [ ] 创建矩形，旋转 45 度，再次选中可以缩放
- [ ] 创建矩形，旋转 90 度，再次选中可以移动、旋转、缩放
- [ ] 创建圆形，旋转 45 度，再次选中可以继续旋转
- [ ] 创建三角形，旋转 30 度，再次选中可以缩放

### 7.2 连续操作测试

- [ ] 创建形状 → 旋转 → 释放 → 选中 → 缩放 → 释放 → 选中 → 旋转（循环操作正常）
- [ ] 创建形状 → 旋转 → 移动 → 旋转 → 缩放（连续多种操作正常）
- [ ] 多次旋转（旋转 → 释放 → 旋转 → 释放 → 旋转）累计角度正确

### 7.3 边界情况测试

- [ ] 旋转 180 度后，控制点仍可正常响应
- [ ] 旋转 270 度后，控制点仍可正常响应
- [ ] 旋转 360 度（一圈）后，控制点仍可正常响应
- [ ] 极小形状（20x20）旋转后仍可操作
- [ ] 极大形状（500x500）旋转后仍可操作

### 7.4 回归测试

- [ ] 未旋转的形状，选择、移动、缩放功能正常
- [ ] 箭头工具功能正常（不应受影响）
- [ ] 圆形强制正方形约束仍然有效
- [ ] 撤销/重做功能正常
- [ ] 保存/加载后形状状态正确

---

## 附录 A：设计方案对比

### A.1 之前的设计方案 (canvas_tools_enhancement_v1.0.md) 的问题

之前的设计方案（`canvas_tools_enhancement_v1.0.md`）建议添加反旋转逻辑：

```swift
// 之前方案的建议（错误的）
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // 关键：将触摸点从世界坐标系反旋转到本地坐标系
    let rotationAngle = atan2(transform.b, transform.a)
    // ... 反旋转计算
}
```

这个建议基于错误的假设，导致代码越改越糟。

### A.2 正确理解

正确的理解是：

1. UIKit 的 `point(inside:with:)` 接收的 point 参数**已经是本地坐标系**
2. `gesture.location(in: self)` 返回的坐标**已经是本地坐标系**
3. 你不需要手动处理 transform 的坐标转换
4. 参考 `SelectableArrowView` 的简洁实现

---

## 附录 B：相关参考资料

1. [Apple UIView.transform 文档](https://developer.apple.com/documentation/uikit/uiview/1622459-transform)
2. [UIView bounds and transforms - Swift by Sundell](https://www.swiftbysundell.com/tips/uiview-bounds-and-transforms/)
3. [iOS, hitTesting a View](https://shawnbaek.com/2024/03/26/ios-hittesting-a-view-hittest-pointinside/)
4. [UIGestureRecognizer.location(in:) 文档](https://developer.apple.com/documentation/uikit/uigesturerecognizer/1624219-location)

---

## 附录 C：实施检查清单

- [ ] 阅读并理解本方案
- [ ] 备份当前 SelectableShapeView.swift
- [ ] 修改 `point(inside:with:)` 方法
- [ ] 修改 `hitTestHandle(at:)` 方法
- [ ] 运行所有验收测试
- [ ] 确认回归测试通过
- [ ] 更新 CHANGELOG.md

---

**文档版本**：v2.0
**创建日期**：2025-12-18
**状态**：待实施
