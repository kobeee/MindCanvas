# 文本工具终极修复方案 v1.0

## 概述

本文档针对文本工具开发过程中引入的编译错误和功能缺失问题，提供完整的修复方案。方案遵循"化繁为简，大道至简"的原则，彻底解决问题而非修补。

**原始需求回顾**：
> 给画布下的工具栏加上文本工具，一个'T'，然后可以在画布上写字：要求，点击T图标，浮出字体选择列表，找一些常用受欢迎的字体（中英文），包括艺术字，字体颜色先默认是黑色；然后还要，使用选择工具选择文字时，也可以旋转以及缩放；另外，注意字体也需要能被选框截图截取到

---

## 问题诊断

### 编译错误根源分析

通过深度排查，确认了以下核心问题：

#### 问题1：CanvasToolbar.swift 第107行致命语法错误

**位置**：`CanvasToolbar.swift:107`

**当前代码**：
```swift
default:
    ToolButton(
        tool: tool,
        isSelected: currentTool == tool,
        action: { ... }
    )
    print("zzz [CanvasToolbar] === 工具切换结束 ===")  // <-- 致命错误
}
```

**问题分析**：
- `print` 语句位于 switch 的 default case 内，但在 `ToolButton` 之后
- SwiftUI 的 ForEach 闭包是 ViewBuilder，要求返回单一 View 类型
- `print` 语句返回 `Void`，破坏了 ViewBuilder 的类型推断
- 导致编译器无法推断 ForEach 的泛型参数 C

**为什么错误信息具有误导性**：
- SwiftUI 编译器在 ViewBuilder 类型推断失败时，会尝试匹配其他 ForEach 重载
- 这导致了 "Cannot convert value of type '[CanvasTool]' to expected argument type 'Binding<C>'" 等误导性错误
- 真正的问题是 ViewBuilder 中混入了非 View 类型的语句

#### 问题2：TextToolButton 定义但未使用

**位置**：`CanvasToolbar.swift:223-283`

**问题**：
- 定义了完整的 `TextToolButton` 私有结构体
- 但在 ForEach 的 `case .text:` 分支中使用的是普通 `ToolButton`
- TextToolButton 依赖 `@EnvironmentObject var stateManager: CanvasStateManager`
- 冗余代码增加了维护成本和编译器负担

#### 问题3：FontPickerPopover 参数顺序问题（潜在）

**位置**：`FontPickerPopover.swift:23-38` 和 `CanvasToolbar.swift:267-280`

**定义**：
```swift
init(
    selectedFont: Binding<String>,
    fontSize: Binding<CGFloat>,
    textColor: Binding<Color>,
    onConfirm: @escaping () -> Void,      // 必需参数
    onFontChanged: ((String, CGFloat, Color) -> Void)? = nil  // 可选参数
)
```

**调用**：
```swift
FontPickerPopover(
    selectedFont: $tempFontName,
    fontSize: $tempFontSize,
    textColor: $tempTextColor,
    onFontChanged: { ... },  // 可选参数在前
    onConfirm: { ... }       // 必需参数在后
)
```

**分析**：
- 当前调用是通过具名参数，Swift 允许这种调用方式
- 但顺序不一致容易造成混淆和潜在错误

#### 问题4：SelectableTextView 缺少控制点交互

**位置**：`SelectableTextView.swift`

**问题**：
- TextLayerNode 有 `rotation` 和 `scale` 属性
- SelectableTextView 只实现了移动功能
- 缺少旋转手柄和角点控制点
- 用户无法通过 UI 旋转和缩放文字

#### 问题5：状态管理冗余

**涉及文件**：
- `CanvasToolbar.swift`: 临时状态 `tempFontName`, `tempFontSize`, `tempTextColor`
- `CanvasStateManager.swift`: 全局状态 `textFontName`, `textFontSize`, `textColor`
- `FontPickerPopover.swift`: 接收 `@Binding` 参数

