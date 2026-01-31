# 文字工具键盘联动优化修复方案 v2.0

## 1. 问题背景

### 1.1 历史实现回顾

根据归档记录（CHANGELOG-20260125-archived.md），文字工具的键盘联动功能经历了多轮迭代：

1. **2025-12-21**: 初始实现键盘自动定位功能
2. **2025-12-22**: 修复状态管理问题，实现"首次调整者负责制"
3. **2025-12-22**: 修复遗留问题（矫枉过正的画布还原、工具栏遮挡计算）
4. **2026-01-02**: 修复上移距离过大问题（从493pt降到60pt）

### 1.2 当前问题描述

用户反馈当前体验下降，具体表现为：

1. **移动距离不精确**：键盘弹出时画布移动距离可能过大或过小
2. **遮挡判断不准确**：只有点击被键盘覆盖的区域才需要移动，但判断逻辑可能失效
3. **重复移动问题**：键盘已弹出后再次点击画布，不应再次移动，但可能仍在移动
4. **恢复位置异常**：键盘收起时画布可能无法正确恢复到原始位置

### 1.3 预期行为

1. 文字工具选中时，点击画布弹出键盘
2. **智能判断**：只有当点击位置会被键盘遮挡时，才自动移动画布
3. **精确移动**：移动距离刚好让文字编辑框在键盘上方可见（考虑工具栏高度）
4. **避免重复**：键盘已弹出后再次点击，不再移动画布
5. **正确恢复**：键盘收起时，画布恢复到原始位置

---

## 2. 第一性原理分析

### 2.1 核心问题本质

键盘联动的本质是：**确保用户正在编辑的内容始终可见**。

这涉及三个核心计算：
1. **遮挡检测**：判断文字编辑框是否被键盘（及工具栏）遮挡
2. **偏移计算**：计算需要移动多少距离才能让编辑框可见
3. **状态管理**：正确管理"是否已调整"的状态，避免重复调整和正确恢复

### 2.2 坐标系统分析

MindCanvas 涉及多个坐标系：

```
屏幕坐标系 (Window)
    ↓
NativeCanvasView 坐标系
    ↓
PKCanvasView (pencilCanvas) 坐标系
    ↓
画布内容坐标系 (5000x5000)
```

**关键点**：
- 键盘高度是屏幕坐标系中的值
- UITextView 添加到 NativeCanvasView，使用屏幕坐标
- 画布滚动使用 PKCanvasView 的 contentOffset
- 缩放因子影响坐标转换

### 2.3 遮挡区域定义

遮挡区域 = 键盘高度 + 工具栏高度 + 舒适边距

```
┌─────────────────────────────────────┐
│                                     │
│           可见区域                   │
│                                     │
├─────────────────────────────────────┤ ← effectiveOcclusionTop
│         舒适边距 (20pt)              │
├─────────────────────────────────────┤
│         工具栏 (60pt)                │
├─────────────────────────────────────┤
│                                     │
│           键盘                       │
│                                     │
└─────────────────────────────────────┘
```

---

## 3. 现有代码分析

### 3.1 关键代码位置

| 文件 | 功能 |
|-----|------|
| `SelectableTextView.swift` | 键盘联动核心逻辑 |
| `NativeCanvasView.swift` | 画布管理、文字创建 |

### 3.2 当前实现架构

```swift
// 全局状态（静态变量，所有实例共享）
private static var isKeyboardVisible = false
private static var originalContentOffset: CGPoint = .zero
private static var responsibleInstance: SelectableTextView?
private static var hasAdjustedForKeyboard = false
```

### 3.3 关键方法分析

#### 3.3.1 keyboardWillShow (第1035-1111行)

```swift
@objc private func keyboardWillShow(notification: NSNotification) {
    // 1. 标记键盘可见
    Self.isKeyboardVisible = true

    // 2. 检查是否已调整（避免重复）
    if Self.hasAdjustedForKeyboard && Self.responsibleInstance != nil {
        updateTextViewPositionAfterScroll()
        return
    }

    // 3. 计算是否被遮挡
    let isTextHidden = calculateIfTextIsHidden(...)

    // 4. 如果被遮挡，执行调整
    if isTextHidden {
        // 保存原始位置
        Self.originalContentOffset = currentOffset
        Self.responsibleInstance = self
        Self.hasAdjustedForKeyboard = true

        // 计算并执行滚动
        ...
    }
}
```

#### 3.3.2 calculateIfTextIsHidden (第594-618行)

