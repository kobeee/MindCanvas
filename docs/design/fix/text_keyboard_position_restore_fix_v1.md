# 文本工具键盘定位与画布还原问题修复方案 v1.0

## 文档信息
- **创建日期**: 2025-12-22
- **问题类型**: 键盘定位状态管理缺陷
- **严重级别**: 高 (影响核心用户体验)
- **涉及文件**:
  - `SelectableTextView.swift`
  - `NativeCanvasView.swift` (辅助)

---

## 一、问题现象

### 1.1 用户诉求
1. 文本编辑工具使用时，点击画布下方，键盘弹出，如果键盘会遮挡文本编辑框的话，画布要自动上移，避免键盘遮挡文本框
2. 只要键盘弹出后，在画布上其他地方点击编辑文本时，画布无需再移动，因为键盘已经弹出来了，不可能再遮挡到文本编辑框
3. 文本编辑框弹出的键盘，只要收起来（切换其他工具、输入回车、点击收起键盘按钮等），画布都需要还原到初始位置

### 1.2 实际问题表现
| 场景 | 预期行为 | 实际行为 | 状态 |
|------|----------|----------|------|
| 首次点击画布底部编辑文本 | 键盘弹出，画布上移 | 正常 | OK |
| 收起键盘 | 画布还原到原始位置 | 正常 | OK |
| 再次点击画布编辑文本 | 键盘弹出，画布上移 | 正常 | OK |
| 键盘弹出后继续点击画布其他位置多次 | 画布不移动 | 正常 | OK |
| 多次点击后收起键盘 | 画布还原到原始位置 | **画布不还原** | BUG |
| 工具切换后 | 画布还原到原始位置 | **画布不还原** | BUG |
| 回车确认后 | 画布还原到原始位置 | **画布不还原** | BUG |

---

## 二、根本原因分析

### 2.1 全局状态管理机制回顾

当前系统使用4个全局静态变量管理键盘定位状态：

```swift
// SelectableTextView.swift 第79-83行
private static var isKeyboardVisible = false           // 键盘是否可见
private static var originalContentOffset: CGPoint = .zero  // 原始画布偏移
private static var responsibleInstance: SelectableTextView? // 负责恢复的实例
private static var hasAdjustedForKeyboard = false      // 是否已调整过位置
```

### 2.2 核心问题：通知监听器生命周期管理错误

#### 问题1：键盘隐藏通知无法被正确接收

当用户在键盘弹出后点击画布其他位置创建新文本时：

```
时序图：
用户点击画布位置A --> 创建TextViewA --> startEditing() --> setupKeyboardNotifications()
                                                            ^-- 注册监听 keyboardWillShow/Hide
键盘弹出 --> keyboardWillShow被TextViewA接收 --> 记录originalContentOffset --> 调整画布位置
                                                 设置 responsibleInstance = TextViewA
                                                 设置 hasAdjustedForKeyboard = true

用户点击画布位置B --> 创建TextViewB --> startEditing()
                                   --> 检测到键盘已显示，重置状态:
                                       hasAdjustedForKeyboard = false  <-- 问题根源1！
                                       responsibleInstance = nil        <-- 问题根源2！
                                   --> setupKeyboardNotifications()

用户收起键盘 --> keyboardWillHide被TextViewB接收
           --> 检查 responsibleInstance === self --> FALSE (responsibleInstance是nil)
           --> 跳过恢复逻辑！<-- BUG发生点
```

#### 问题2：startEditing中错误地清理状态

```swift
// SelectableTextView.swift 第481-487行
func startEditing() {
    // ...
    // 这段代码的意图是好的：避免状态冲突
    // 但实际效果是：销毁了恢复画布位置所需的关键信息
    if Self.isKeyboardVisible {
        print("⚠️ [TextView] 检测到键盘仍然显示，重置全局状态以避免冲突")
        Self.hasAdjustedForKeyboard = false  // 错误：清除了"需要恢复"的标记
        Self.responsibleInstance = nil       // 错误：清除了负责恢复的实例
    }
    // ...
}
```

#### 问题3：finishEditing与keyboardWillHide的竞态条件

当用户按回车键确认时：
```
回车键 --> textView(shouldChangeTextIn:) 返回 false 并调用 finishEditing()
      --> finishEditing() 执行：
          1. cleanupEditingTextView() --> removeKeyboardNotifications() <-- 移除监听器！
          2. editingTextView.resignFirstResponder() --> 触发键盘隐藏
      --> keyboardWillHide通知发出
      --> 但监听器已被移除，无法接收通知！<-- BUG发生点
```

#### 问题4：工具切换时的处理顺序问题

