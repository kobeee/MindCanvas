# MindCanvas 文本工具与键盘问题终极修复方案

**版本**: v1.0
**日期**: 2025-12-20
**问题范围**: 文本工具点击无响应 + 键盘无法唤起

---

## 一、问题综述

### 1.1 用户反馈的问题

| 序号 | 问题描述 | 影响范围 |
|------|---------|---------|
| 1 | 选择文本工具后，点击画布无响应 | 核心功能失效 |
| 2 | 文生图输入框点击后键盘不弹出 | 无法输入prompt |
| 3 | 图生图输入框点击后键盘不弹出 | 无法输入prompt |
| 4 | 项目名称输入框点击后键盘不弹出 | 无法编辑标题 |

### 1.2 根本原因汇总

经过深入分析，发现这些问题**同根同源**，核心问题是：

> **NativeCanvasView 在 window 级别添加的全局 UITapGestureRecognizer 拦截了所有触摸事件，导致 SwiftUI 组件（TextEditingView、TextEditor、TextField）的手势无法正确响应。**

具体原因链路：

```
用户点击画布/输入框
        ↓
window.globalTapGesture (UIKit) 优先捕获
        ↓
gestureRecognizer delegate 没有正确处理优先级
        ↓
SwiftUI 的 DragGesture / TextField 手势被阻断
        ↓
isEditing 无法变为 true / 键盘无法弹出
```

---

## 二、问题详细分析

### 2.1 文本工具点击无响应

#### 2.1.1 问题位置

| 文件 | 行号 | 关键代码 |
|------|------|---------|
| `NativeCanvasView.swift` | 1821-1844 | `setupGlobalTapObserver()` - 添加全局手势 |
| `NativeCanvasView.swift` | 1645-1676 | `UIGestureRecognizerDelegate` - 手势优先级配置 |
| `NativeCanvasView.swift` | 649-665 | `handleCanvasTap()` - 画布点击处理 |
| `TextEditingView.swift` | 54-65 | `DragGesture` - SwiftUI 手势（被阻断） |

#### 2.1.2 问题根因

1. **双重文字创建系统冲突**
   - UIKit 层: `NativeCanvasView.createTextAtLocation()` 自动创建默认文字
   - SwiftUI 层: `TextEditingView.DragGesture` 让用户输入文字
   - 两者竞争同一个点击事件

2. **手势优先级配置错误**
   ```swift
   // NativeCanvasView.swift:1645-1652
   func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
       if gestureRecognizer == canvasTapGesture || otherGestureRecognizer == canvasTapGesture {
           return false  // 禁止同时识别 - 导致 SwiftUI 手势被阻断
       }
       return true
   }
   ```

3. **全局手势覆盖范围过大**
   ```swift
   // NativeCanvasView.swift:1834-1838
   let globalTapGesture = UITapGestureRecognizer(...)
   window.addGestureRecognizer(globalTapGesture)  // window 级别，影响所有子视图
   ```

### 2.2 键盘无法唤起

#### 2.2.1 问题位置

| 文件 | 行号 | 组件 | 问题 |
|------|------|------|------|
| `TextToImageSheet.swift` | 100-114 | TextEditor | 缺少自动焦点激活 |
| `NativeEditorView.swift` | 960-970 | TextEditor (prompt) | 完全没有焦点管理 |
| `NativePublishSheetView.swift` | 1282 | TextField | NavigationStack 嵌套过深 |

#### 2.2.2 问题根因

1. **全局手势拦截输入法事件**
   - `globalTapGesture` 的 `cancelsTouchesInView = false` 不足以解决问题
   - delegate 方法没有为 `UITextField`/`UITextView` 的手势让路

2. **FocusState 没有自动激活**
   ```swift
   // TextToImageSheet.swift:100-114
   TextEditor(text: $prompt)
       .focused($isPromptFocused)  // 只是定义绑定
       // 缺少: .onAppear { isPromptFocused = true }
   ```

3. **NavigationStack 响应链过长**
   - Sheet 中嵌套 NavigationStack
   - 导致事件分发路径变长，容易被中途拦截

### 2.3 @Observable 与 UIViewRepresentable 兼容性问题

虽然之前的重构"修复"了工具切换 UI 更新问题，但存在隐患：

