# MindCanvas 文本工具与键盘问题终极修复方案 V2

**版本**: v2.0
**日期**: 2025-12-20
**状态**: 待实施
**前置**: v1方案已实施但未能解决问题，本方案从根本上重构架构

---

## 一、问题诊断总结

### 1.1 V1方案失败原因分析

V1方案虽然识别了问题方向，但存在以下致命缺陷：

| 缺陷 | 描述 | 后果 |
|------|------|------|
| **架构层面** | 文字视图仍在 objectLayerView 内，受 PKCanvasView 手势影响 | 手势冲突未根除 |
| **布局层面** | TextLayerNode.bounds 返回 width=0，约束计算崩溃 | SelectableTextView:674 强制解包崩溃 |
| **时序层面** | becomeFirstResponder() 在视图布局完成前调用 | 键盘无法唤起 |
| **焦点层面** | FocusState 0.3s 延迟不足 | Sheet中键盘不弹出 |

### 1.2 真正的根本原因

通过深度调试日志和代码分析，确定了三个核心问题：

#### 问题 #1: 文字视图架构错误

当前架构：
```
NativeCanvasView
├── pencilCanvas (PKCanvasView)
├── overlayContainerView
│   └── objectLayerView
│       ├── arrowViews
│       ├── shapeViews
│       ├── imageViews
│       └── textViews ← 问题所在：与其他对象共用容器
```

**问题**：
- textViews 与箭头、形状、图片共用 objectLayerView
- 当工具切换时，objectLayerView.isUserInteractionEnabled 被整体控制
- UITextField 的触摸事件被 objectLayerView 的父视图层层拦截
- PKCanvasView 的 scrollView 行为干扰 UITextField 的焦点获取

#### 问题 #2: TextLayerNode.bounds 返回无效尺寸

```swift
// 当 text = "" 时
var bounds: CGRect {
    let nsString = text as NSString
    let size = nsString.boundingRect(...).size  // size.width = 0!
    return CGRect(x: position.x - size.width / 2, ...)
    // 返回 width = 0 的 CGRect
}
```

**后果链**：
1. SelectableTextView.frame = (x, y, 0, height)
2. setupEditingInterface() 中的约束依赖 bounds
3. centerXAnchor.constraint(equalTo: centerXAnchor) 基于 width=0 的视图
4. 强制解包某个可选值时崩溃

#### 问题 #3: UITextField 焦点获取失败

```swift
// SelectableTextView.swift:668-669
let success = editingTextField.becomeFirstResponder()
// success = false 的可能原因：
// 1. 视图尚未加入 window
// 2. 父视图链中某个 isUserInteractionEnabled = false
// 3. PKCanvasView 的 scrollView 抢占了第一响应者
// 4. 布局尚未完成，Auto Layout 约束无效
```

---

## 二、终极修复方案

### 2.1 核心设计思路

**原则**: 将文字视图完全独立于 PKCanvasView 的视图层级

**新架构**:
```
NativeCanvasView
├── pencilCanvas (PKCanvasView)
├── overlayContainerView
│   └── objectLayerView
│       ├── arrowViews
│       ├── shapeViews
│       └── imageViews
└── textOverlayView ← 新增：独立的文字覆盖层
    └── textViews (SelectableTextView[])
```

**设计优势**:
1. 文字视图脱离 PKCanvasView 的 scrollView 事件传递链
2. textOverlayView 可以独立控制手势和交互
3. UITextField 不再受到 objectLayerView 的 isUserInteractionEnabled 影响
4. 坐标同步逻辑集中管理，避免多层 transform 叠加

### 2.2 修复任务清单

| 任务 | 优先级 | 影响文件 | 改动量 |
|------|-------|---------|-------|
| A. 创建独立文字覆盖层 | P0 | NativeCanvasView.swift | ~80行 |
| B. 修复 TextLayerNode.bounds | P0 | TextLayerNode.swift | ~15行 |
| C. 重构 SelectableTextView 编辑流程 | P0 | SelectableTextView.swift | ~60行 |
| D. 修复键盘焦点时序 | P1 | SelectableTextView.swift, TextToImageSheet.swift | ~30行 |
| E. 清理冗余代码 | P2 | 多文件 | ~50行删除 |

---

## 三、详细实施步骤