```swift
// NativeCanvasView.swift 第2002-2012行
NotificationCenter.default.addObserver(...) { notification in
    // 工具切换时：
    self?.resetAllTextKeyboardStates()  // 调用 finishEditing() 和 resetGlobalKeyboardState()

    if let tool = notification.object as? CanvasTool {
        self?.updateForTool(tool)
    }
}

// 问题链路：
// resetAllTextKeyboardStates() --> finishEditing() --> cleanupEditingTextView()
//                              --> removeKeyboardNotifications() <-- 移除监听器
//                              --> resignFirstResponder() <-- 触发键盘隐藏
//                              --> 但已无法接收keyboardWillHide通知
//                              --> resetGlobalKeyboardState() 只重置状态
//                              --> 没有执行实际的画布位置恢复！
```

### 2.3 问题汇总

| 问题编号 | 问题描述 | 影响场景 | 根本原因 |
|---------|---------|---------|---------|
| P1 | startEditing中过早清除状态 | 多次点击编辑 | 新实例编辑时清除了恢复所需的状态 |
| P2 | finishEditing中先移除监听再收起键盘 | 回车确认 | 监听器移除后无法接收keyboardWillHide |
| P3 | 工具切换时没有主动恢复画布位置 | 切换工具 | resetGlobalKeyboardState只重置状态不恢复位置 |
| P4 | 多实例场景下responsibleInstance丢失 | 多次点击编辑 | 新实例覆盖了原有的responsible标记 |

---

## 三、修复方案

### 3.1 设计原则

1. **单一责任原则**：画布位置恢复的责任应该明确归属，不应随实例切换而丢失
2. **状态一致性**：在任何时刻，`originalContentOffset`和`hasAdjustedForKeyboard`必须保持一致
3. **主动恢复优于被动等待**：在可预期的键盘收起场景（回车、工具切换），主动执行恢复逻辑

### 3.2 核心修复：重新设计状态管理

#### 修复策略：转变为"首次调整者负责制"

- 只有第一次调整画布位置的实例才能成为"责任实例"
- 责任实例不会被后续的编辑操作覆盖
- 责任实例被销毁时，必须完成位置恢复或交接责任

### 3.3 具体修改

#### 修改1：移除startEditing中的错误状态清理

**文件**: `SelectableTextView.swift`
**位置**: 第471-494行 `startEditing()` 方法

**修改前**:
```swift
func startEditing() {
    guard !isEditing else { return }

    isEditing = true
    onEditingStarted?(textNode)

    print("✏️ [TextView] 开始编辑 - 实例: \(ObjectIdentifier(self))")
    print("✏️ [TextView] 编辑前全局状态 - hasAdjustedForKeyboard: \(Self.hasAdjustedForKeyboard), responsibleInstance: \(Self.responsibleInstance != nil ? "\(ObjectIdentifier(Self.responsibleInstance!))" : "无")")

    // 🔧 关键修复：每次开始新编辑时，重置全局状态
    // 这确保每次编辑都是独立的会话
    if Self.isKeyboardVisible {
        print("⚠️ [TextView] 检测到键盘仍然显示，重置全局状态以避免冲突")
        Self.hasAdjustedForKeyboard = false  // <-- 错误：不应该清除
        Self.responsibleInstance = nil       // <-- 错误：不应该清除
    }

    // 隐藏Label
    textLabel.isHidden = true

    // 创建UITextView
    setupEditingTextView()
}
```

**修改后**:
```swift
func startEditing() {
    guard !isEditing else { return }

    isEditing = true
    onEditingStarted?(textNode)

    print("✏️ [TextView] 开始编辑 - 实例: \(ObjectIdentifier(self))")
    print("✏️ [TextView] 编辑前全局状态 - hasAdjustedForKeyboard: \(Self.hasAdjustedForKeyboard), responsibleInstance: \(Self.responsibleInstance != nil ? "\(ObjectIdentifier(Self.responsibleInstance!))" : "无")")

    // 键盘已显示时，不重置状态
    // 原因：原始位置信息和责任实例需要保留，用于最终恢复画布位置
    // 当键盘收起时，无论是哪个实例触发的收起，都应该恢复到最初记录的位置
    if Self.isKeyboardVisible {
        print("ℹ️ [TextView] 键盘已显示，保留原始位置信息用于最终恢复")
        // 注意：不清除 hasAdjustedForKeyboard 和 responsibleInstance
        // 这些信息需要保留到键盘真正收起时使用
    }

    // 隐藏Label
    textLabel.isHidden = true

    // 创建UITextView
    setupEditingTextView()
}
```

#### 修改2：修复finishEditing中的执行顺序