1. **updateUIView 调用时机不确定**
   - `@Observable` 的变化检测与 `UIViewRepresentable.updateUIView` 的触发不完全同步
   - 可能导致工具切换后 UIKit 层状态延迟更新

2. **计算属性打破观察链**
   ```swift
   // NativeCanvasView.swift:61-63
   var currentTool: CanvasTool {
       return stateManager?.currentTool ?? .select  // 计算属性，不触发观察
   }
   ```

---

## 三、修复方案

### 3.1 架构重构总览

```
Before:
┌─────────────────────────────────────────────────────────────┐
│ Window                                                       │
│  ├─ globalTapGesture (拦截所有点击)                          │
│  └─ NativeEditorView                                         │
│      ├─ NativeCanvasViewWrapper (UIViewRepresentable)        │
│      │   └─ NativeCanvasView                                 │
│      │       ├─ canvasTapGesture (与全局手势冲突)            │
│      │       └─ objectLayerView                              │
│      ├─ TextEditingView (SwiftUI, 手势被阻断)                │
│      └─ Sheets (TextEditor 键盘被阻断)                       │
└─────────────────────────────────────────────────────────────┘

After:
┌─────────────────────────────────────────────────────────────┐
│ Window (无全局手势)                                          │
│  └─ NativeEditorView                                         │
│      ├─ NativeCanvasViewWrapper                              │
│      │   └─ NativeCanvasView                                 │
│      │       ├─ 精确范围的 canvasTapGesture                  │
│      │       ├─ 工具特定的手势启用/禁用逻辑                  │
│      │       └─ 统一的文字创建系统 (移除 SwiftUI 层)         │
│      └─ Sheets (正确的 FocusState 管理)                      │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 核心修复任务

#### 任务 1：移除全局手势识别器

**文件**: `NativeCanvasView.swift`

**修改内容**:

1. **删除 `setupGlobalTapObserver()` 方法**（第1818-1844行）

2. **删除 `handleGlobalTap()` 方法**（第1875-1908行）

3. **删除 `cleanupGlobalTapObserver()` 中的全局手势清理**（第1949-1962行）

4. **修改 `setupViews()` 方法**，移除对 `setupGlobalTapObserver()` 的调用（约第235行）

**理由**: 全局手势的本意是让用户点击画布外时取消选中状态，但这个需求可以通过更精确的方式实现，不需要拦截整个 window 的触摸事件。

#### 任务 2：优化画布手势代理

**文件**: `NativeCanvasView.swift`

**修改 `UIGestureRecognizerDelegate` 扩展**（第1612-1677行）:

```swift
extension NativeCanvasView: UIGestureRecognizerDelegate {

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer == canvasTapGesture else { return true }

        let location = touch.location(in: objectLayerView)
        let hitView = objectLayerView.hitTest(location, with: nil)

        // 如果是文字工具，让 SwiftUI 层优先处理
        if currentTool == .text {
            // 仅当点击在已有的 SelectableTextView 上时才处理
            if hitView is SelectableTextView {
                return true
            }
            return false  // 其他区域让 SwiftUI 的 TextEditingView 处理
        }

        if isSelectableObject(hitView) {
            return false  // 让对象自己的手势处理
        }

        return true  // 空白区域由画布手势处理
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 与系统文本输入手势兼容
        let otherClassName = String(describing: type(of: otherGestureRecognizer))
        if otherClassName.contains("UITextField") ||
           otherClassName.contains("UITextView") ||
           otherClassName.contains("UITextInteraction") {
            return true  // 允许同时识别，不阻断输入焦点
        }

