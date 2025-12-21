# MindCanvas 文本工具终极修复方案 V3

**版本**: v3.0
**日期**: 2025-12-20
**状态**: 待实施
**作者**: Claude Opus 4.5

---

## 一、执行摘要

### 1.1 当前问题

1. **画布无编辑光标显示**: 点击画布后，SelectableTextView创建成功，但UITextField的光标不可见
2. **输入文字后不显示**: 用户输入文字并按回车后，文字内容无法在画布上显示
3. **CATextLayer渲染失败**: 即使数据保存正确，视觉渲染层面存在问题

### 1.2 根本原因（一句话总结）

**当前架构使用CATextLayer进行文字渲染，存在时序问题和渲染机制限制。核心问题是CATextLayer在frame尚未正确设置或缩放环境下无法正确渲染文字内容。**

### 1.3 解决方案（一句话总结）

**抛弃CATextLayer方案，使用UILabel直接渲染文字，同时重构文字编辑流程，采用UITextView替代UITextField以获得更好的编辑体验。**

---

## 二、问题深度分析

### 2.1 从第一性原理出发

要在iOS画布上实现可编辑文字，本质上需要解决三个问题：

1. **创建时机**：用户点击画布 → 创建文字节点 → 显示编辑器
2. **编辑过程**：键盘弹出 → 用户输入 → 实时预览
3. **渲染显示**：编辑完成 → 渲染文字到画布 → 支持选择/变换

### 2.2 当前实现的问题链

```
用户点击画布
    ↓
handleCanvasTap() 捕获点击 [正常]
    ↓
createTextAtLocationWithEditing() 创建 TextLayerNode [正常]
    ↓
addText() → textLayerManager.addText() [正常]
    ↓
createTextView() 创建 SelectableTextView [正常]
    ↓
textOverlayView.addSubview(textView) [正常]
    ↓
startEditing() 被调用 [正常]
    ↓
setupEditingInterface() 创建 UITextField [正常]
    ↓
becomeFirstResponder() [可能失败 - 问题点1]
    ↓
用户输入文字
    ↓
textFieldShouldReturn() → finishEditing() [正常]
    ↓
textNode.updated(text: newText) [正常]
    ↓
updateFromNode() 更新 CATextLayer [失败 - 问题点2]
    ↓
textLayer.string = textNode.text [设置成功]
    ↓
CATextLayer渲染 [失败 - 问题点3]
```

### 2.3 三个问题点的详细分析

#### 问题点1：becomeFirstResponder可能失败

**位置**: SelectableTextView.swift:691

**现象**: `becomeFirstResponder()` 返回 `false`，键盘不弹出

**根因分析**:
1. UITextField在添加到视图后0.15秒才尝试获取焦点
2. 此时视图层级可能尚未完全加入window
3. textOverlayView虽然isUserInteractionEnabled=true，但其父视图NativeCanvasView可能存在手势冲突

**验证日志**:
```swift
print("[SelectableTextView] becomeFirstResponder 结果: \(success)")
// 需要添加更多诊断日志
```

#### 问题点2：updateFromNode更新CATextLayer

**位置**: SelectableTextView.swift:205-249

**现象**: `textLayer.string = textNode.text` 设置成功，但视觉上不显示

**根因分析**:
1. CATextLayer的frame基于`textNode.bounds`计算
2. `textNode.bounds`依赖于文字内容计算尺寸
3. 当文字为空时，即使有占位符逻辑，实际渲染仍可能失败
4. `textLayer.setNeedsDisplay()` + `displayIfNeeded()` 在某些情况下不生效

**关键代码审查**:
```swift
// SelectableTextView.swift:234
textLayer.frame = bounds  // bounds可能为(0,0,60,30)的最小尺寸

// 问题：CATextLayer的frame.size过小时，文字可能被裁剪
```

#### 问题点3：CATextLayer渲染机制限制