**文件**: `SelectableTextView.swift`
**位置**: 第497-545行 `finishEditing()` 方法

**修改前**:
```swift
func finishEditing() {
    guard isEditing else { return }

    print("✏️ [TextView] 完成编辑 - 实例: \(ObjectIdentifier(self))")

    let rawText = editingTextView?.text ?? ""
    let originalText = textNode.text

    // 处理占位符情况：如果显示的是占位符，则视为空文本
    let newText: String
    if isShowingPlaceholder || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        newText = ""
    } else {
        newText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 🔧 关键修复：如果当前实例是负责实例，主动清理状态
    if Self.responsibleInstance === self {
        print("🧹 [TextView] 清理负责实例状态")
        Self.responsibleInstance = nil
        Self.hasAdjustedForKeyboard = false
    }

    // 清理编辑视图
    cleanupEditingTextView()  // <-- 这里移除监听器并收起键盘

    // ... 后续处理
}
```

**修改后**:
```swift
func finishEditing() {
    guard isEditing else { return }

    print("✏️ [TextView] 完成编辑 - 实例: \(ObjectIdentifier(self))")

    let rawText = editingTextView?.text ?? ""
    let originalText = textNode.text

    // 处理占位符情况
    let newText: String
    if isShowingPlaceholder || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        newText = ""
    } else {
        newText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 关键修复：在移除监听器之前，主动执行画布位置恢复
    // 因为resignFirstResponder会触发键盘隐藏，但此时监听器即将被移除
    let shouldRestorePosition = Self.hasAdjustedForKeyboard
    let savedOriginalOffset = Self.originalContentOffset

    if shouldRestorePosition {
        print("📍 [TextView] finishEditing - 主动恢复画布位置到: \(savedOriginalOffset)")
        // 主动恢复画布位置
        if let canvasView = findParentCanvasView() {
            let scrollView = canvasView.pencilCanvas
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
                scrollView.setContentOffset(savedOriginalOffset, animated: false)
            }
        }
    }

    // 重置全局状态（在恢复位置之后）
    Self.hasAdjustedForKeyboard = false
    Self.responsibleInstance = nil
    Self.isKeyboardVisible = false  // 同时重置键盘可见状态

    // 清理编辑视图（现在可以安全移除监听器了）
    cleanupEditingTextView()

    // 显示Label
    textLabel.isHidden = false
    isEditing = false
    isShowingPlaceholder = false

    // 如果文本为空，通过回调通知删除该对象
    if newText.isEmpty {
        onEditingFinished?(textNode, "")
        return
    }

    // 更新节点
    textNode = textNode.updated(text: newText)

    // 更新显示
    updateFromNode()

    // 回调
    if newText != originalText {
        onEditingFinished?(textNode, newText)
    }
    onNodeUpdated?(textNode)
}
```

#### 修改3：优化keyboardWillShow，修复责任实例判断逻辑

**文件**: `SelectableTextView.swift`
**位置**: 第936-1053行 `keyboardWillShow()` 方法

**问题**: 当前逻辑在键盘已显示时，第二个编辑实例也会尝试处理keyboardWillShow，但条件判断有缺陷。

**修改前**:
```swift
@objc private func keyboardWillShow(notification: NSNotification) {
    // ...

    // 只有需要调整时才记录原始位置和执行调整
    if shouldAdjust {
        // 记录原始位置（只在第一次调整时记录）
        Self.originalContentOffset = currentOffset
        Self.responsibleInstance = self  // 记录负责的实例
        Self.hasAdjustedForKeyboard = true
        // ...
    }
    // ...
}
```