### 任务 A: 创建独立文字覆盖层

**文件**: `NativeCanvasView.swift`

#### A.1 新增属性声明

在属性区域（约第39-42行之后）添加：

```swift
/// Layer 3: 文字覆盖层 - 完全独立于 objectLayerView
private let textOverlayView = UIView()
```

#### A.2 修改 setupViews() 方法

在 `setupViews()` 方法中（约第194-249行），添加 textOverlayView 的配置：

```swift
private func setupViews() {
    backgroundColor = .systemGray6

    // ... 现有的 pencilCanvas 配置代码 ...

    // ... 现有的 overlayContainerView 配置代码 ...

    // ... 现有的 objectLayerView 配置代码 ...

    // 新增：配置文字覆盖层
    textOverlayView.backgroundColor = .clear
    textOverlayView.isUserInteractionEnabled = true
    textOverlayView.clipsToBounds = false
    textOverlayView.isOpaque = false
    textOverlayView.frame = CGRect(origin: .zero, size: canvasSize)

    // 添加视图层级
    addSubview(pencilCanvas)
    addSubview(overlayContainerView)
    overlayContainerView.addSubview(objectLayerView)
    addSubview(textOverlayView)  // 新增：作为最顶层

    // ... 其余代码 ...
}
```

#### A.3 修改 setupConstraints() 方法

在 `setupConstraints()` 方法中（约第251-268行），添加 textOverlayView 的约束：

```swift
private func setupConstraints() {
    pencilCanvas.translatesAutoresizingMaskIntoConstraints = false
    overlayContainerView.translatesAutoresizingMaskIntoConstraints = false
    textOverlayView.translatesAutoresizingMaskIntoConstraints = false  // 新增

    NSLayoutConstraint.activate([
        // pencilCanvas 约束保持不变
        pencilCanvas.topAnchor.constraint(equalTo: topAnchor),
        pencilCanvas.leadingAnchor.constraint(equalTo: leadingAnchor),
        pencilCanvas.trailingAnchor.constraint(equalTo: trailingAnchor),
        pencilCanvas.bottomAnchor.constraint(equalTo: bottomAnchor),

        // overlayContainerView 约束保持不变
        overlayContainerView.topAnchor.constraint(equalTo: topAnchor),
        overlayContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
        overlayContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        overlayContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

        // 新增：textOverlayView 约束
        textOverlayView.topAnchor.constraint(equalTo: topAnchor),
        textOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
        textOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
        textOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
}
```

#### A.4 修改 layoutSubviews() 方法

修改 `layoutSubviews()` 方法（约第270-276行）：

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    objectLayerView.frame = CGRect(origin: .zero, size: canvasSize)
    textOverlayView.frame = CGRect(origin: .zero, size: canvasSize)  // 新增
    syncOverlayTransform()
}
```

#### A.5 修改 syncOverlayTransform() 方法

修改 `syncOverlayTransform()` 方法（约第279-291行）：

```swift
private func syncOverlayTransform() {
    let offset = pencilCanvas.contentOffset
    let scale = pencilCanvas.zoomScale

    // objectLayerView 变换（保持不变）
    objectLayerView.transform = CGAffineTransform(scaleX: scale, y: scale)
    objectLayerView.frame.origin = CGPoint(x: -offset.x, y: -offset.y)

    // 新增：textOverlayView 变换（与 objectLayerView 同步）
    textOverlayView.transform = CGAffineTransform(scaleX: scale, y: scale)
    textOverlayView.frame.origin = CGPoint(x: -offset.x, y: -offset.y)
}
```

#### A.6 修改 createTextView(for:) 方法

修改 `createTextView(for:)` 方法（约第1741-1849行），将文字视图添加到 textOverlayView：

找到这一行：
```swift
objectLayerView.addSubview(textView)
```

替换为：
```swift
textOverlayView.addSubview(textView)
```

#### A.7 修改 updateForTool() 方法中的文字工具处理

在 `updateForTool()` 方法的 `.text` case 中（约第1068-1106行），添加 textOverlayView 的控制：

```swift
case .arrow, .rectangle, .text, .annotation:
    // ... 现有代码 ...

    // 新增：文字工具时确保 textOverlayView 可交互
    if tool == .text {
        textOverlayView.isUserInteractionEnabled = true

        for (_, textView) in textViews {
            textView.enableTextGestures()
        }
    }