**CATextLayer的已知限制**:
1. 不是UIView，无法直接响应触摸事件
2. 在transform缩放环境下可能出现模糊或不渲染
3. 需要手动管理contentsScale
4. 在异步场景下displayIfNeeded()可能不生效

**CHANGELOG中的记录**:
> "CATextLayer的渲染机制问题...占位符能显示，但与实际数据不一致...文字位置可能超出视口范围"

### 2.4 坐标系统分析

当前存在**三个坐标系**：

1. **屏幕坐标系**: 用户点击的位置（gesture.location）
2. **画布内容坐标系**: TextLayerNode.position存储的位置
3. **视图坐标系**: SelectableTextView.center的位置

**坐标转换流程**:
```swift
// NativeCanvasView.swift:673
let location = gesture.location(in: objectLayerView)  // 屏幕→objectLayerView坐标

// NativeCanvasView.swift:738
let contentLocation = convertToContentCoordinates(location)  // →画布内容坐标

// convertToContentCoordinates:
return CGPoint(
    x: (viewLocation.x + offset.x) / scale,
    y: (viewLocation.y + offset.y) / scale
)
```

**问题**:
- `location`是相对于`objectLayerView`的坐标
- 但`textOverlayView`是独立的视图层
- 两者的transform相同，但传递的坐标可能存在偏差

---

## 三、终极解决方案

### 3.1 核心设计决策

| 决策项 | 当前方案 | 新方案 | 理由 |
|-------|---------|-------|------|
| 文字渲染 | CATextLayer | **UILabel** | UILabel是UIView，渲染稳定可靠 |
| 编辑器 | UITextField | **UITextView** | 支持多行，更好的编辑体验 |
| 视图架构 | CATextLayer嵌入UIView | **UILabel作为子视图** | 简化视图层级 |
| 编辑模式 | 覆盖UITextField | **就地编辑UITextView** | 所见即所得 |

### 3.2 新架构设计

```
NativeCanvasView
├── pencilCanvas (PKCanvasView)
├── overlayContainerView
│   └── objectLayerView (箭头、形状、图片)
└── textOverlayView
    └── SelectableTextView (重构后)
        ├── contentView (UIView) - 承载内容
        │   └── textLabel (UILabel) - 显示文字
        ├── controlPointViews (角点和旋转手柄)
        └── editingTextView (UITextView) - 编辑时显示
```

### 3.3 SelectableTextView 完全重构

#### 3.3.1 废弃CATextLayer，使用UILabel

**原因**:
1. UILabel是标准UIView，渲染机制可靠
2. 自动处理contentsScale
3. 支持自动布局和动态尺寸
4. 与UITextView切换更自然

#### 3.3.2 编辑模式采用UITextView就地替换

**流程**:
1. 非编辑状态：显示UILabel
2. 开始编辑：隐藏UILabel，显示UITextView（位置和样式一致）
3. 结束编辑：隐藏UITextView，更新UILabel内容

**优势**:
1. 所见即所得的编辑体验
2. UITextView支持多行文本
3. 无需复杂的坐标计算

---

## 四、详细实施方案

### 4.1 文件修改清单

| 文件 | 修改类型 | 改动量 | 优先级 |
|------|---------|-------|-------|
| SelectableTextView.swift | **完全重写** | ~400行 | P0 |
| TextLayerNode.swift | 小修改 | ~20行 | P0 |
| NativeCanvasView.swift | 调整 | ~30行 | P1 |
| TextEditingView.swift | 可能废弃 | - | P2 |

### 4.2 SelectableTextView 完全重写

**新文件结构**:

```swift
/// 可选择的文本视图（重构版）
/// 使用UILabel渲染文字，UITextView进行编辑
class SelectableTextView: UIView {

    // MARK: - Properties

    var textNode: TextLayerNode {
        didSet { updateFromNode() }
    }

    // 显示层
    private let textLabel = UILabel()

    // 编辑层
    private var editingTextView: UITextView?

    // 选中边框和控制点
    private let selectionBorder = CAShapeLayer()
    private var cornerHandleLayers: [CAShapeLayer] = []
    private let rotationHandleLayer = CAShapeLayer()
    private let rotationLineLayer = CAShapeLayer()

    // 控制点配置
    private let handleSize: CGFloat = 12
    private let rotationHandleOffset: CGFloat = 30

    // 状态
    var isSelected: Bool = false { didSet { updateSelectionAppearance() } }
    var isEditing: Bool = false { didSet { updateEditingState() } }

    // 手势
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    private var doubleTapGesture: UITapGestureRecognizer!

    // 回调
    var onNodeUpdated: ((TextLayerNode) -> Void)?
    var onSelected: ((UUID) -> Void)?
    var onOperationStart: ((TextLayerNode) -> Void)?
    var onOperationEnd: ((SelectableTextView?, TextLayerNode) -> Void)?
    var onEditingFinished: ((TextLayerNode, String) -> Void)?

    // MARK: - Initialization

    init(textNode: TextLayerNode) {
        self.textNode = textNode
        super.init(frame: textNode.bounds)
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

        // 配置UILabel
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        textLabel.backgroundColor = .clear
        addSubview(textLabel)

        // 配置选中边框
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.strokeColor = UIColor.systemBlue.cgColor
        selectionBorder.lineWidth = 1.5
        selectionBorder.lineDashPattern = [4, 4]
        layer.addSublayer(selectionBorder)

        // 配置控制点
        setupControlPoints()
    }

    private func setupControlPoints() {
        // 旋转连接线
        rotationLineLayer.fillColor = UIColor.clear.cgColor
        rotationLineLayer.strokeColor = UIColor.systemBlue.cgColor
        rotationLineLayer.lineWidth = 1.5
        layer.addSublayer(rotationLineLayer)

        // 旋转手柄
        rotationHandleLayer.fillColor = UIColor.white.cgColor
        rotationHandleLayer.strokeColor = UIColor.systemBlue.cgColor
        rotationHandleLayer.lineWidth = 2
        layer.addSublayer(rotationHandleLayer)

        // 角点
        for _ in 0..<4 {
            let handleLayer = CAShapeLayer()
            handleLayer.fillColor = UIColor.white.cgColor
            handleLayer.strokeColor = UIColor.systemBlue.cgColor
            handleLayer.lineWidth = 2
            layer.addSublayer(handleLayer)
            cornerHandleLayers.append(handleLayer)
        }
    }

    private func setupGestures() {
        // 点击选中
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        // 双击编辑
        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)

        tapGesture.require(toFail: doubleTapGesture)

        // 拖拽移动/缩放/旋转
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
    }

    // MARK: - Update Methods

    func updateFromNode() {
        // 重置transform以便正确计算
        transform = .identity

        // 计算bounds
        let textBounds = textNode.bounds
        bounds = CGRect(origin: .zero, size: textBounds.size)
        center = textNode.position

        // 更新UILabel
        updateTextLabel()

        // 应用旋转
        transform = CGAffineTransform(rotationAngle: textNode.rotation)

        // 更新选中外观
        updateSelectionAppearance()
    }

    private func updateTextLabel() {
        // 设置文字内容
        if textNode.text.isEmpty {
            textLabel.text = "输入文字"
            textLabel.textColor = .systemGray
        } else {
            textLabel.text = textNode.text
            textLabel.textColor = UIColor(hex: textNode.color) ?? .black
        }

        // 设置字体
        let font = UIFont(name: textNode.fontName, size: textNode.fontSize * textNode.scale)
            ?? UIFont.systemFont(ofSize: textNode.fontSize * textNode.scale)
        textLabel.font = font

        // 设置frame
        textLabel.frame = bounds
    }

    // MARK: - Editing

    func startEditing() {
        guard !isEditing else { return }
        isEditing = true

        // 隐藏Label
        textLabel.isHidden = true

        // 创建UITextView
        let textView = UITextView(frame: bounds.insetBy(dx: -4, dy: -4))
        textView.text = textNode.text
        textView.font = textLabel.font
        textView.textColor = textNode.text.isEmpty ? .black : textLabel.textColor
        textView.textAlignment = .center
        textView.backgroundColor = UIColor.white.withAlphaComponent(0.95)
        textView.layer.cornerRadius = 6
        textView.layer.borderWidth = 2
        textView.layer.borderColor = UIColor.systemBlue.cgColor
        textView.delegate = self
        textView.autocorrectionType = .no
        textView.returnKeyType = .done

        addSubview(textView)
        editingTextView = textView

        // 延迟激活键盘
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, self.isEditing else { return }
            self.editingTextView?.becomeFirstResponder()
        }
    }

    func finishEditing() {
        guard isEditing else { return }

        let newText = editingTextView?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalText = textNode.text

        // 更新节点
        textNode = textNode.updated(text: newText)

        // 清理编辑视图
        editingTextView?.resignFirstResponder()
        editingTextView?.removeFromSuperview()
        editingTextView = nil

        // 显示Label
        textLabel.isHidden = false
        isEditing = false

        // 更新显示
        updateFromNode()

        // 回调
        if newText != originalText {
            onEditingFinished?(textNode, newText)
        }
        onNodeUpdated?(textNode)
    }

    // ... 其余方法（手势处理、控制点等）保持原有逻辑，但简化
}

// MARK: - UITextViewDelegate

extension SelectableTextView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // 回车键完成编辑
        if text == "\n" {
            finishEditing()
            return false
        }
        return true
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if isEditing {
            finishEditing()
        }
    }
}
```