**修改后**:
```swift
@objc private func keyboardWillShow(notification: NSNotification) {
    print("🎹 [Keyboard] 键盘弹出通知接收 - 实例: \(ObjectIdentifier(self))")
    guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
    guard let canvasView = findParentCanvasView() else { return }

    // 标记键盘为显示状态
    Self.isKeyboardVisible = true

    print("🎹 [Keyboard] 全局状态 - hasAdjusted: \(Self.hasAdjustedForKeyboard), responsible: \(Self.responsibleInstance.map { "\(ObjectIdentifier($0))" } ?? "无")")

    // 关键修复：如果已经有责任实例且已调整过位置，后续实例不应该重复处理
    // 这保证了originalContentOffset始终是第一次调整前的真实位置
    if Self.hasAdjustedForKeyboard && Self.responsibleInstance != nil {
        print("ℹ️ [Keyboard] 已有责任实例处理过画布调整，当前实例跳过处理")
        // 只需要更新当前UITextView的位置
        updateTextViewPositionAfterScroll()
        return
    }

    // 获取画布当前状态
    let scrollView = canvasView.pencilCanvas
    let currentScale = scrollView.zoomScale
    let currentOffset = scrollView.contentOffset
    let canvasBounds = scrollView.bounds

    // 获取键盘信息
    let keyboardScreenFrame = keyboardFrame
    let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3

    // 检查文本是否被键盘遮挡
    let isTextHidden = calculateIfTextIsHidden(
        scrollView: scrollView,
        keyboardFrame: keyboardScreenFrame,
        textView: editingTextView
    )

    print("🎹 [Keyboard] 遮挡检测: isTextHidden=\(isTextHidden)")

    // 需要调整且尚未调整过
    if isTextHidden {
        // 记录原始位置（这是第一次调整，记录真实的原始位置）
        Self.originalContentOffset = currentOffset
        Self.responsibleInstance = self
        Self.hasAdjustedForKeyboard = true

        print("📍 [Keyboard] 记录原始位置: \(Self.originalContentOffset)")

        // 执行画布位置调整...
        // (后续调整逻辑保持不变)

        // 计算键盘高度和文本框位置
        guard let textView = editingTextView else { return }
        guard let window = scrollView.window else { return }

        let textNodePosition = textNode.position
        let screenX = (textNodePosition.x * currentScale) - currentOffset.x
        let screenY = (textNodePosition.y * currentScale) - currentOffset.y

        // 更新UITextView位置
        let textViewFrame = CGRect(
            x: screenX - textView.frame.width / 2,
            y: screenY - textView.frame.height / 2,
            width: textView.frame.width,
            height: textView.frame.height
        )
        textView.frame = textViewFrame

        // 计算需要滚动的距离
        let textViewFrameInWindow = textView.convert(textViewFrame, to: window)
        let textViewBottomInScreen = textViewFrameInWindow.maxY
        let keyboardHeight = keyboardScreenFrame.height
        let keyboardTopInScreen = window.bounds.height - keyboardHeight
        let overlapAmount = textViewBottomInScreen - keyboardTopInScreen

        if overlapAmount > 0 {
            let comfortableMargin: CGFloat = 30
            let maxScrollDistance = canvasBounds.height * 0.4
            let requiredOffset = min(max(0, overlapAmount + comfortableMargin), maxScrollDistance)
            let scrollOffset = requiredOffset / currentScale

            let newOffsetY = currentOffset.y + scrollOffset
            let maxOffsetY = scrollView.contentSize.height - canvasBounds.height
            let clampedOffsetY = min(newOffsetY, max(0, maxOffsetY))
            let newOffset = CGPoint(x: currentOffset.x, y: clampedOffsetY)

            UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut]) {
                scrollView.setContentOffset(newOffset, animated: false)
            } completion: { _ in
                self.updateTextViewPositionAfterScroll()
                print("✅ [Keyboard] 画布位置调整完成")
            }
        }
    } else {
        // 文本框可见，无需调整，但仍需更新位置
        updateTextViewPositionAfterScroll()
    }
}
```

#### 修改4：简化keyboardWillHide，添加防御性检查

**文件**: `SelectableTextView.swift`
**位置**: 第1080-1132行 `keyboardWillHide()` 方法

**修改前**:
```swift
@objc private func keyboardWillHide(notification: NSNotification) {
    print("🎹 [Keyboard] 键盘隐藏通知接收 - 实例: \(ObjectIdentifier(self))")
    print("🎹 [Keyboard] 当前负责实例: \(Self.responsibleInstance != nil ? "\(ObjectIdentifier(Self.responsibleInstance!))" : "无")")

    // 只有负责的实例才执行恢复逻辑
    guard Self.responsibleInstance === self else {
        print("⚠️ [Keyboard] 跳过恢复 - 当前实例不是负责实例")
        return
    }
    // ...
}
```

**修改后**:
```swift
@objc private func keyboardWillHide(notification: NSNotification) {
    print("🎹 [Keyboard] 键盘隐藏通知接收 - 实例: \(ObjectIdentifier(self))")

    // 重置键盘可见状态
    Self.isKeyboardVisible = false

    // 防御性检查：如果没有调整过位置，无需恢复
    guard Self.hasAdjustedForKeyboard else {
        print("ℹ️ [Keyboard] 未调整过画布位置，跳过恢复")
        Self.responsibleInstance = nil  // 清理可能的残留状态
        return
    }

    guard let canvasView = findParentCanvasView() else {
        // 清理状态
        Self.hasAdjustedForKeyboard = false
        Self.responsibleInstance = nil
        return
    }

    let scrollView = canvasView.pencilCanvas
    let currentOffset = scrollView.contentOffset
    let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3

    print("📍 [Keyboard] 准备恢复位置: 当前=\(currentOffset), 原始=\(Self.originalContentOffset)")

    // 恢复画布位置
    if currentOffset != Self.originalContentOffset {
        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut]) {
            scrollView.setContentOffset(Self.originalContentOffset, animated: false)
        } completion: { _ in
            self.updateTextViewPositionAfterScroll()
            print("✅ [Keyboard] 画布位置恢复完成")
        }
    }

    // 无论是否执行恢复，都要重置状态
    Self.hasAdjustedForKeyboard = false
    Self.responsibleInstance = nil
    Self.originalContentOffset = .zero
}
```