        if gestureRecognizer == canvasTapGesture || otherGestureRecognizer == canvasTapGesture {
            return false
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 让系统输入手势优先
        let otherClassName = String(describing: type(of: otherGestureRecognizer))
        if otherClassName.contains("UITextField") ||
           otherClassName.contains("UITextView") {
            return true  // canvasTapGesture 需要等待输入手势失败
        }
        return false
    }
}
```

#### 任务 3：统一文字创建系统（移除双重架构）

**决策**: 保留 UIKit 层的文字创建（`NativeCanvasView.createTextAtLocation`），移除 SwiftUI 层的 `TextEditingView`。

**理由**:
- UIKit 层已有完整的文字管理系统（SelectableTextView）
- 双重系统导致手势冲突
- 统一为 UIKit 可以避免 SwiftUI 与 UIKit 的手势竞争

**修改内容**:

**文件**: `NativeEditorView.swift`

1. **移除 TextEditingView 相关状态**（第466-468行）:
   ```swift
   // 删除以下状态
   @State private var isEditingText = false
   @State private var textPosition: CGPoint = .zero
   @State private var editingText: String = ""
   ```

2. **移除 TextEditingView 条件渲染**（第639-678行）:
   ```swift
   // 删除整个 if viewModel.stateManager.currentTool == .text { ... } 块
   ```

3. **移除 onToolChanged 中的文字工具特殊处理**（第817-829行）:
   ```swift
   // 删除以下代码
   if newTool == .text {
       isEditingText = false
       textPosition = .zero
       editingText = ""
   } else {
       if isEditingText {
           isEditingText = false
           textPosition = .zero
           editingText = ""
       }
   }
   ```

4. **移除 onChange(of:) 中的文字工具监听**（第857-869行）

**文件**: `NativeCanvasView.swift`

1. **改进 `handleCanvasTap` 方法**（第649-665行）:
   ```swift
   @objc private func handleCanvasTap(_ gesture: UITapGestureRecognizer) {
       let location = gesture.location(in: objectLayerView)
       let hitView = objectLayerView.hitTest(location, with: nil)

       // 文字工具：创建新文字并立即进入编辑模式
       if currentTool == .text {
           if hitView == objectLayerView || !isSelectableObject(hitView) {
               createTextAtLocationWithEditing(location)
               return
           }
       }

       // 其他情况：点击空白区域取消选中
       if hitView == objectLayerView || !isSelectableObject(hitView) {
           selectedNodeID = nil
       }
   }
   ```

2. **新增 `createTextAtLocationWithEditing` 方法**:
   ```swift
   private func createTextAtLocationWithEditing(_ location: CGPoint) {
       let contentLocation = convertToContentCoordinates(location)

       let fontSize = stateManager?.textFontSize ?? 24
       let textColor = stateManager?.textColor ?? "#000000"
       let fontName = stateManager?.textFontName ?? ".SF Pro Display"

       let text = TextLayerNode(
           position: contentLocation,
           text: "",  // 空文字，进入编辑模式
           fontSize: fontSize,
           color: textColor,
           fontName: fontName,
           zIndex: textLayerManager.getNextZIndex()
       )

       addText(text)
       selectedNodeID = text.id

       // 自动进入编辑模式
       if let textView = textViews[text.id] {
           DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
               textView.startEditing()
           }
       }
   }
   ```

3. **修改 SelectableTextView，公开 startEditing 方法**:

   **文件**: `SelectableTextView.swift`

   将 `private func startEditing()` 改为 `func startEditing()`（约第468行）

#### 任务 4：修复键盘唤起问题

**文件**: `TextToImageSheet.swift`

1. **添加自动焦点激活**（第100-117行）:
   ```swift
   private var promptEditor: some View {
       VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
           Text("提示词")
               .font(Theme.Fonts.caption)
               .foregroundStyle(Theme.Colors.secondaryText)

           TextEditor(text: $prompt)
               .focused($isPromptFocused)
               .frame(height: 120)
               .frame(minHeight: 120)
               .padding(Theme.Spacing.md)
               .scrollContentBackground(.hidden)
               .background(Theme.Colors.appBackground)
               .cornerRadius(Theme.Shapes.buttonCornerRadius)
               .overlay(
                   RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                       .stroke(
                           isPromptFocused ? Theme.Colors.brandBlue : Color.gray.opacity(0.2),
                           lineWidth: isPromptFocused ? 2 : 1
                       )
               )
               .animation(.easeInOut(duration: 0.2), value: isPromptFocused)
               .onAppear {
                   // 延迟激活焦点，确保视图完成布局
                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                       isPromptFocused = true
                   }
               }
       }
   }
   ```

**文件**: `NativeEditorView.swift`

1. **为控制面板的 TextEditor 添加焦点管理**（约第954-970行）:

   在 `NativeControlPanel` 结构体中添加:
   ```swift
   @FocusState private var isPromptFocused: Bool
   ```

   修改 promptSection:
   ```swift
   private var promptSection: some View {
       VStack(alignment: .leading, spacing: 8) {
           Label("生成描述", systemImage: "text.bubble")
               .font(.headline)

           TextEditor(text: $viewModel.prompt)
               .focused($isPromptFocused)
               .frame(height: 120)
               .padding(8)
               .background(Color.gray.opacity(0.05))
               .cornerRadius(8)
               .overlay(
                   RoundedRectangle(cornerRadius: 8)
                       .stroke(
                           isPromptFocused ? Color.blue : Color.gray.opacity(0.2),
                           lineWidth: isPromptFocused ? 2 : 1
                       )
               )
               .onTapGesture {
                   isPromptFocused = true
               }
       }
   }
   ```

**文件**: `NativePublishSheetView.swift`（约第1269-1300行）

1. **添加焦点管理**:
   ```swift
   private struct NativePublishSheetView: View {
       let asset: Asset
       @Binding var title: String
       let onPublish: () -> Void
       let onCancel: () -> Void

       @FocusState private var isTitleFocused: Bool

       var body: some View {
           NavigationStack {
               VStack(spacing: 20) {
                   // ...

                   TextField("添加标题", text: $title)
                       .focused($isTitleFocused)
                       .textFieldStyle(.roundedBorder)
                       .onAppear {
                           DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                               isTitleFocused = true
                           }
                       }

                   // ...
               }
           }
       }
   }
   ```

#### 任务 5：强化状态同步机制

**文件**: `NativeCanvasView.swift`

1. **添加工具变化的显式监听**（在 `setupViews()` 方法中，约第192-246行后添加）:
   ```swift
   private var toolChangeObserver: NSObjectProtocol?

   private func setupToolObserver() {
       toolChangeObserver = NotificationCenter.default.addObserver(
           forName: .toolChanged,
           object: nil,
           queue: .main
       ) { [weak self] notification in
           if let tool = notification.object as? CanvasTool {
               self?.updateForTool(tool)
           }
       }
   }
   ```

   在 `setupViews()` 末尾调用:
   ```swift
   setupToolObserver()
   ```

2. **在 deinit 中清理**:
   ```swift
   deinit {
       if let observer = toolChangeObserver {
           NotificationCenter.default.removeObserver(observer)
       }
       cleanupSelectionSyncObserver()
   }
   ```

#### 任务 6：优化取消选中的触发方式

移除全局手势后，需要替代方案来实现"点击画布外取消选中"的功能。

**方案**: 在 SwiftUI 层使用 `contentShape` 和手势：

**文件**: `NativeEditorView.swift`

在 `NativeCanvasContainer` 的 body 中（约第478-855行），将整个 ZStack 包装：

```swift
var body: some View {
    GeometryReader { proxy in
        ZStack {
            // 现有内容...
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            // 点击空白区域（非画布区域）时取消选中
            // 注意：画布内的点击由 NativeCanvasView 处理
            // 这里只处理工具栏等 UI 元素外的点击
        }
    }
    // 移除这个监听，改为在工具栏按钮的 action 中直接处理
    // .onChange(of: viewModel.stateManager.currentTool) { ... }
}
```

**更好的方案**: 在工具栏按钮点击时直接清除选中：

**文件**: `CanvasToolbar.swift`

修改 `ToolButton` 的 action（约第77-91行）:
```swift
ToolButton(
    tool: tool,
    isSelected: stateManager.currentTool == tool,
    action: {
        if tool == .image {
            onImageImport()
        } else if stateManager.currentTool != tool {
            // 切换工具时清除选中状态
            stateManager.clearSelection()

            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                stateManager.currentTool = tool
                onToolChanged?(tool)
            }
        }
    }
)
```

---

## 四、实施步骤

### 4.1 第一阶段：移除全局手势（最高优先级）

| 步骤 | 文件 | 操作 |
|------|------|------|
| 1-1 | `NativeCanvasView.swift` | 删除 `setupGlobalTapObserver()` 方法 |
| 1-2 | `NativeCanvasView.swift` | 删除 `handleGlobalTap()` 方法 |
| 1-3 | `NativeCanvasView.swift` | 删除 `cleanupGlobalTapObserver()` 中的全局手势代码 |
| 1-4 | `NativeCanvasView.swift` | 从 `setupViews()` 移除 `setupGlobalTapObserver()` 调用 |
| 1-5 | `NativeCanvasView.swift` | 删除 `AssociatedKeys` 结构体 |

**验证点**:
- [ ] 编译通过
- [ ] 其他工具（选择、平移、画笔等）功能正常

### 4.2 第二阶段：优化手势代理

| 步骤 | 文件 | 操作 |
|------|------|------|
| 2-1 | `NativeCanvasView.swift` | 修改 `gestureRecognizer(_:shouldReceive:)` |
| 2-2 | `NativeCanvasView.swift` | 修改 `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` |
| 2-3 | `NativeCanvasView.swift` | 修改 `gestureRecognizer(_:shouldRequireFailureOf:)` |

**验证点**:
- [ ] 画布上的对象可以正常选中、移动
- [ ] 键盘可以正常弹出（测试 Sheet 中的 TextEditor）

### 4.3 第三阶段：统一文字创建系统

| 步骤 | 文件 | 操作 |
|------|------|------|
| 3-1 | `NativeEditorView.swift` | 删除 `isEditingText`、`textPosition`、`editingText` 状态 |
| 3-2 | `NativeEditorView.swift` | 删除 TextEditingView 条件渲染块 |
| 3-3 | `NativeEditorView.swift` | 删除 onToolChanged 中的文字工具处理代码 |
| 3-4 | `NativeEditorView.swift` | 删除 onChange 中的文字工具监听 |
| 3-5 | `NativeCanvasView.swift` | 修改 `handleCanvasTap()` 方法 |
| 3-6 | `NativeCanvasView.swift` | 新增 `createTextAtLocationWithEditing()` 方法 |
| 3-7 | `SelectableTextView.swift` | 公开 `startEditing()` 方法 |

**验证点**:
- [ ] 选择文字工具后，点击画布可创建新文字
- [ ] 新创建的文字自动进入编辑模式，可输入内容
- [ ] 双击已有文字可编辑

### 4.4 第四阶段：修复键盘唤起

| 步骤 | 文件 | 操作 |
|------|------|------|
| 4-1 | `TextToImageSheet.swift` | 添加 `.onAppear` 自动激活焦点 |
| 4-2 | `NativeEditorView.swift` | 为 NativeControlPanel 添加 FocusState |
| 4-3 | `NativePublishSheetView.swift` | 添加焦点管理 |

**验证点**:
- [ ] 打开文生图 Sheet 后，TextEditor 自动获焦，键盘弹出
- [ ] 点击控制面板的 prompt 输入框，键盘弹出
- [ ] 发布弹窗的标题输入框键盘可弹出

### 4.5 第五阶段：强化状态同步

| 步骤 | 文件 | 操作 |
|------|------|------|
| 5-1 | `NativeCanvasView.swift` | 添加 `toolChangeObserver` 属性 |
| 5-2 | `NativeCanvasView.swift` | 添加 `setupToolObserver()` 方法 |
| 5-3 | `NativeCanvasView.swift` | 在 `setupViews()` 中调用 |
| 5-4 | `NativeCanvasView.swift` | 在 `deinit` 中清理 observer |

**验证点**:
- [ ] 快速切换工具，UIKit 层状态同步正常
- [ ] 工具切换后画布手势行为正确

### 4.6 第六阶段：优化取消选中

| 步骤 | 文件 | 操作 |
|------|------|------|
| 6-1 | `CanvasToolbar.swift` | 在工具切换时调用 `clearSelection()` |

**验证点**:
- [ ] 选中对象后，切换工具会取消选中
- [ ] 点击工具栏按钮不会影响键盘状态

---

## 五、代码变更清单

### 5.1 需要删除的代码

| 文件 | 删除内容 |
|------|---------|
| `NativeCanvasView.swift` | `setupGlobalTapObserver()` 方法（约40行） |
| `NativeCanvasView.swift` | `handleGlobalTap()` 方法（约35行） |
| `NativeCanvasView.swift` | `cleanupGlobalTapObserver()` 中的全局手势代码（约15行） |
| `NativeCanvasView.swift` | `AssociatedKeys` 结构体（约3行） |
| `NativeEditorView.swift` | TextEditingView 相关状态（约3行） |
| `NativeEditorView.swift` | TextEditingView 条件渲染块（约40行） |
| `NativeEditorView.swift` | onToolChanged 中文字工具处理（约12行） |
| `NativeEditorView.swift` | onChange 中文字工具监听（约12行） |

### 5.2 需要修改的代码

| 文件 | 修改内容 |
|------|---------|
| `NativeCanvasView.swift` | `UIGestureRecognizerDelegate` 扩展（约60行改动） |
| `NativeCanvasView.swift` | `handleCanvasTap()` 方法（约20行改动） |
| `TextToImageSheet.swift` | promptEditor（添加约5行） |
| `NativeEditorView.swift` | NativeControlPanel.promptSection（约15行改动） |
| `NativePublishSheetView.swift` | TextField（约10行改动） |
| `CanvasToolbar.swift` | ToolButton action（约5行改动） |

### 5.3 需要新增的代码

| 文件 | 新增内容 |
|------|---------|
| `NativeCanvasView.swift` | `createTextAtLocationWithEditing()` 方法（约25行） |
| `NativeCanvasView.swift` | `toolChangeObserver` 属性和 `setupToolObserver()` 方法（约15行） |
| `SelectableTextView.swift` | 公开 `startEditing()` 方法（改访问级别，0行新增） |

---

## 六、测试验收清单

### 6.1 文本工具测试

- [ ] 选择文本工具，工具栏按钮高亮
- [ ] 点击画布空白区域，创建新文字
- [ ] 新文字自动进入编辑模式，光标闪烁
- [ ] 可正常输入中英文
- [ ] 按回车完成编辑
- [ ] 双击已有文字可重新编辑
- [ ] 选择其他工具后再切换回文字工具，功能正常

### 6.2 键盘测试

- [ ] 打开文生图 Sheet，TextEditor 自动获焦
- [ ] 键盘自动弹出
- [ ] 输入内容正常
- [ ] 点击控制面板 prompt 输入框，键盘弹出
- [ ] 发布弹窗标题输入框键盘弹出
- [ ] 关闭 Sheet 后键盘消失

### 6.3 工具切换测试

- [ ] 快速连续点击不同工具，UI 响应正常
- [ ] 选中对象后切换工具，选中状态清除
- [ ] 画笔工具可正常绘图
- [ ] 橡皮擦工具可正常擦除
- [ ] 形状工具可正常创建形状
- [ ] 箭头工具可正常创建箭头

### 6.4 回归测试

- [ ] 图片导入功能正常
- [ ] 图片缩放、移动、旋转正常
- [ ] 撤销/恢复功能正常
- [ ] Magic Frame 功能正常
- [ ] 图生图/文生图流程正常
- [ ] 项目保存/加载正常

---

## 七、风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|-------|------|---------|
| 移除全局手势后点击外部无法取消选中 | 低 | 低 | 已在工具切换时清除选中 |
| SelectableTextView.startEditing 调用时机不当 | 中 | 中 | 使用 DispatchQueue.main.asyncAfter 延迟 |
| 焦点激活在某些设备上延迟不够 | 低 | 低 | 可根据实际调整延迟时间 |
| 手势代理修改影响其他功能 | 中 | 高 | 充分测试各工具功能 |

---

## 八、附录：日志添加建议

为便于调试，建议在以下位置添加日志：

```swift
// NativeCanvasView.swift - handleCanvasTap
@objc private func handleCanvasTap(_ gesture: UITapGestureRecognizer) {
    print("[DEBUG] handleCanvasTap - currentTool: \(currentTool)")
    // ...
}

// NativeCanvasView.swift - gestureRecognizer delegate
func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                       shouldReceive touch: UITouch) -> Bool {
    let result = // 计算结果
    print("[DEBUG] shouldReceive - gesture: \(gestureRecognizer), result: \(result)")
    return result
}

// SelectableTextView.swift - startEditing
func startEditing() {
    print("[DEBUG] SelectableTextView.startEditing - id: \(textNode.id)")
    // ...
}
```

---

## 九、总结

本方案通过以下核心改动解决问题：

1. **移除全局手势** - 根除事件拦截的源头
2. **优化手势代理** - 正确处理与输入框手势的优先级
3. **统一文字创建** - 消除 SwiftUI 与 UIKit 的双重系统冲突
4. **添加焦点管理** - 确保输入框正确获取焦点
5. **强化状态同步** - 使用 NotificationCenter 保证工具状态同步

预计改动量约 200 行（删除约 120 行，修改约 60 行，新增约 40 行），风险可控，可在半天内完成实施和测试。