```swift
private func calculateIfTextIsHidden(...) -> Bool {
    let toolbarHeight: CGFloat = 60
    let keyboardTopInWindow = window.bounds.height - keyboardFrame.height
    let effectiveOcclusionTop = keyboardTopInWindow - toolbarHeight

    let textViewFrameInWindow = textView.convert(textView.bounds, to: window)
    let textViewBottomInWindow = textViewFrameInWindow.maxY

    return textViewBottomInWindow > effectiveOcclusionTop
}
```

#### 3.3.3 keyboardWillHide (第1137-1166行)

```swift
@objc private func keyboardWillHide(notification: NSNotification) {
    Self.isKeyboardVisible = false

    guard Self.hasAdjustedForKeyboard else {
        Self.responsibleInstance = nil
        return
    }

    // 恢复原始位置
    if currentOffset != Self.originalContentOffset {
        UIView.animate(...) {
            scrollView.setContentOffset(Self.originalContentOffset, animated: false)
        }
    }

    // 重置状态
    Self.hasAdjustedForKeyboard = false
    Self.responsibleInstance = nil
    Self.originalContentOffset = .zero
}
```

### 3.4 潜在问题点

1. **遮挡检测时机问题**：`calculateIfTextIsHidden` 在 `keyboardWillShow` 中调用时，UITextView 的 frame 可能还未更新到正确位置

2. **坐标转换问题**：UITextView 添加到 NativeCanvasView 后，其 frame 是相对于 NativeCanvasView 的，但 `convert(bounds, to: window)` 可能因为视图层级问题返回错误值

3. **状态重置时机**：`finishEditing` 中的状态保留逻辑可能与 `keyboardWillHide` 的重置逻辑冲突

4. **舒适边距计算**：当前在 `calculateIfTextIsHidden` 中没有包含舒适边距，但在 `keyboardWillShow` 的滚动计算中包含了

---

## 4. 修复方案

### 4.1 方案概述

采用"统一遮挡区域计算 + 精确状态管理"的策略：

1. **统一遮挡区域定义**：在所有计算中使用相同的遮挡区域定义
2. **修复坐标转换**：确保 UITextView 位置计算正确
3. **优化状态管理**：简化状态流转，避免边缘情况

### 4.2 具体修改

#### 4.2.1 统一遮挡区域常量

```swift
// 在 SelectableTextView 中添加常量
private enum KeyboardLayoutConstants {
    static let toolbarHeight: CGFloat = 60      // 键盘上方工具栏高度
    static let comfortableMargin: CGFloat = 20  // 舒适边距

    /// 计算有效遮挡区域顶部位置
    static func effectiveOcclusionTop(keyboardFrame: CGRect, in window: UIWindow) -> CGFloat {
        let keyboardTopInWindow = window.bounds.height - keyboardFrame.height
        return keyboardTopInWindow - toolbarHeight - comfortableMargin
    }
}
```

#### 4.2.2 修复 calculateIfTextIsHidden

```swift
private func calculateIfTextIsHidden(
    scrollView: UIScrollView,
    keyboardFrame: CGRect,
    textView: UITextView?
) -> Bool {
    guard let textView = textView else { return false }
    guard let window = scrollView.window else { return false }

    // 使用统一的遮挡区域计算
    let effectiveOcclusionTop = KeyboardLayoutConstants.effectiveOcclusionTop(
        keyboardFrame: keyboardFrame,
        in: window
    )

    // 获取 UITextView 在窗口坐标系中的位置
    // 注意：UITextView 添加到 NativeCanvasView，需要正确转换
    let textViewFrameInWindow = textView.convert(textView.bounds, to: window)
    let textViewBottomInWindow = textViewFrameInWindow.maxY

    return textViewBottomInWindow > effectiveOcclusionTop
}
```

#### 4.2.3 优化 keyboardWillShow