**问题**：
- 三层状态导致数据流混乱
- `onFontChanged` 实时回调增加复杂度
- 不符合 SwiftUI 单向数据流原则

---

## 修复方案

### 阶段一：修复编译错误（立即执行）

#### 修复1.1：删除 CanvasToolbar 中的 print 语句

**文件**：`src/MindCanvas/MindCanvas/Views/Editor/Canvas/CanvasToolbar.swift`

**修改位置**：第107行

**修改前**：
```swift
default:
    ToolButton(
        tool: tool,
        isSelected: currentTool == tool,
        action: { ... }
    )
    print("zzz [CanvasToolbar] === 工具切换结束 ===")
}
```

**修改后**：
```swift
default:
    ToolButton(
        tool: tool,
        isSelected: currentTool == tool,
        action: { ... }
    )
}
```

**说明**：直接删除第107行的 `print` 语句。如需调试日志，应在 `action` 闭包内部添加。

#### 修复1.2：删除未使用的 TextToolButton

**文件**：`src/MindCanvas/MindCanvas/Views/Editor/Canvas/CanvasToolbar.swift`

**修改位置**：第221-283行

**操作**：删除整个 `TextToolButton` 结构体定义（第221-283行），包括其上方的 MARK 注释。

**理由**：
- 该组件未被使用
- 依赖 `@EnvironmentObject`，增加了编译器负担
- 后续会用更简洁的方式实现文本工具按钮

---

### 阶段二：重构文本工具交互（简化设计）

#### 修复2.1：修改 case .text 分支

**文件**：`src/MindCanvas/MindCanvas/Views/Editor/Canvas/CanvasToolbar.swift`

**修改位置**：第60-71行

**修改前**：
```swift
case .text:
    // 文字工具 - 临时简化为普通按钮
    ToolButton(
        tool: tool,
        isSelected: currentTool == tool,
        action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentTool = tool
                onToolChanged?(tool)
            }
        }
    )
```

**修改后**：
```swift
case .text:
    // 文字工具 - 点击选中，长按/再次点击显示设置
    TextToolButtonView(
        tool: tool,
        isSelected: currentTool == tool,
        showSettings: $showFontSettings,
        onSelect: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                currentTool = tool
                onToolChanged?(tool)
            }
        }
    )
```

#### 修复2.2：新增 TextToolButtonView 组件

**文件**：`src/MindCanvas/MindCanvas/Views/Editor/Canvas/CanvasToolbar.swift`

**插入位置**：在 `PenToolButton` 结构体之后（约第219行之后）

**新增代码**：
```swift
// MARK: - 文字工具按钮（带弹出设置面板）

private struct TextToolButtonView: View {
    let tool: CanvasTool
    let isSelected: Bool
    @Binding var showSettings: Bool
    let onSelect: () -> Void

    var body: some View {
        Button {
            if isSelected {
                // 已选中时，点击弹出设置
                showSettings.toggle()
            } else {
                // 未选中时，先选中工具
                onSelect()
            }
        } label: {
            Image(systemName: tool.iconName)
                .font(.system(size: 22))
                .foregroundColor(isSelected ? .white : Theme.Colors.secondaryText)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .fill(isSelected ? Theme.Colors.brandBlue : Color.clear)
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .help(tool.displayName)
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            SimpleFontPickerPopover(onConfirm: {
                showSettings = false
            })
        }
    }
}
```

#### 修复2.3：简化 FontPickerPopover

**创建新文件**：`src/MindCanvas/MindCanvas/Views/Editor/Canvas/SimpleFontPickerPopover.swift`

**设计原则**：
- 移除 `@Binding` 参数，改为直接操作 CanvasStateManager
- 移除 `onFontChanged` 实时回调
- 保留 `onConfirm` 用于关闭弹窗

**完整代码**：