#### 修改5：修复resetGlobalKeyboardState，添加主动恢复逻辑

**文件**: `SelectableTextView.swift`
**位置**: 第905-911行 `resetGlobalKeyboardState()` 方法

**修改前**:
```swift
static func resetGlobalKeyboardState() {
    print("🔄 [Keyboard] 重置全局键盘状态")
    isKeyboardVisible = false
    hasAdjustedForKeyboard = false
    originalContentOffset = .zero
    responsibleInstance = nil
}
```

**修改后** (需要添加新方法):
```swift
/// 重置全局键盘状态（仅重置状态，不恢复位置）
static func resetGlobalKeyboardState() {
    print("🔄 [Keyboard] 重置全局键盘状态")
    isKeyboardVisible = false
    hasAdjustedForKeyboard = false
    originalContentOffset = .zero
    responsibleInstance = nil
}

/// 重置全局键盘状态并恢复画布位置
/// - Parameter canvasView: 画布视图引用，用于执行位置恢复
static func resetGlobalKeyboardStateAndRestorePosition(canvasView: NativeCanvasView?) {
    print("🔄 [Keyboard] 重置全局键盘状态并恢复位置")

    // 如果有调整过位置，先执行恢复
    if hasAdjustedForKeyboard, let canvasView = canvasView {
        let scrollView = canvasView.pencilCanvas
        let savedOffset = originalContentOffset

        print("📍 [Keyboard] 主动恢复画布位置到: \(savedOffset)")

        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            scrollView.setContentOffset(savedOffset, animated: false)
        }
    }

    // 重置所有状态
    isKeyboardVisible = false
    hasAdjustedForKeyboard = false
    originalContentOffset = .zero
    responsibleInstance = nil
}
```

#### 修改6：更新NativeCanvasView中的工具切换处理

**文件**: `NativeCanvasView.swift`
**位置**: 第2016-2026行 `resetAllTextKeyboardStates()` 方法

**修改前**:
```swift
private func resetAllTextKeyboardStates() {
    for (_, textView) in textViews {
        if textView.isEditing {
            print("🧹 [Canvas] 强制结束文本编辑: \(textView.textNode.id)")
            textView.finishEditing()
        }
    }

    // 🔧 关键修复：重置全局静态状态
    SelectableTextView.resetGlobalKeyboardState()
}
```

**修改后**:
```swift
private func resetAllTextKeyboardStates() {
    // 先获取是否需要恢复位置的信息（在finishEditing之前）
    // 因为finishEditing现在会主动恢复位置，这里不需要额外处理

    for (_, textView) in textViews {
        if textView.isEditing {
            print("🧹 [Canvas] 强制结束文本编辑: \(textView.textNode.id)")
            textView.finishEditing()  // finishEditing现在会主动恢复位置
        }
    }

    // 确保全局状态被重置（finishEditing应该已经处理了，这是防御性代码）
    SelectableTextView.resetGlobalKeyboardState()
}
```

---

## 四、验证方案

### 4.1 添加调试日志

在修复过程中，建议添加以下调试日志点，帮助验证修复效果：

```swift
// 在startEditing开始处添加
print("=== START EDITING ===")
print("[State] isKeyboardVisible: \(Self.isKeyboardVisible)")
print("[State] hasAdjustedForKeyboard: \(Self.hasAdjustedForKeyboard)")
print("[State] originalContentOffset: \(Self.originalContentOffset)")
print("[State] responsibleInstance: \(Self.responsibleInstance.map { ObjectIdentifier($0).description } ?? "nil")")

// 在finishEditing开始处添加
print("=== FINISH EDITING ===")
print("[State] 同上...")

// 在keyboardWillShow收到通知时添加
print("=== KEYBOARD WILL SHOW ===")
print("[State] 同上...")

// 在keyboardWillHide收到通知时添加
print("=== KEYBOARD WILL HIDE ===")
print("[State] 同上...")

// 在resetGlobalKeyboardState调用时添加
print("=== RESET GLOBAL STATE ===")
```