### 4.3 TextLayerNode.swift 修改

**位置**: bounds 计算属性

**修改内容**:

```swift
var bounds: CGRect {
    // 使用占位符计算尺寸（确保空文字时也有有效尺寸）
    let displayText = text.isEmpty ? "输入文字" : text
    let nsString = displayText as NSString

    let font = UIFont(name: fontName, size: fontSize * scale)
        ?? UIFont.systemFont(ofSize: fontSize * scale)

    let attributes: [NSAttributedString.Key: Any] = [.font: font]

    var size = nsString.boundingRect(
        with: CGSize(width: 300, height: .greatestFiniteMagnitude), // 限制最大宽度
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes,
        context: nil
    ).size

    // 添加padding
    size.width += 24
    size.height += 16

    // 确保最小尺寸
    let minWidth: CGFloat = 80
    let minHeight: CGFloat = 44
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

### 4.4 NativeCanvasView.swift 调整

#### 4.4.1 修改 handleCanvasTap

**位置**: 约第672行

**修改内容**:

```swift
@objc private func handleCanvasTap(_ gesture: UITapGestureRecognizer) {
    // 文字工具模式
    if currentTool == .text {
        // 获取textOverlayView中的坐标
        let textLocation = gesture.location(in: textOverlayView)
        let textHitView = textOverlayView.hitTest(textLocation, with: nil)

        // 如果点击在已有文字上，让其自己处理
        if textHitView is SelectableTextView {
            return
        }

        // 点击空白区域创建新文字
        createTextAtLocationWithEditing(textLocation)
        return
    }

    // 其他工具：点击空白取消选中
    let location = gesture.location(in: objectLayerView)
    let hitView = objectLayerView.hitTest(location, with: nil)

    if hitView == objectLayerView || !isSelectableObject(hitView) {
        selectedNodeID = nil
    }
}
```

#### 4.4.2 修改 createTextAtLocationWithEditing

**位置**: 约第735行

**修改内容**:

```swift
private func createTextAtLocationWithEditing(_ location: CGPoint) {
    // location已经是textOverlayView坐标系
    // 转换为画布内容坐标
    let contentLocation = convertToContentCoordinates(location)

    let fontSize = stateManager?.textFontSize ?? 24
    let textColor = stateManager?.textColor ?? "#000000"
    let fontName = stateManager?.textFontName ?? ".SF Pro Display"

    let text = TextLayerNode(
        position: contentLocation,
        text: "",
        fontSize: fontSize,
        color: textColor,
        fontName: fontName,
        rotation: 0,
        scale: 1.0,
        zIndex: textLayerManager.getNextZIndex()
    )

    addText(text)
    selectedNodeID = text.id

    // 自动开始编辑
    if let textView = textViews[text.id] {
        // 确保视图布局完成后再开始编辑
        DispatchQueue.main.async {
            textView.startEditing()
        }
    }
}
```

#### 4.4.3 确保textOverlayView正确同步

**位置**: syncOverlayTransform()

**确认内容**（当前代码已正确，保持不变）:

```swift
private func syncOverlayTransform() {
    let offset = pencilCanvas.contentOffset
    let scale = pencilCanvas.zoomScale

    objectLayerView.transform = CGAffineTransform(scaleX: scale, y: scale)
    objectLayerView.frame.origin = CGPoint(x: -offset.x, y: -offset.y)

    textOverlayView.transform = CGAffineTransform(scaleX: scale, y: scale)
    textOverlayView.frame.origin = CGPoint(x: -offset.x, y: -offset.y)
}
```

---

## 五、关键诊断日志

为了验证修复效果，需要在关键位置添加以下日志：

### 5.1 创建流程日志

```swift
// NativeCanvasView.handleCanvasTap
print("📍 [Text] 点击位置(textOverlayView): \(textLocation)")