```swift
import SwiftUI

/// 简化版字体选择弹窗
/// 直接操作 CanvasStateManager，无中间状态
struct SimpleFontPickerPopover: View {
    @EnvironmentObject private var stateManager: CanvasStateManager
    let onConfirm: () -> Void

    // 本地预览状态（仅用于实时预览，不影响全局）
    @State private var previewFontName: String = ".SF Pro Display"
    @State private var previewFontSize: CGFloat = 24
    @State private var previewTextColor: Color = .black

    // 字体分类
    @State private var selectedCategory: FontCategory = .system
    @State private var searchText: String = ""

    // 预设颜色
    private let presetColors: [Color] = [
        .black, .white,
        Color(hex: "#FF3B30") ?? .red,      // iOS红
        Color(hex: "#FF9500") ?? .orange,   // iOS橙
        Color(hex: "#FFCC00") ?? .yellow,   // iOS黄
        Color(hex: "#34C759") ?? .green,    // iOS绿
        Color(hex: "#007AFF") ?? .blue,     // iOS蓝
        Color(hex: "#5856D6") ?? .purple,   // iOS紫
        Color(hex: "#AF52DE") ?? .purple,   // iOS浅紫
        Color(hex: "#FF2D55") ?? .pink,     // iOS粉
        Color(hex: "#A2845E") ?? .brown,    // 棕色
        Color(hex: "#8E8E93") ?? .gray,     // iOS灰
    ]

    // 字体大小选项
    private let fontSizes: [CGFloat] = [12, 16, 20, 24, 32, 48, 64]

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Button("取消") {
                    onConfirm()
                }
                .foregroundColor(Theme.Colors.secondaryText)

                Spacer()

                Text("文字设置")
                    .font(Theme.Fonts.headline)

                Spacer()

                Button("完成") {
                    // 确认时同步到全局状态
                    stateManager.setTextFontName(previewFontName)
                    stateManager.setTextFontSize(previewFontSize)
                    stateManager.setTextColor(previewTextColor.toHex() ?? "#000000")
                    onConfirm()
                }
                .foregroundColor(Theme.Colors.brandBlue)
                .fontWeight(.semibold)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // 预览区域
                    previewSection

                    // 字体分类
                    categorySection

                    // 字体列表
                    fontListSection

                    // 字体大小
                    fontSizeSection

                    // 颜色选择
                    colorSection
                }
                .padding()
            }
        }
        .frame(width: 380, height: 580)
        .background(Theme.Colors.appBackground)
        .onAppear {
            // 初始化预览状态
            previewFontName = stateManager.textFontName ?? ".SF Pro Display"
            previewFontSize = stateManager.textFontSize
            previewTextColor = Color(hex: stateManager.textColor) ?? .black
        }
    }

    // MARK: - 预览区域

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("预览")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.secondaryText)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                    .fill(Theme.Colors.cardBackground)

                Text("预览文字 AaBbCc 123")
                    .font(.custom(previewFontName, size: min(previewFontSize, 32)))
                    .foregroundColor(previewTextColor)
            }
            .frame(height: 80)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - 分类选择

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("分类")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(FontCategory.allCases, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category.displayName)
                                .font(Theme.Fonts.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedCategory == category
                                              ? Theme.Colors.brandBlue
                                              : Theme.Colors.cardBackground)
                                )
                                .foregroundColor(selectedCategory == category ? .white : Theme.Colors.primaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 字体列表

    private var fontListSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("字体")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.secondaryText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(filteredFonts, id: \.name) { font in
                    Button {
                        previewFontName = font.name
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(font.displayName)
                                    .font(.custom(font.name, size: 13))
                                    .lineLimit(1)

                                if font.supportsChinese {
                                    Text("支持中文")
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.red.opacity(0.15))
                                        .foregroundColor(.red)
                                        .cornerRadius(2)
                                }
                            }

                            Spacer()

                            if previewFontName == font.name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.Colors.brandBlue)
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(previewFontName == font.name
                                      ? Theme.Colors.brandBlue.opacity(0.1)
                                      : Theme.Colors.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(previewFontName == font.name
                                        ? Theme.Colors.brandBlue
                                        : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.Colors.primaryText)
                }
            }
        }
    }

    // MARK: - 字体大小

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("大小")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.secondaryText)

                Spacer()

                Text("\(Int(previewFontSize)) pt")
                    .font(Theme.Fonts.bodyBold)
                    .foregroundColor(Theme.Colors.brandBlue)
            }

            Slider(value: $previewFontSize, in: 12...72, step: 1)
                .tint(Theme.Colors.brandBlue)

            HStack(spacing: 8) {
                ForEach(fontSizes, id: \.self) { size in
                    Button {
                        previewFontSize = size
                    } label: {
                        Text("\(Int(size))")
                            .font(Theme.Fonts.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(previewFontSize == size
                                          ? Theme.Colors.brandBlue
                                          : Theme.Colors.cardBackground)
                            )
                            .foregroundColor(previewFontSize == size ? .white : Theme.Colors.primaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 颜色选择

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("颜色")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.secondaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                ForEach(presetColors, id: \.self) { color in
                    Button {
                        previewTextColor = color
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(color)
                                .frame(width: 36, height: 36)

                            if previewTextColor == color {
                                Image(systemName: "checkmark")
                                    .foregroundColor(color == .white ? .black : .white)
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(previewTextColor == color
                                        ? Theme.Colors.brandBlue
                                        : Color.gray.opacity(0.3), lineWidth: previewTextColor == color ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 过滤后的字体列表

    private var filteredFonts: [FontInfo] {
        let fonts = selectedCategory.fonts
        if searchText.isEmpty {
            return fonts
        }
        return fonts.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - 字体分类

enum FontCategory: CaseIterable {
    case system
    case chinese
    case sansSerif
    case serif
    case handwritten
    case monospaced

    var displayName: String {
        switch self {
        case .system: return "系统"
        case .chinese: return "中文"
        case .sansSerif: return "无衬线"
        case .serif: return "衬线"
        case .handwritten: return "手写"
        case .monospaced: return "等宽"
        }
    }

    var fonts: [FontInfo] {
        switch self {
        case .system:
            return [
                FontInfo(name: ".SF Pro Display", displayName: "SF Pro", supportsChinese: false),
                FontInfo(name: ".SF Pro Rounded", displayName: "SF Rounded", supportsChinese: false),
                FontInfo(name: ".SF Compact Display", displayName: "SF Compact", supportsChinese: false),
            ]
        case .chinese:
            return [
                FontInfo(name: "PingFang SC", displayName: "苹方-简", supportsChinese: true),
                FontInfo(name: "PingFang TC", displayName: "苹方-繁", supportsChinese: true),
                FontInfo(name: "Heiti SC", displayName: "黑体-简", supportsChinese: true),
                FontInfo(name: "STHeitiSC-Light", displayName: "华文黑体", supportsChinese: true),
                FontInfo(name: "STSongti-SC-Regular", displayName: "华文宋体", supportsChinese: true),
                FontInfo(name: "STKaiti", displayName: "华文楷体", supportsChinese: true),
                FontInfo(name: "STFangsong", displayName: "华文仿宋", supportsChinese: true),
            ]
        case .sansSerif:
            return [
                FontInfo(name: "Helvetica Neue", displayName: "Helvetica Neue", supportsChinese: false),
                FontInfo(name: "Arial", displayName: "Arial", supportsChinese: false),
                FontInfo(name: "Avenir Next", displayName: "Avenir Next", supportsChinese: false),
                FontInfo(name: "Futura", displayName: "Futura", supportsChinese: false),
                FontInfo(name: "Gill Sans", displayName: "Gill Sans", supportsChinese: false),
            ]
        case .serif:
            return [
                FontInfo(name: "Times New Roman", displayName: "Times New Roman", supportsChinese: false),
                FontInfo(name: "Georgia", displayName: "Georgia", supportsChinese: false),
                FontInfo(name: "Baskerville", displayName: "Baskerville", supportsChinese: false),
                FontInfo(name: "Palatino", displayName: "Palatino", supportsChinese: false),
                FontInfo(name: "Didot", displayName: "Didot", supportsChinese: false),
            ]
        case .handwritten:
            return [
                FontInfo(name: "Bradley Hand", displayName: "Bradley Hand", supportsChinese: false),
                FontInfo(name: "Marker Felt", displayName: "Marker Felt", supportsChinese: false),
                FontInfo(name: "Noteworthy", displayName: "Noteworthy", supportsChinese: false),
                FontInfo(name: "Snell Roundhand", displayName: "Snell Roundhand", supportsChinese: false),
                FontInfo(name: "Zapfino", displayName: "Zapfino", supportsChinese: false),
            ]
        case .monospaced:
            return [
                FontInfo(name: "Menlo", displayName: "Menlo", supportsChinese: false),
                FontInfo(name: "Monaco", displayName: "Monaco", supportsChinese: false),
                FontInfo(name: "Courier New", displayName: "Courier New", supportsChinese: false),
                FontInfo(name: "SF Mono", displayName: "SF Mono", supportsChinese: false),
            ]
        }
    }
}

// MARK: - 字体信息

struct FontInfo {
    let name: String
    let displayName: String
    let supportsChinese: Bool
}
```