### 4.2 测试用例

| 编号 | 测试场景 | 预期结果 | 验证要点 |
|------|---------|---------|---------|
| TC01 | 首次点击画布底部创建文本 | 键盘弹出，画布上移 | originalContentOffset正确记录 |
| TC02 | TC01后收起键盘 | 画布恢复到原始位置 | contentOffset恢复正确 |
| TC03 | TC01后点击画布其他位置创建新文本 | 画布不再移动 | 日志显示跳过调整 |
| TC04 | TC03后收起键盘 | 画布恢复到TC01前的位置 | 使用原始originalContentOffset |
| TC05 | TC03后切换到选择工具 | 键盘收起，画布恢复 | finishEditing主动恢复 |
| TC06 | TC03后按回车确认 | 键盘收起，画布恢复 | finishEditing主动恢复 |
| TC07 | TC03后点击收起键盘按钮 | 键盘收起，画布恢复 | keyboardWillHide恢复 |
| TC08 | 点击画布上方（不被遮挡）创建文本 | 画布不移动 | hasAdjustedForKeyboard保持false |
| TC09 | TC08后收起键盘 | 画布位置不变 | 无需恢复 |

### 4.3 验收标准

1. **功能正确性**
   - 所有9个测试用例通过
   - 无论如何操作，键盘收起后画布都能恢复到正确位置

2. **状态一致性**
   - 键盘收起后，所有全局状态都被正确重置
   - 不存在状态残留导致的后续问题

3. **用户体验**
   - 动画平滑，无卡顿
   - 响应及时，无明显延迟

---

## 五、风险评估

### 5.1 潜在风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| finishEditing主动恢复可能与keyboardWillHide重复 | 画布位置被设置两次 | 在keyboardWillHide中检查hasAdjustedForKeyboard |
| 快速连续点击可能导致状态混乱 | 画布位置不正确 | 使用原子操作和状态锁 |
| 极端情况下findParentCanvasView返回nil | 状态无法正确恢复 | 添加防御性代码和错误日志 |

### 5.2 建议的额外优化

1. **考虑使用DispatchQueue进行状态同步**
   ```swift
   private static let stateQueue = DispatchQueue(label: "com.mindcanvas.keyboard.state")
   ```

2. **添加状态校验机制**
   - 在每次状态变更后验证状态一致性
   - 发现不一致时自动恢复到安全状态

---

## 六、实施步骤

### 步骤1：备份现有代码
```bash
git checkout -b fix/text-keyboard-restore
```

### 步骤2：按顺序修改代码
1. 修改 `startEditing()` - 移除错误的状态清理
2. 修改 `finishEditing()` - 添加主动位置恢复
3. 修改 `keyboardWillShow()` - 优化责任实例判断
4. 修改 `keyboardWillHide()` - 简化恢复逻辑
5. 添加 `resetGlobalKeyboardStateAndRestorePosition()` 方法
6. 更新 `resetAllTextKeyboardStates()` 调用

### 步骤3：添加调试日志
按照4.1节的指导添加调试日志

### 步骤4：运行测试用例
按照4.2节的测试用例逐一验证

### 步骤5：清理调试日志
验证通过后移除或减少调试日志

### 步骤6：代码审查
提交PR进行代码审查

---

## 七、附录

### A. 状态流转图

```
                                  用户点击画布底部创建文本
                                           |
                                           v
                               +------------------------+
                               | startEditing()         |
                               | isEditing = true       |
                               | setupKeyboardNotifications()
                               +------------------------+
                                           |
                                           v
                               +------------------------+
                               | keyboardWillShow()     |
                               | isKeyboardVisible=true |
                               | hasAdjusted=true       |
                               | originalOffset=current |
                               | responsible=self       |
                               | 执行画布位置调整        |
                               +------------------------+
                                           |
               +---------------------------+---------------------------+
               |                           |                           |
               v                           v                           v
    用户再次点击画布              用户按回车                  用户切换工具/点击收起按钮
               |                           |                           |
               v                           v                           v
    +------------------------+  +------------------------+  +------------------------+
    | startEditing()         |  | finishEditing()        |  | resetAllTextKeyboardStates()
    | 检测到键盘已显示        |  | 1.主动恢复画布位置    |  | -> finishEditing()    |
    | 保留状态不清除          |  | 2.重置全局状态        |  | 1.主动恢复画布位置    |
    +------------------------+  | 3.resignFirstResponder|  | 2.重置全局状态        |
               |                +------------------------+  +------------------------+
               v                           |                           |
    +------------------------+             |                           |
    | keyboardWillShow()     |             v                           v
    | 检测到hasAdjusted=true |  +------------------------+  +------------------------+
    | 跳过调整，只更新位置    |  | 键盘已收起             |  | 键盘收起               |
    +------------------------+  | 画布已恢复             |  | 画布已恢复             |
               |                +------------------------+  +------------------------+
               v
    (等待用户下一步操作...)
               |
               v
    +------------------------+
    | keyboardWillHide()     |
    | 检测到hasAdjusted=true |
    | 恢复画布到原始位置      |
    | 重置全局状态            |
    +------------------------+
               |
               v
    +------------------------+
    | 画布位置已恢复          |
    | 状态已重置              |
    +------------------------+
```