```swift
@objc private func keyboardWillShow(notification: NSNotification) {
    guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
    guard let canvasView = findParentCanvasView() else { return }

    // 1. 标记键盘可见
    Self.isKeyboardVisible = true

    // 2. 关键检查：如果已经调整过，只更新 UITextView 位置，不再移动画布
    if Self.hasAdjustedForKeyboard {
        updateTextViewPositionAfterScroll()
        return
    }

    let scrollView = canvasView.pencilCanvas
    let currentScale = scrollView.zoomScale
    let currentOffset = scrollView.contentOffset

    // 3. 确保 UITextView 位置是最新的
    updateTextViewPositionAfterScroll()

    // 4. 检查是否被遮挡
    let isTextHidden = calculateIfTextIsHidden(
        scrollView: scrollView,
        keyboardFrame: keyboardFrame,
        textView: editingTextView
    )

    // 5. 如果不被遮挡，无需调整
    guard isTextHidden else { return }

    // 6. 保存原始位置并标记
    Self.originalContentOffset = currentOffset
    Self.responsibleInstance = self
    Self.hasAdjustedForKeyboard = true

    // 7. 计算需要滚动的距离
    guard let textView = editingTextView,
          let window = scrollView.window else { return }

    let textViewFrameInWindow = textView.convert(textView.bounds, to: window)
    let textViewBottomInWindow = textViewFrameInWindow.maxY
    let effectiveOcclusionTop = KeyboardLayoutConstants.effectiveOcclusionTop(
        keyboardFrame: keyboardFrame,
        in: window
    )

    let overlapAmount = textViewBottomInWindow - effectiveOcclusionTop

    // 8. 将屏幕坐标的偏移量转换为画布内容坐标
    let scrollOffset = overlapAmount / currentScale

    // 9. 计算新的 contentOffset
    let newOffsetY = currentOffset.y + scrollOffset
    let canvasBounds = scrollView.bounds
    let maxOffsetY = scrollView.contentSize.height - canvasBounds.height
    let clampedOffsetY = min(newOffsetY, max(0, maxOffsetY))
    let newOffset = CGPoint(x: currentOffset.x, y: clampedOffsetY)

    // 10. 执行动画滚动
    let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3

    UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut]) {
        scrollView.setContentOffset(newOffset, animated: false)
    } completion: { _ in
        self.updateTextViewPositionAfterScroll()
    }
}
```

#### 4.2.4 简化 keyboardWillHide

```swift
@objc private func keyboardWillHide(notification: NSNotification) {
    // 1. 标记键盘隐藏
    Self.isKeyboardVisible = false

    // 2. 如果没有调整过，直接返回
    guard Self.hasAdjustedForKeyboard else {
        Self.responsibleInstance = nil
        return
    }

    // 3. 获取画布引用
    guard let canvasView = findParentCanvasView() else {
        resetAllKeyboardState()
        return
    }

    let scrollView = canvasView.pencilCanvas
    let currentOffset = scrollView.contentOffset
    let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3

    // 4. 恢复原始位置
    if currentOffset != Self.originalContentOffset {
        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut]) {
            scrollView.setContentOffset(Self.originalContentOffset, animated: false)
        } completion: { _ in
            self.updateTextViewPositionAfterScroll()
            self.resetAllKeyboardState()
        }
    } else {
        resetAllKeyboardState()
    }
}

/// 重置所有键盘相关状态
private func resetAllKeyboardState() {
    Self.hasAdjustedForKeyboard = false
    Self.responsibleInstance = nil
    Self.originalContentOffset = .zero
}
```

#### 4.2.5 修复 UITextView 位置更新

```swift
private func updateTextViewPositionAfterScroll() {
    guard let textView = editingTextView,
          let canvasView = findParentCanvasView() else {
        return
    }

    let scrollView = canvasView.pencilCanvas
    let currentScale = scrollView.zoomScale
    let currentOffset = scrollView.contentOffset

    // 计算文字节点在屏幕上的位置
    let textNodePosition = textNode.position
    let screenX = (textNodePosition.x * currentScale) - currentOffset.x
    let screenY = (textNodePosition.y * currentScale) - currentOffset.y

    // 保持 UITextView 的尺寸不变，只更新位置
    let currentSize = textView.frame.size
    let updatedFrame = CGRect(
        x: screenX - currentSize.width / 2,
        y: screenY - currentSize.height / 2,
        width: currentSize.width,
        height: currentSize.height
    )

    // 使用动画平滑更新位置
    UIView.animate(withDuration: 0.1) {
        textView.frame = updatedFrame
    }
}
```

### 4.3 边缘情况处理

#### 4.3.1 iPad 外接键盘

```swift
/// 检查是否是外接键盘（软键盘不弹出）
private func isExternalKeyboard(keyboardFrame: CGRect, in window: UIWindow) -> Bool {
    // 外接键盘时，keyboardFrame.origin.y >= window.bounds.height
    return keyboardFrame.origin.y >= window.bounds.height
}
```