---

### 阶段三：完善 SelectableTextView 控制点交互

#### 修复3.1：添加控制点系统

**文件**：`src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableTextView.swift`

**重构说明**：参考 `SelectableShapeView.swift` 的实现模式，为 SelectableTextView 添加完整的控制点交互系统。

**关键修改**：

1. **添加控制点枚举和图层**（在类属性区域添加）：

```swift
// 控制点类型（复用 SelectableShapeView 的定义或定义局部枚举）
private enum TextControlHandle: Int {
    case topLeft = 0
    case topRight = 1
    case bottomRight = 2
    case bottomLeft = 3
    case rotation = 4

    func position(in bounds: CGRect, rotationOffset: CGFloat = 30) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: bounds.minX, y: bounds.minY)
        case .topRight: return CGPoint(x: bounds.maxX, y: bounds.minY)
        case .bottomRight: return CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .bottomLeft: return CGPoint(x: bounds.minX, y: bounds.maxY)
        case .rotation: return CGPoint(x: bounds.midX, y: bounds.minY - rotationOffset)
        }
    }

    var oppositeCorner: TextControlHandle? {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomRight: return .topLeft
        case .bottomLeft: return .topRight
        case .rotation: return nil
        }
    }
}

// 控制点配置
private let handleSize: CGFloat = 12
private let rotationHandleOffset: CGFloat = 30

// 控制点图层
private var cornerHandleLayers: [CAShapeLayer] = []
private let rotationHandleLayer = CAShapeLayer()
private let rotationLineLayer = CAShapeLayer()

// 当前活动的控制点
private var activeHandle: TextControlHandle?

// 初始状态（用于旋转和缩放）
private var initialBounds: CGRect = .zero
private var initialRotation: CGFloat = 0
private var initialTouchAngle: CGFloat = 0
private var initialNode: TextLayerNode?
```