### B. 关键代码位置速查

| 方法 | 文件 | 行号 | 作用 |
|------|------|------|------|
| startEditing | SelectableTextView.swift | 471-494 | 开始编辑，设置监听 |
| finishEditing | SelectableTextView.swift | 497-545 | 结束编辑，清理资源 |
| keyboardWillShow | SelectableTextView.swift | 936-1053 | 键盘弹出处理 |
| keyboardWillHide | SelectableTextView.swift | 1080-1132 | 键盘隐藏处理 |
| resetGlobalKeyboardState | SelectableTextView.swift | 905-911 | 重置全局状态 |
| resetAllTextKeyboardStates | NativeCanvasView.swift | 2016-2026 | 工具切换时重置 |

---

## 八、修复后的完整代码参考

以下是修复后的关键方法完整代码，供执行人员参考：

### 8.1 startEditing() 完整代码

```swift
/// 开始编辑文字
func startEditing() {
    guard !isEditing else { return }

    isEditing = true
    onEditingStarted?(textNode)

    print("✏️ [TextView] 开始编辑 - 实例: \(ObjectIdentifier(self))")
    print("✏️ [TextView] 全局状态 - hasAdjusted: \(Self.hasAdjustedForKeyboard), responsible: \(Self.responsibleInstance.map { ObjectIdentifier($0).description } ?? "nil")")

    // 关键点：键盘已显示时，保留原始位置信息
    // 不重置 hasAdjustedForKeyboard 和 responsibleInstance
    // 这些信息需要保留到键盘真正收起时使用
    if Self.isKeyboardVisible {
        print("ℹ️ [TextView] 键盘已显示，保留原始位置信息")
    }

    // 隐藏Label
    textLabel.isHidden = true

    // 创建UITextView
    setupEditingTextView()
}
```

### 8.2 finishEditing() 完整代码

```swift
/// 完成编辑文字
func finishEditing() {
    guard isEditing else { return }

    print("✏️ [TextView] 完成编辑 - 实例: \(ObjectIdentifier(self))")

    let rawText = editingTextView?.text ?? ""
    let originalText = textNode.text

    // 处理占位符情况
    let newText: String
    if isShowingPlaceholder || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        newText = ""
    } else {
        newText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // 关键修复：在移除监听器之前，主动执行画布位置恢复
    // 因为resignFirstResponder会触发键盘隐藏，但此时监听器即将被移除
    if Self.hasAdjustedForKeyboard {
        let savedOffset = Self.originalContentOffset
        print("📍 [TextView] finishEditing - 主动恢复画布位置到: \(savedOffset)")

        if let canvasView = findParentCanvasView() {
            let scrollView = canvasView.pencilCanvas
            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
                scrollView.setContentOffset(savedOffset, animated: false)
            }
        }
    }

    // 重置全局状态
    Self.hasAdjustedForKeyboard = false
    Self.responsibleInstance = nil
    Self.isKeyboardVisible = false
    Self.originalContentOffset = .zero

    // 清理编辑视图
    cleanupEditingTextView()

    // 显示Label
    textLabel.isHidden = false
    isEditing = false
    isShowingPlaceholder = false

    // 如果文本为空，通过回调通知删除该对象
    if newText.isEmpty {
        onEditingFinished?(textNode, "")
        return
    }

    // 更新节点
    textNode = textNode.updated(text: newText)

    // 更新显示
    updateFromNode()

    // 回调
    if newText != originalText {
        onEditingFinished?(textNode, newText)
    }
    onNodeUpdated?(textNode)
}
```

### 8.3 keyboardWillShow() 完整代码