在 `keyboardWillShow` 开头添加检查：

```swift
// 外接键盘不需要调整
if isExternalKeyboard(keyboardFrame: keyboardFrame, in: window) {
    return
}
```

#### 4.3.2 工具切换时的状态清理

确保 `NativeCanvasView.resetAllTextKeyboardStates()` 正确调用：

```swift
private func resetAllTextKeyboardStates() {
    for (_, textView) in textViews {
        if textView.isEditing {
            textView.finishEditing()
        }
    }

    // 强制重置全局状态并恢复位置
    SelectableTextView.resetGlobalKeyboardStateAndRestorePosition(canvasView: self)
}
```

---

## 5. 测试验证

### 5.1 测试场景

| 场景 | 预期行为 | 验证点 |
|-----|---------|-------|
| 点击画布底部创建文字 | 键盘弹出，画布上移 | 文字编辑框在键盘上方可见 |
| 点击画布顶部创建文字 | 键盘弹出，画布不移动 | 文字编辑框本身不被遮挡 |
| 键盘弹出后点击其他位置 | 画布不再移动 | hasAdjustedForKeyboard 阻止重复调整 |
| 按回车收起键盘 | 画布恢复原位 | contentOffset 恢复到 originalContentOffset |
| 切换工具收起键盘 | 画布恢复原位 | resetAllTextKeyboardStates 正确执行 |
| 不同缩放比例下 | 移动距离正确 | 考虑 zoomScale 的坐标转换 |
| 外接键盘 | 不做任何调整 | isExternalKeyboard 检测正确 |

### 5.2 验证步骤

1. **基础功能验证**
   - 选择文字工具
   - 点击画布底部（会被键盘遮挡的区域）
   - 验证键盘弹出后画布上移，文字编辑框可见
   - 按回车确认，验证画布恢复原位

2. **非遮挡区域验证**
   - 选择文字工具
   - 点击画布顶部（不会被键盘遮挡的区域）
   - 验证键盘弹出后画布不移动

3. **重复点击验证**
   - 选择文字工具
   - 点击画布底部，键盘弹出，画布上移
   - 不收起键盘，点击画布其他位置
   - 验证画布不再移动

4. **缩放状态验证**
   - 将画布缩放到 50%
   - 重复上述测试
   - 将画布缩放到 200%
   - 重复上述测试

---

## 6. 实施计划

### 6.1 修改文件清单

| 文件 | 修改内容 |
|-----|---------|
| `SelectableTextView.swift` | 键盘联动核心逻辑优化 |
| `NativeCanvasView.swift` | 状态清理逻辑确认 |

### 6.2 实施步骤

1. **Step 1**: 添加 `KeyboardLayoutConstants` 常量定义
2. **Step 2**: 修复 `calculateIfTextIsHidden` 方法
3. **Step 3**: 优化 `keyboardWillShow` 方法
4. **Step 4**: 简化 `keyboardWillHide` 方法
5. **Step 5**: 修复 `updateTextViewPositionAfterScroll` 方法
6. **Step 6**: 添加外接键盘检测
7. **Step 7**: 执行测试验证

### 6.3 风险评估

| 风险 | 影响 | 缓解措施 |
|-----|------|---------|
| 坐标转换错误 | 移动距离不正确 | 添加调试日志，逐步验证 |
| 状态管理混乱 | 画布无法恢复 | 简化状态流转，减少边缘情况 |
| 动画冲突 | 视觉抖动 | 使用 `.beginFromCurrentState` 选项 |

---

## 7. 参考资料

### 7.1 iOS 最佳实践

- 使用 `UIResponder.keyboardWillShowNotification` 而非 `keyboardDidShowNotification`
- 使用 `convert(_:to:)` 进行坐标转换
- 动画时长与系统键盘动画保持一致
- 使用 `setContentOffset(_:animated:)` 进行滚动

### 7.2 相关文档

- Apple Human Interface Guidelines: Keyboards
- UIKit: Managing the Keyboard
- PKCanvasView: Scroll View Integration

---

## 8. 总结

本方案从第一性原理出发，分析了键盘联动的核心问题：

1. **统一遮挡区域定义**：确保所有计算使用相同的遮挡区域
2. **精确坐标转换**：正确处理多坐标系之间的转换
3. **简化状态管理**：减少状态变量，明确状态流转
4. **完善边缘情况**：处理外接键盘、工具切换等场景

通过这些修改，可以实现精确、稳定的键盘联动体验。