2. **修改 setupViews() 方法**（添加控制点图层）：

```swift
private func setupViews() {
    backgroundColor = .clear
    isOpaque = false
    clipsToBounds = false

    // 配置文本图层
    textLayer.contentsScale = UIScreen.main.scale
    textLayer.alignmentMode = .center
    textLayer.isWrapped = true
    layer.addSublayer(textLayer)

    // 添加选中边框
    layer.addSublayer(selectionBorder)

    // 添加旋转连接线
    rotationLineLayer.fillColor = UIColor.clear.cgColor
    rotationLineLayer.strokeColor = UIColor.systemBlue.cgColor
    rotationLineLayer.lineWidth = 1.5
    layer.addSublayer(rotationLineLayer)

    // 添加旋转手柄
    rotationHandleLayer.fillColor = UIColor.white.cgColor
    rotationHandleLayer.strokeColor = UIColor.systemBlue.cgColor
    rotationHandleLayer.lineWidth = 2
    layer.addSublayer(rotationHandleLayer)

    // 添加角点控制点
    for _ in 0..<4 {
        let handleLayer = CAShapeLayer()
        handleLayer.fillColor = UIColor.white.cgColor
        handleLayer.strokeColor = UIColor.systemBlue.cgColor
        handleLayer.lineWidth = 2
        layer.addSublayer(handleLayer)
        cornerHandleLayers.append(handleLayer)
    }

    updateSelectionStyle()
}
```