```

#### A.8 新增：确保其他工具时 textOverlayView 仍可响应

在 `updateForTool()` 方法的每个 case 开头，根据需要设置 textOverlayView：

```swift
case .select:
    // ... 现有代码 ...
    textOverlayView.isUserInteractionEnabled = true  // 选择时可交互
    for textView in textViews.values {
        textView.enableTextGestures()
    }

case .pan:
    // ... 现有代码 ...
    textOverlayView.isUserInteractionEnabled = false  // 平移时不可交互

case .pen, .eraser:
    // ... 现有代码 ...
    textOverlayView.isUserInteractionEnabled = false  // 绘图时不可交互

case .image:
    // ... 现有代码 ...
    textOverlayView.isUserInteractionEnabled = true  // 图片工具时可交互

case .arrow, .rectangle, .annotation:
    // ... 现有代码 ...
    textOverlayView.isUserInteractionEnabled = false  // 创建形状时不可交互

case .text:
    // ... 现有代码 ...
    textOverlayView.isUserInteractionEnabled = true  // 文字工具必须可交互
```

---

### 任务 B: 修复 TextLayerNode.bounds

**文件**: `TextLayerNode.swift`

找到 `bounds` 计算属性（搜索 `var bounds: CGRect`），修改为：

```swift
var bounds: CGRect {
    let nsString = (text.isEmpty ? "文字" : text) as NSString  // 修改：空文字时使用占位符计算
    let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont(name: fontName, size: fontSize * scale)
            ?? UIFont.systemFont(ofSize: fontSize * scale)
    ]

    let size = nsString.boundingRect(
        with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes,
        context: nil
    ).size

    // 新增：确保最小尺寸
    let minWidth: CGFloat = 60   // 最小宽度，确保可点击
    let minHeight: CGFloat = 30  // 最小高度
    let finalWidth = max(size.width, minWidth)
    let finalHeight = max(size.height, minHeight)

    return CGRect(
        x: position.x - finalWidth / 2,
        y: position.y - finalHeight / 2,
        width: finalWidth,
        height: finalHeight
    )
}
```

---

### 任务 C: 重构 SelectableTextView 编辑流程

**文件**: `SelectableTextView.swift`

#### C.1 修改 startEditing() 方法为 public

找到 `startEditing()` 方法（约第538行），修改访问级别：

```swift
// 修改前
private func startEditing() {

// 修改后
func startEditing() {
```

#### C.2 重写 setupEditingInterface() 方法

找到 `setupEditingInterface()` 方法（约第609-678行），**完全替换**为：

```swift
private func setupEditingInterface() {
    // 安全检查：确保 bounds 有效
    guard bounds.width >= 10 && bounds.height >= 10 else {
        print("[SelectableTextView] setupEditingInterface 失败：bounds 无效 \(bounds)")
        isEditing = false
        return
    }

    // 安全检查：确保视图在 window 中
    guard window != nil else {
        print("[SelectableTextView] setupEditingInterface 失败：视图不在 window 中")
        isEditing = false
        return
    }

    // 创建半透明遮罩层（使用 frame 而非 Auto Layout）
    let overlayFrame = bounds.insetBy(dx: -8, dy: -8)
    editingOverlay = UIView(frame: overlayFrame)
    editingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.05)
    editingOverlay.layer.cornerRadius = 8
    editingOverlay.layer.borderWidth = 2
    editingOverlay.layer.borderColor = UIColor.systemBlue.cgColor
    addSubview(editingOverlay)

    // 创建文本输入框（使用 frame 而非 Auto Layout）
    let textFieldHeight = max(textNode.fontSize + 16, 44)
    let textFieldWidth = max(bounds.width + 24, 120)
    let textFieldFrame = CGRect(
        x: (bounds.width - textFieldWidth) / 2,
        y: (bounds.height - textFieldHeight) / 2,
        width: textFieldWidth,
        height: textFieldHeight
    )

    editingTextField = UITextField(frame: textFieldFrame)
    editingTextField.text = textNode.text
    editingTextField.font = UIFont(name: textNode.fontName, size: textNode.fontSize)
        ?? UIFont.systemFont(ofSize: textNode.fontSize)
    editingTextField.textColor = UIColor_fromHex(textNode.color)
    editingTextField.textAlignment = .center
    editingTextField.backgroundColor = UIColor.white.withAlphaComponent(0.98)
    editingTextField.layer.cornerRadius = 6
    editingTextField.layer.borderWidth = 1
    editingTextField.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
    editingTextField.delegate = self

    // 设置阴影
    editingTextField.layer.shadowColor = UIColor.black.cgColor
    editingTextField.layer.shadowOffset = CGSize(width: 0, height: 2)
    editingTextField.layer.shadowOpacity = 0.15
    editingTextField.layer.shadowRadius = 6
    editingTextField.layer.masksToBounds = false

    // 添加内边距
    let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: textFieldHeight))
    editingTextField.leftView = paddingView
    editingTextField.leftViewMode = .always
    editingTextField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: textFieldHeight))
    editingTextField.rightViewMode = .always

    addSubview(editingTextField)

    // 关键：延迟激活键盘，确保布局完成
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
        guard let self = self, self.isEditing else { return }
        guard let textField = self.editingTextField else { return }

        // 再次检查视图状态
        guard textField.window != nil else {
            print("[SelectableTextView] becomeFirstResponder 失败：textField 不在 window 中")
            return
        }

        let success = textField.becomeFirstResponder()
        print("[SelectableTextView] becomeFirstResponder 结果: \(success)")

        if success {
            // 选中全部文字
            textField.selectAll(nil)
        } else {
            // 焦点获取失败，尝试恢复
            print("[SelectableTextView] 尝试延迟重试 becomeFirstResponder")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.editingTextField?.becomeFirstResponder()
            }
        }
    }
}
```

#### C.3 修改 point(inside:with:) 方法

找到 `point(inside:with:)` 方法（约第327-376行），修改编辑状态的处理：

```swift
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // 1. 编辑状态：扩大点击区域，包含 UITextField
    if isEditing {
        let expandedBounds = bounds.insetBy(dx: -20, dy: -20)
        return expandedBounds.contains(point)
    }

    // 2. 在原始 bounds 内
    if bounds.contains(point) {
        return true
    }

    // 3. 选中状态：检查控制点区域
    guard isSelected else {
        return false
    }

    let controlPointHitRadius: CGFloat = 22

    // 检查旋转手柄
    let rotationPos = TextControlHandle.rotation.position(in: bounds, rotationOffset: rotationHandleOffset)
    if distance(from: point, to: rotationPos) <= controlPointHitRadius {
        return true
    }

    // 检查角点
    let corners: [TextControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
    for corner in corners {
        let cornerPos = corner.position(in: bounds)
        if distance(from: point, to: cornerPos) <= controlPointHitRadius {
            return true
        }
    }

    return false
}
```

---

### 任务 D: 修复键盘焦点时序

#### D.1 修改 TextToImageSheet.swift

**文件**: `TextToImageSheet.swift`

找到 TextEditor 的 `.onAppear` 修饰符（约第136-144行），修改延迟时间：

```swift
.onAppear {
    // 延迟激活焦点，确保 Sheet 动画和布局完成
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {  // 从 0.3 增加到 0.6
        isPromptFocused = true
    }
}
```

#### D.2 修改 NativeCanvasView 中的 createTextAtLocationWithEditing

**文件**: `NativeCanvasView.swift`

找到 `createTextAtLocationWithEditing()` 方法（约第809-883行），修改延迟时间：

```swift
// 自动进入编辑模式
if let textView = textViews[text.id] {
    // 确保视图完成布局后再启动编辑
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {  // 从 0.1 增加到 0.2
        // 再次验证视图状态
        guard textView.superview != nil else {
            print("[NativeCanvasView] textView 已被移除，跳过编辑")
            return
        }
        textView.startEditing()
    }
}
```

---

### 任务 E: 清理冗余代码

#### E.1 移除 handleCanvasTap 中的冗余日志

**文件**: `NativeCanvasView.swift`

找到 `handleCanvasTap()` 方法（约第651-762行），移除所有 `print` 语句，仅保留核心逻辑：

```swift
@objc private func handleCanvasTap(_ gesture: UITapGestureRecognizer) {
    let location = gesture.location(in: objectLayerView)
    let hitView = objectLayerView.hitTest(location, with: nil)

    // 文字工具模式：点击空白区域创建文字
    if currentTool == .text {
        // 检查是否点击在 textOverlayView 中的已有文字上
        let textLocation = gesture.location(in: textOverlayView)
        let textHitView = textOverlayView.hitTest(textLocation, with: nil)

        if textHitView == textOverlayView || !(textHitView is SelectableTextView) {
            createTextAtLocationWithEditing(textLocation)
            return
        }
    }

    // 其他情况：点击空白区域取消选中
    if hitView == objectLayerView || !isSelectableObject(hitView) {
        selectedNodeID = nil
    }
}
```

#### E.2 移除 SelectableTextView 中的冗余日志

**文件**: `SelectableTextView.swift`

移除所有调试用的 `print` 语句，仅保留关键错误日志。

---

## 四、手势代理优化

**文件**: `NativeCanvasView.swift`

找到 `UIGestureRecognizerDelegate` 扩展（约第1867-2046行），进行以下优化：

### 4.1 修改 shouldReceive touch

```swift
func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    guard gestureRecognizer == canvasTapGesture else { return true }

    // 文字工具时，检查触摸是否在 textOverlayView 的文字视图上
    if currentTool == .text {
        let textLocation = touch.location(in: textOverlayView)
        let textHitView = textOverlayView.hitTest(textLocation, with: nil)

        // 如果点击在已有的 SelectableTextView 上，让其自己处理
        if textHitView is SelectableTextView {
            return false
        }
        // 其他区域由 canvasTapGesture 处理（创建新文字）
        return true
    }

    // 其他工具的处理保持不变
    let location = touch.location(in: objectLayerView)
    let hitView = objectLayerView.hitTest(location, with: nil)

    if isSelectableObject(hitView) {
        return false
    }

    return true
}
```

### 4.2 修改 shouldRecognizeSimultaneouslyWith

```swift
func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                       shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    // 与 UITextField 的手势兼容
    if let view = otherGestureRecognizer.view, view is UITextField {
        return true
    }

    // 与系统文本交互手势兼容
    let otherClassName = String(describing: type(of: otherGestureRecognizer))
    if otherClassName.contains("UITextInteraction") ||
       otherClassName.contains("UITextSelectionInteraction") {
        return true
    }

    if gestureRecognizer == canvasTapGesture || otherGestureRecognizer == canvasTapGesture {
        return false
    }

    return true
}
```

### 4.3 修改 shouldRequireFailureOf

```swift
func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                       shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    // UITextField 的手势优先
    if let view = otherGestureRecognizer.view, view is UITextField {
        return true
    }

    return false
}
```

---

## 五、验证清单

### 5.1 编译验证

- [ ] 项目编译无错误
- [ ] 项目编译无警告（忽略第三方库警告）

### 5.2 文字工具测试

| 测试项 | 操作 | 预期结果 |
|-------|------|---------|
| 创建文字 | 选择文字工具 → 点击画布空白 | 出现文字输入框，键盘弹出 |
| 输入文字 | 在输入框中输入 "测试文字" | 文字正常显示 |
| 完成编辑 | 按键盘回车 | 输入框消失，文字对象创建成功 |
| 再次编辑 | 双击已创建的文字 | 输入框出现，显示当前文字 |
| 移动文字 | 单击选中 → 拖拽 | 文字跟随移动 |
| 缩放文字 | 选中 → 拖拽角点 | 文字按比例缩放 |
| 旋转文字 | 选中 → 拖拽旋转手柄 | 文字围绕中心旋转 |

### 5.3 键盘测试

| 测试项 | 操作 | 预期结果 |
|-------|------|---------|
| 文生图键盘 | 打开文生图 Sheet | TextEditor 自动获焦，键盘弹出 |
| 输入内容 | 输入 prompt 文字 | 正常输入，无卡顿 |
| 关闭键盘 | 点击关闭按钮或下滑 | 键盘收起，Sheet 关闭 |
| 项目名称 | 发布时编辑标题 | 输入框获焦，键盘弹出 |

### 5.4 工具切换测试

| 测试项 | 操作 | 预期结果 |
|-------|------|---------|
| 选择→文字 | 点击文字工具 | 工具栏高亮，画布可点击创建文字 |
| 文字→画笔 | 点击画笔工具 | 可正常绘图，文字对象保持显示 |
| 文字→选择 | 点击选择工具 | 可选中已创建的文字 |
| 快速切换 | 连续快速点击不同工具 | UI 响应正常，无卡顿 |

### 5.5 回归测试

| 功能 | 状态 |
|------|------|
| 图片导入 | [ ] 正常 |
| 图片变换 | [ ] 正常 |
| 画笔绘图 | [ ] 正常 |
| 橡皮擦除 | [ ] 正常 |
| 箭头创建 | [ ] 正常 |
| 形状创建 | [ ] 正常 |
| 撤销/恢复 | [ ] 正常 |
| 项目保存 | [ ] 正常 |
| 项目加载 | [ ] 正常 |

---

## 六、实施顺序

建议按以下顺序实施，每步完成后验证：

1. **任务 B**: 修复 TextLayerNode.bounds（最简单，防止崩溃）
2. **任务 C**: 重构 SelectableTextView 编辑流程
3. **任务 A**: 创建独立文字覆盖层（核心架构改动）
4. **任务 D**: 修复键盘焦点时序
5. **第四节**: 手势代理优化
6. **任务 E**: 清理冗余代码
7. **全面测试**: 按验证清单逐项验证

---

## 七、风险控制

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|-------|------|---------|
| textOverlayView 坐标同步偏移 | 中 | 中 | syncOverlayTransform() 已统一处理 |
| 旧文字对象加载位置错误 | 低 | 中 | 加载时迁移到 textOverlayView |
| 手势优先级仍有冲突 | 低 | 低 | 进一步调整 delegate 方法 |
| 键盘延迟时间不足 | 低 | 低 | 可根据实际调整延迟值 |

---

## 八、附录

### 8.1 关键文件行号索引

| 文件 | 关键位置 | 行号范围 |
|------|---------|---------|
| NativeCanvasView.swift | 属性声明区 | 36-120 |
| NativeCanvasView.swift | setupViews() | 194-249 |
| NativeCanvasView.swift | setupConstraints() | 251-268 |
| NativeCanvasView.swift | layoutSubviews() | 270-276 |
| NativeCanvasView.swift | syncOverlayTransform() | 279-291 |
| NativeCanvasView.swift | handleCanvasTap() | 651-762 |
| NativeCanvasView.swift | createTextAtLocationWithEditing() | 809-883 |
| NativeCanvasView.swift | updateForTool() | 970-1107 |
| NativeCanvasView.swift | createTextView() | 1741-1849 |
| NativeCanvasView.swift | UIGestureRecognizerDelegate | 1867-2046 |
| SelectableTextView.swift | point(inside:with:) | 327-376 |
| SelectableTextView.swift | startEditing() | 538-566 |
| SelectableTextView.swift | setupEditingInterface() | 609-678 |
| TextLayerNode.swift | bounds 属性 | 搜索 "var bounds: CGRect" |
| TextToImageSheet.swift | TextEditor onAppear | 136-144 |

### 8.2 核心改动量估算

| 任务 | 新增行数 | 删除行数 | 修改行数 |
|------|---------|---------|---------|
| A | 30 | 5 | 15 |
| B | 15 | 5 | 0 |
| C | 60 | 70 | 10 |
| D | 5 | 0 | 5 |
| E | 0 | 50 | 0 |
| 手势优化 | 20 | 30 | 10 |
| **总计** | **130** | **160** | **40** |

**净改动**: 约 130 + 40 - 160 = **+10 行**（代码量基本不变，但质量大幅提升）

---

## 九、总结

本 V2 方案的核心改进：

1. **架构重构**: 将文字视图从 objectLayerView 中独立出来，创建专用的 textOverlayView
2. **防崩溃**: 修复 TextLayerNode.bounds 返回无效尺寸的问题
3. **时序修正**: 延迟 becomeFirstResponder() 调用，确保视图布局完成
4. **手势隔离**: 文字视图不再受 PKCanvasView 和 objectLayerView 的手势干扰
5. **代码清理**: 移除调试日志，简化逻辑

相比 V1 方案，V2 方案从架构层面解决问题，而不是试图在复杂的视图层级中修补手势冲突。这是一个更彻底、更可维护的解决方案。