// NativeCanvasView.createTextAtLocationWithEditing
print("📝 [Text] 创建文字 - 内容坐标: \(contentLocation)")
print("📝 [Text] TextLayerNode.id: \(text.id)")

// NativeCanvasView.addText
print("📝 [Text] addText - textViews.count: \(textViews.count)")

// NativeCanvasView.createTextView
print("📝 [Text] createTextView完成 - frame: \(textView.frame)")
```

### 5.2 编辑流程日志

```swift
// SelectableTextView.startEditing
print("✏️ [Edit] 开始编辑 - bounds: \(bounds)")
print("✏️ [Edit] UITextView创建完成")

// SelectableTextView.becomeFirstResponder
print("⌨️ [Edit] becomeFirstResponder结果: \(success)")
print("⌨️ [Edit] window存在: \(window != nil)")
print("⌨️ [Edit] superview: \(String(describing: superview))")

// SelectableTextView.finishEditing
print("✅ [Edit] 完成编辑 - 文字: '\(newText)'")
```

### 5.3 渲染流程日志

```swift
// SelectableTextView.updateTextLabel
print("🖼️ [Render] 更新Label - text: '\(textNode.text)'")
print("🖼️ [Render] Label.frame: \(textLabel.frame)")
print("🖼️ [Render] Label.isHidden: \(textLabel.isHidden)")
```

---

## 六、验证测试清单

### 6.1 功能测试

| 测试项 | 操作步骤 | 预期结果 | 通过 |
|-------|---------|---------|------|
| 创建文字 | 选择文字工具 → 点击画布 | UITextView出现，键盘弹出 | [ ] |
| 输入文字 | 输入"测试文字" | 文字实时显示在UITextView中 | [ ] |
| 完成编辑 | 按键盘回车 | UITextView消失，UILabel显示文字 | [ ] |
| 再次编辑 | 双击文字 | UITextView出现，显示当前文字 | [ ] |
| 选中文字 | 单击文字 | 显示蓝色边框和控制点 | [ ] |
| 移动文字 | 拖拽文字 | 文字跟随移动 | [ ] |
| 缩放文字 | 拖拽角点 | 文字按比例缩放 | [ ] |
| 旋转文字 | 拖拽旋转手柄 | 文字围绕中心旋转 | [ ] |
| 空文字处理 | 不输入内容直接回车 | 显示"输入文字"占位符 | [ ] |
| 多文字创建 | 创建多个文字 | 每个文字独立显示 | [ ] |

### 6.2 边界测试

| 测试项 | 操作步骤 | 预期结果 | 通过 |
|-------|---------|---------|------|
| 长文本 | 输入超过50个字符 | 文字自动换行，尺寸自适应 | [ ] |
| 特殊字符 | 输入emoji和中文 | 正常显示 | [ ] |
| 快速创建 | 快速连续创建5个文字 | 全部正常显示 | [ ] |
| 缩放画布 | 缩放到0.5x和2x | 文字清晰显示 | [ ] |
| 工具切换 | 文字工具 → 画笔 → 文字 | 功能正常 | [ ] |

### 6.3 回归测试

| 功能 | 状态 |
|------|------|
| 图片导入和变换 | [ ] 正常 |
| 画笔绘图 | [ ] 正常 |
| 橡皮擦除 | [ ] 正常 |
| 箭头创建 | [ ] 正常 |
| 形状创建 | [ ] 正常 |
| 撤销/恢复 | [ ] 正常 |
| 项目保存加载 | [ ] 正常 |

---

## 七、实施步骤

### 第一步：备份当前代码

```bash
cd src/MindCanvas/MindCanvas/Views/Editor/Canvas
cp SelectableTextView.swift SelectableTextView.swift.bak
```

### 第二步：重写SelectableTextView

1. 删除所有CATextLayer相关代码
2. 添加UILabel作为文字渲染层
3. 添加UITextView作为编辑层
4. 实现startEditing/finishEditing逻辑
5. 保留原有的手势和控制点逻辑

### 第三步：修改TextLayerNode.bounds

1. 更新bounds计算逻辑
2. 添加padding和最小尺寸保证

### 第四步：调整NativeCanvasView

1. 修改handleCanvasTap坐标处理
2. 修改createTextAtLocationWithEditing
3. 验证syncOverlayTransform

### 第五步：添加诊断日志

按照第五节添加关键日志

### 第六步：测试验证

按照第六节逐项测试

### 第七步：清理日志

测试通过后移除调试日志

---

## 八、风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|-------|------|---------|
| UILabel渲染问题 | 低 | 中 | UILabel是标准组件，渲染稳定 |
| UITextView键盘问题 | 中 | 中 | 使用成熟的延迟激活模式 |
| 坐标转换错误 | 中 | 高 | 详细日志+单元测试 |
| 控制点交互问题 | 低 | 低 | 保留原有逻辑 |
| 撤销/恢复兼容性 | 中 | 中 | 确保TextLayerNode数据结构不变 |

---

## 九、附录

### A. UIColor扩展（如果不存在）

```swift
extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b, a: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
```

### B. 参考资料

1. [Apple UILabel Documentation](https://developer.apple.com/documentation/uikit/uilabel)
2. [Apple UITextView Documentation](https://developer.apple.com/documentation/uikit/uitextview)
3. [Asana/Drawsana - Text Tool Implementation](https://github.com/Asana/Drawsana)
4. [IFTTT/jot - Text State Management](https://github.com/IFTTT/jot)

### C. 核心文件位置

| 文件 | 路径 |
|------|------|
| SelectableTextView | Views/Editor/Canvas/SelectableTextView.swift |
| TextLayerNode | Models/Canvas/TextLayerNode.swift |
| NativeCanvasView | Views/Editor/Canvas/NativeCanvasView.swift |
| TextEditingView | Views/Editor/Canvas/TextEditingView.swift (可废弃) |

---

## 十、总结

本V3方案的核心改进：

1. **抛弃CATextLayer**：CATextLayer在复杂视图层级和缩放环境下存在渲染问题，改用UILabel作为渲染层
2. **使用UITextView编辑**：UITextView比UITextField更适合文字编辑场景，支持多行且编辑体验更好
3. **就地编辑模式**：编辑时UITextView覆盖UILabel的位置，所见即所得
4. **简化坐标处理**：统一使用textOverlayView坐标系，避免多层转换
5. **保留控制点交互**：缩放、旋转、移动等交互逻辑保持不变

这是一个从根本上解决问题的方案，而不是在现有架构上打补丁。通过使用标准UIKit组件（UILabel + UITextView），可以获得稳定可靠的渲染和编辑体验。