3. **修改 updateSelectionAppearance() 方法**：

```swift
private func updateSelectionAppearance() {
    let showHandles = isSelected && !isEditing

    selectionBorder.isHidden = !showHandles
    rotationLineLayer.isHidden = !showHandles
    rotationHandleLayer.isHidden = !showHandles
    cornerHandleLayers.forEach { $0.isHidden = !showHandles }

    guard showHandles else { return }

    // 更新选中边框
    selectionBorder.path = UIBezierPath(rect: bounds).cgPath

    // 更新角点控制点
    let corners: [TextControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
    for (index, corner) in corners.enumerated() {
        let position = corner.position(in: bounds)
        let handleRect = CGRect(
            x: position.x - handleSize / 2,
            y: position.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        cornerHandleLayers[index].path = UIBezierPath(rect: handleRect).cgPath
    }

    // 更新旋转连接线
    let linePath = UIBezierPath()
    linePath.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
    linePath.addLine(to: CGPoint(x: bounds.midX, y: bounds.minY - rotationHandleOffset))
    rotationLineLayer.path = linePath.cgPath

    // 更新旋转手柄
    let rotationPos = TextControlHandle.rotation.position(in: bounds, rotationOffset: rotationHandleOffset)
    let rotationRect = CGRect(
        x: rotationPos.x - handleSize / 2,
        y: rotationPos.y - handleSize / 2,
        width: handleSize,
        height: handleSize
    )
    rotationHandleLayer.path = UIBezierPath(ovalIn: rotationRect).cgPath
}
```

4. **添加 hitTestHandle 方法**：

```swift
private func hitTestHandle(at point: CGPoint) -> TextControlHandle? {
    guard isSelected else { return nil }

    let hitRadius: CGFloat = handleSize + 10

    // 坐标转换：将触摸点从旋转后的坐标系转换到本地坐标系
    let rotationAngle = atan2(transform.b, transform.a)
    let cosR = cos(-rotationAngle)
    let sinR = sin(-rotationAngle)

    let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
    let relativePoint = CGPoint(x: point.x - centerPoint.x, y: point.y - centerPoint.y)
    let rotatedPoint = CGPoint(
        x: relativePoint.x * cosR - relativePoint.y * sinR,
        y: relativePoint.x * sinR + relativePoint.y * cosR
    )
    let localTouchPoint = CGPoint(x: rotatedPoint.x + centerPoint.x, y: rotatedPoint.y + centerPoint.y)

    // 先检查旋转手柄
    let rotationPos = TextControlHandle.rotation.position(in: bounds, rotationOffset: rotationHandleOffset)
    if distance(from: localTouchPoint, to: rotationPos) < hitRadius {
        return .rotation
    }

    // 再检查角点
    let corners: [TextControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
    for corner in corners {
        let cornerPos = corner.position(in: bounds)
        if distance(from: localTouchPoint, to: cornerPos) < hitRadius {
            return corner
        }
    }

    return nil
}

private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
    sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
}
```