```swift
@objc private func keyboardWillShow(notification: NSNotification) {
    print("🎹 [Keyboard] 键盘弹出通知 - 实例: \(ObjectIdentifier(self))")
    guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
    guard let canvasView = findParentCanvasView() else { return }

    // 标记键盘为显示状态
    Self.isKeyboardVisible = true

    print("🎹 [Keyboard] 状态 - hasAdjusted: \(Self.hasAdjustedForKeyboard), responsible: \(Self.responsibleInstance.map { ObjectIdentifier($0).description } ?? "nil")")

    // 关键修复：如果已经调整过位置，后续实例不再处理
    if Self.hasAdjustedForKeyboard && Self.responsibleInstance != nil {
        print("ℹ️ [Keyboard] 已有责任实例，跳过调整")
        updateTextViewPositionAfterScroll()
        return
    }

    let scrollView = canvasView.pencilCanvas
    let currentScale = scrollView.zoomScale
    let currentOffset = scrollView.contentOffset
    let canvasBounds = scrollView.bounds
    let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3

    // 检查文本是否被键盘遮挡
    let isTextHidden = calculateIfTextIsHidden(
        scrollView: scrollView,
        keyboardFrame: keyboardFrame,
        textView: editingTextView
    )

    if isTextHidden {
        // 记录原始位置
        Self.originalContentOffset = currentOffset
        Self.responsibleInstance = self
        Self.hasAdjustedForKeyboard = true

        print("📍 [Keyboard] 记录原始位置: \(Self.originalContentOffset)")

        guard let textView = editingTextView else { return }
        guard let window = scrollView.window else { return }

        // 计算文本框位置
        let textNodePosition = textNode.position
        let screenX = (textNodePosition.x * currentScale) - currentOffset.x
        let screenY = (textNodePosition.y * currentScale) - currentOffset.y

        let textViewFrame = CGRect(
            x: screenX - textView.frame.width / 2,
            y: screenY - textView.frame.height / 2,
            width: textView.frame.width,
            height: textView.frame.height
        )
        textView.frame = textViewFrame

        // 计算重叠量
        let textViewFrameInWindow = textView.convert(textViewFrame, to: window)
        let textViewBottomInScreen = textViewFrameInWindow.maxY
        let keyboardHeight = keyboardFrame.height
        let keyboardTopInScreen = window.bounds.height - keyboardHeight
        let overlapAmount = textViewBottomInScreen - keyboardTopInScreen

        if overlapAmount > 0 {
            let comfortableMargin: CGFloat = 30
            let maxScrollDistance = canvasBounds.height * 0.4
            let requiredOffset = min(max(0, overlapAmount + comfortableMargin), maxScrollDistance)
            let scrollOffset = requiredOffset / currentScale

            let newOffsetY = currentOffset.y + scrollOffset
            let maxOffsetY = scrollView.contentSize.height - canvasBounds.height
            let clampedOffsetY = min(newOffsetY, max(0, maxOffsetY))
            let newOffset = CGPoint(x: currentOffset.x, y: clampedOffsetY)

            print("🎯 [Keyboard] 调整画布: \(currentOffset) -> \(newOffset)")

            UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut]) {
                scrollView.setContentOffset(newOffset, animated: false)
            } completion: { _ in
                self.updateTextViewPositionAfterScroll()
            }
        }
    } else {
        updateTextViewPositionAfterScroll()
    }
}
```

### 8.4 keyboardWillHide() 完整代码

```swift
@objc private func keyboardWillHide(notification: NSNotification) {
    print("🎹 [Keyboard] 键盘隐藏通知 - 实例: \(ObjectIdentifier(self))")

    // 重置键盘可见状态
    Self.isKeyboardVisible = false

    // 如果没有调整过位置，无需恢复
    guard Self.hasAdjustedForKeyboard else {
        print("ℹ️ [Keyboard] 未调整过位置，跳过恢复")
        Self.responsibleInstance = nil
        Self.originalContentOffset = .zero
        return
    }

    guard let canvasView = findParentCanvasView() else {
        Self.hasAdjustedForKeyboard = false
        Self.responsibleInstance = nil
        Self.originalContentOffset = .zero
        return
    }

    let scrollView = canvasView.pencilCanvas
    let currentOffset = scrollView.contentOffset
    let savedOffset = Self.originalContentOffset
    let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3

    print("📍 [Keyboard] 恢复位置: \(currentOffset) -> \(savedOffset)")

    if currentOffset != savedOffset {
        UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut]) {
            scrollView.setContentOffset(savedOffset, animated: false)
        } completion: { _ in
            self.updateTextViewPositionAfterScroll()
            print("✅ [Keyboard] 位置恢复完成")
        }
    }

    // 重置所有状态
    Self.hasAdjustedForKeyboard = false
    Self.responsibleInstance = nil
    Self.originalContentOffset = .zero
}
```

---

**文档结束**