5. **修改 handlePan 方法**：

```swift
@objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    let locationInSelf = gesture.location(in: self)

    switch gesture.state {
    case .began:
        initialNode = textNode
        onOperationStart?(textNode)

        activeHandle = hitTestHandle(at: locationInSelf)
        initialCenter = center
        initialBounds = bounds
        initialRotation = atan2(transform.b, transform.a)

        if activeHandle == .rotation {
            let touchInSuperview = gesture.location(in: superview)
            initialTouchAngle = atan2(
                touchInSuperview.y - initialCenter.y,
                touchInSuperview.x - initialCenter.x
            )
        }
        dragStartPoint = gesture.location(in: superview)

    case .changed:
        let currentPoint = gesture.location(in: superview)

        if let handle = activeHandle {
            switch handle {
            case .rotation:
                handleRotation(currentPoint: currentPoint)
            default:
                handleResize(handle: handle, currentPoint: currentPoint)
            }
        } else {
            handleMove(currentPoint: currentPoint)
        }

    case .ended, .cancelled:
        syncToNode()
        if let initial = initialNode {
            onOperationEnd?(self, textNode)
        }
        activeHandle = nil
        initialNode = nil

    default:
        break
    }
}

private func handleMove(currentPoint: CGPoint) {
    let dx = currentPoint.x - dragStartPoint.x
    let dy = currentPoint.y - dragStartPoint.y
    center = CGPoint(x: initialCenter.x + dx, y: initialCenter.y + dy)
}

private func handleRotation(currentPoint: CGPoint) {
    let currentTouchAngle = atan2(
        currentPoint.y - initialCenter.y,
        currentPoint.x - initialCenter.x
    )
    let deltaAngle = currentTouchAngle - initialTouchAngle
    let newRotation = initialRotation + deltaAngle
    transform = CGAffineTransform(rotationAngle: newRotation)
    updateSelectionAppearance()
}

private func handleResize(handle: TextControlHandle, currentPoint: CGPoint) {
    // 简化的缩放实现：根据拖拽距离计算缩放因子
    let dragDeltaX = currentPoint.x - dragStartPoint.x
    let dragDeltaY = currentPoint.y - dragStartPoint.y

    // 计算拖拽方向上的总距离
    let totalDelta = sqrt(dragDeltaX * dragDeltaX + dragDeltaY * dragDeltaY)
    let sign: CGFloat = (dragDeltaX + dragDeltaY) > 0 ? 1 : -1

    // 计算缩放因子（限制在合理范围内）
    let scaleFactor = 1.0 + (sign * totalDelta) / 200.0
    let newScale = max(0.5, min(3.0, textNode.scale * scaleFactor))

    // 更新节点
    textNode = textNode.updated(scale: newScale)

    // 重新计算边界
    let textBounds = textNode.bounds
    bounds = CGRect(origin: .zero, size: textBounds.size)
    textLayer.frame = bounds

    // 保持旋转角度
    transform = CGAffineTransform(rotationAngle: initialRotation)

    updateSelectionAppearance()
}
```

6. **修改 syncToNode 方法**：

```swift
private func syncToNode() {
    let currentRotation = atan2(transform.b, transform.a)

    textNode = textNode.updated(
        position: center,
        rotation: currentRotation
        // scale 已在 handleResize 中更新
    )
    onNodeUpdated?(textNode)
}
```

7. **添加 point(inside:with:) 重写**：

```swift
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // 坐标转换：考虑旋转
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

    // 扩展边界以包含控制点
    let expandedBounds = bounds.insetBy(
        dx: -(handleSize + rotationHandleOffset + 20),
        dy: -(handleSize + rotationHandleOffset + 20)
    )
    return expandedBounds.contains(localPoint)
}
```

---

### 阶段四：清理冗余代码

#### 修复4.1：删除旧的 FontPickerPopover

**操作**：
- 保留 `FontPickerPopover.swift` 文件，但标记为 deprecated
- 或者直接删除，使用新的 `SimpleFontPickerPopover.swift`

#### 修复4.2：删除 FontManager 相关的复杂代码

**操作**：
- 删除 `FontManager.swift`
- 删除 `FontAvailabilityDetector.swift`
- 删除 `FontManagementPanel.swift`
- 删除 `FontPreviewView.swift`

**理由**：
- 这些文件过度设计，增加了编译负担
- 简化后的 `SimpleFontPickerPopover` 已内置必要的字体列表
- 后续如需扩展，可按需添加

---

## 文件修改清单

### 必须修改的文件

| 文件路径 | 操作 | 说明 |
|---------|------|------|
| `Views/Editor/Canvas/CanvasToolbar.swift` | 修改 | 删除第107行print，删除TextToolButton，修改case .text |
| `Views/Editor/Canvas/SelectableTextView.swift` | 重构 | 添加控制点系统 |

### 必须新增的文件

| 文件路径 | 说明 |
|---------|------|
| `Views/Editor/Canvas/SimpleFontPickerPopover.swift` | 简化版字体选择弹窗 |

### 可选删除的文件

| 文件路径 | 说明 |
|---------|------|
| `Infrastructure/FontManager.swift` | 过度设计的字体管理器 |
| `Infrastructure/FontAvailabilityDetector.swift` | 字体可用性检测器 |
| `Views/Editor/Canvas/FontManagementPanel.swift` | 字体管理面板 |
| `Views/Editor/Canvas/FontPreviewView.swift` | 字体预览组件 |
| `Views/Editor/Canvas/FontPickerPopover.swift` | 旧版字体选择器（可保留但不使用） |

---

## 验收标准

### 编译验收
- [ ] 项目编译无错误
- [ ] 无任何警告（或仅有预期的 deprecation 警告）

### 功能验收
- [ ] 点击工具栏中的 T 图标，工具切换正常
- [ ] 再次点击 T 图标（已选中状态），弹出字体设置面板
- [ ] 字体设置面板可以选择字体、调整大小、选择颜色
- [ ] 点击画布可以创建文字
- [ ] 选择工具可以选中已创建的文字
- [ ] 拖拽文字可以移动位置
- [ ] 拖拽旋转手柄可以旋转文字
- [ ] 拖拽角点可以缩放文字
- [ ] 旋转后仍可继续旋转和缩放
- [ ] 双击文字可以编辑内容

### UI/UX 验收
- [ ] 字体选择面板设计美观、符合 iOS 规范
- [ ] 控制点样式与形状工具保持一致
- [ ] 动画流畅自然
- [ ] 文字可被选框截图截取

---

## 执行顺序

1. **阶段一**：修复编译错误（必须首先完成）
   - 删除第107行 print 语句
   - 删除 TextToolButton 定义
   - 验证编译通过

2. **阶段二**：重构文本工具交互
   - 创建 SimpleFontPickerPopover.swift
   - 修改 case .text 分支
   - 添加 TextToolButtonView
   - 验证字体选择功能

3. **阶段三**：完善 SelectableTextView
   - 添加控制点图层
   - 实现旋转和缩放手势
   - 验证交互功能

4. **阶段四**：清理冗余代码（可选）
   - 删除或标记 deprecated 的文件
   - 最终验证

---

## 附录：调试日志添加指南

如需调试，在以下位置添加日志（使用 `#if DEBUG`）：

```swift
#if DEBUG
func debugLog(_ message: String) {
    print("[TextTool] \(message)")
}
#endif
```

**建议的日志点**：
1. `CanvasToolbar` 工具切换时
2. `SimpleFontPickerPopover` 字体选择确认时
3. `SelectableTextView` 控制点命中测试时
4. `NativeCanvasView` 文字创建时

---

**文档版本**：v1.0
**创建日期**：2025-12-20
**作者**：Claude Code Assistant
