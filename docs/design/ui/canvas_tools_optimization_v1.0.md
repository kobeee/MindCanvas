# 画布工具优化方案 v1.0

## 概述

本方案针对两个核心问题进行优化：
1. **清屏操作不清理图形对象** - 箭头、形状等对象在清屏后仍然残留
2. **画笔工具体验缺失** - 缺少笔触大小和颜色选择功能，图标不够直观

## 问题分析

### 问题一：清屏操作遗漏图形对象

**现状**：
- `NativeCanvasView.clearCanvas()` 调用 `removeAllLayers()` 清理对象
- `removeAllLayers()` 只清理了 `imageViews` 字典
- `arrowViews` 和 `shapeViews` 字典未被清理

**代码位置**：`NativeCanvasView.swift` 第 306-312 行

```swift
// 当前实现 - 只清理了 imageViews
func removeAllLayers() {
    layers.removeAll()
    imageViews.values.forEach { $0.removeFromSuperview() }
    imageViews.removeAll()
    selectedNodeID = nil
    onLayersUpdated?(layers)
}
```

**遗漏的对象**：
- `arrowViews: [UUID: SelectableArrowView]` - 箭头/直线视图
- `shapeViews: [UUID: SelectableShapeView]` - 形状视图
- `arrowLayerManager` / `shapeLayerManager` 管理的数据

### 问题二：画笔工具体验缺失

**现状**：
1. **硬编码配置**：`inkingTool` 固定为黑色、2pt 宽度（第 55 行）
2. **无 UI 入口**：点击画笔工具直接切换，无法调整参数
3. **图标不直观**：使用 `pencil` 图标，与 iPad 的 Apple Pencil 混淆

**状态管理现状**：
- `CanvasStateManager` 已有 `shapeStrokeColor`、`shapeLineWidth` 等属性
- 但没有 `penColor`、`penLineWidth` 等画笔专属属性
- PencilKit 的 `PKInkingTool` 支持动态创建

---

## 解决方案

### 方案一：修复清屏功能

#### 修改文件
`src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift`

#### 修改内容

**Step 1**: 重写 `removeAllLayers()` 方法，增加箭头和形状的清理逻辑

```swift
/// 移除所有图层（包括图片、箭头、形状）
func removeAllLayers() {
    // 1. 清空图层数据
    layers.removeAll()

    // 2. 清理图片视图
    imageViews.values.forEach { $0.removeFromSuperview() }
    imageViews.removeAll()

    // 3. 清理箭头视图
    arrowViews.values.forEach { $0.removeFromSuperview() }
    arrowViews.removeAll()

    // 4. 清理形状视图
    shapeViews.values.forEach { $0.removeFromSuperview() }
    shapeViews.removeAll()

    // 5. 清理管理器数据
    // 注意：如果管理器有 removeAll 方法，也需要调用

    // 6. 清空选中状态
    selectedNodeID = nil

    // 7. 通知更新
    onLayersUpdated?(layers)
}
```

**Step 2**: 确认 `arrowLayerManager` 和 `shapeLayerManager` 是否需要清理

检查这两个管理器是否维护了独立的数据结构，如果有，需要添加清理方法。

---

### 方案二：画笔工具交互优化

#### 设计目标

1. **点击画笔工具** -> 弹出浮窗（Popover）
2. **浮窗内容**：
   - 笔触大小滑块（1-20pt）
   - 颜色选择器（预设颜色 + 自定义）
3. **交互流程**：调整参数后自动应用，点击外部关闭
4. **图标优化**：使用更直观的画笔图标

#### UI 设计稿

```
+----------------------------------+
|        笔触设置                   |
+----------------------------------+
|                                  |
|  大小                            |
|  [====o================] 4pt     |
|                                  |
|  颜色                            |
|  [黑] [红] [蓝] [绿] [黄] [+]    |
|                                  |
+----------------------------------+
```

#### 架构设计

```
                                 CanvasToolbar
                                      |
                        +-------------+-------------+
                        |                           |
                   ToolButton               PenToolButton
                   (普通工具)                (画笔工具)
                                                |
                                         点击弹出 Popover
                                                |
                                        PenSettingsPopover
                                           /        \
                                   SizeSlider    ColorPicker
```

#### 新增文件

##### 1. `PenSettingsPopover.swift`

位置：`src/MindCanvas/MindCanvas/Views/Editor/Canvas/PenSettingsPopover.swift`

```swift
import SwiftUI

/// 画笔设置弹出框
struct PenSettingsPopover: View {
    @Binding var penColor: Color
    @Binding var penWidth: CGFloat
    @Environment(\.dismiss) private var dismiss

    // 预设颜色
    private let presetColors: [Color] = [
        .black, .red, .blue, .green, .orange, .purple, .brown, .gray
    ]

    // 线宽范围
    private let minWidth: CGFloat = 1
    private let maxWidth: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            Text("笔触设置")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 16) {
                // 大小调节
                sizeSection

                // 颜色选择
                colorSection
            }
            .padding(16)
        }
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        )
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - 大小调节区

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("大小")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(penWidth))pt")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
            }

            // 自定义滑块样式
            HStack(spacing: 12) {
                // 最小预览圆
                Circle()
                    .fill(penColor)
                    .frame(width: 4, height: 4)

                Slider(value: $penWidth, in: minWidth...maxWidth, step: 1)
                    .tint(Theme.Colors.brandBlue)

                // 最大预览圆
                Circle()
                    .fill(penColor)
                    .frame(width: 16, height: 16)
            }

            // 实时预览线条
            penPreview
        }
    }

    // MARK: - 线条预览

    private var penPreview: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: penWidth / 2)
                .fill(penColor)
                .frame(width: 80, height: penWidth)
            Spacer()
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .systemGray6))
        )
    }

    // MARK: - 颜色选择区

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("颜色")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(presetColors, id: \.self) { color in
                    ColorButton(
                        color: color,
                        isSelected: penColor == color,
                        action: { penColor = color }
                    )
                }

                // 自定义颜色按钮
                CustomColorButton(selectedColor: $penColor)
            }
        }
    }
}

// MARK: - 颜色按钮

private struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 32, height: 32)

                    Circle()
                        .strokeBorder(Theme.Colors.brandBlue, lineWidth: 2)
                        .frame(width: 38, height: 38)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
    }
}

// MARK: - 自定义颜色按钮

private struct CustomColorButton: View {
    @Binding var selectedColor: Color

    var body: some View {
        ColorPicker("", selection: $selectedColor, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .frame(width: 44, height: 44)
    }
}

// MARK: - Preview

#Preview {
    PenSettingsPopover(
        penColor: .constant(.black),
        penWidth: .constant(4)
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
```

#### 修改文件

##### 1. `CanvasStateManager.swift`

新增画笔属性：

```swift
// MARK: - 画笔工具

/// 画笔颜色（十六进制）
var penColor: String = "#000000"

/// 画笔线宽
var penLineWidth: CGFloat = 4

/// 设置画笔颜色
func setPenColor(_ color: String) {
    penColor = color
}

/// 设置画笔线宽
func setPenLineWidth(_ width: CGFloat) {
    penLineWidth = max(1, min(20, width))  // 限制范围 1-20
}
```

##### 2. `CanvasTool.swift`

更新画笔图标：

```swift
var iconName: String {
    switch self {
    case .pen:
        return "paintbrush.pointed"  // 更直观的画笔图标
    // ... 其他保持不变
    }
}
```

可选图标方案：
- `paintbrush.pointed` - 尖头画笔（推荐）
- `paintbrush` - 标准画笔
- `pencil.tip` - 笔尖
- `scribble.variable` - 涂鸦

##### 3. `CanvasToolbar.swift`

新增 `PenToolButton` 组件，替换原有的普通 `ToolButton`：

```swift
// MARK: - 画笔工具按钮（带弹出设置）

private struct PenToolButton: View {
    let tool: CanvasTool
    let isSelected: Bool
    @Binding var showSettings: Bool
    let onSelect: () -> Void

    // 绑定画笔属性
    @Binding var penColor: Color
    @Binding var penWidth: CGFloat

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
            PenSettingsPopover(
                penColor: $penColor,
                penWidth: $penWidth
            )
        }
    }
}
```

更新 `CanvasToolbar` 主视图：

```swift
struct CanvasToolbar: View {
    @Binding var currentTool: CanvasTool
    var onImageImport: () -> Void
    var onShapeSelected: ((ShapeType) -> Void)?

    // 画笔设置
    @Binding var penColor: Color
    @Binding var penWidth: CGFloat

    @State private var showShapePicker = false
    @State private var showPenSettings = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(CanvasTool.mainToolbarTools, id: \.self) { tool in
                switch tool {
                case .rectangle:
                    // 图形工具 - 弹出形状选择器
                    ShapeToolButton(...)

                case .pen:
                    // 画笔工具 - 弹出设置面板
                    PenToolButton(
                        tool: tool,
                        isSelected: currentTool == tool,
                        showSettings: $showPenSettings,
                        onSelect: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                currentTool = tool
                            }
                        },
                        penColor: $penColor,
                        penWidth: $penWidth
                    )

                default:
                    // 其他工具 - 普通按钮
                    ToolButton(...)
                }
            }
        }
        // ... 样式保持不变
    }
}
```

##### 4. `NativeCanvasView.swift`

将硬编码的 `inkingTool` 改为动态创建：

```swift
// 移除这行：
// private let inkingTool = PKInkingTool(.pen, color: .black, width: 2)

// 新增属性：
var penColor: UIColor = .black
var penLineWidth: CGFloat = 4

// 新增方法：
func updatePenSettings(color: UIColor, width: CGFloat) {
    penColor = color
    penLineWidth = width

    // 如果当前是画笔工具，立即更新
    if currentTool == .pen {
        pencilCanvas.tool = PKInkingTool(.pen, color: color, width: width)
    }
}

// 修改 updateForTool 方法中的 .pen 分支：
case .pen:
    pencilCanvas.isUserInteractionEnabled = true
    pencilCanvas.tool = PKInkingTool(.pen, color: penColor, width: penLineWidth)
    // ... 其他配置保持不变
```

##### 5. `NativeEditorView.swift`

添加颜色转换和数据流绑定：

```swift
// 在 body 中更新 CanvasToolbar 调用：
CanvasToolbar(
    currentTool: $viewModel.stateManager.currentTool,
    onImageImport: onImageImport,
    onShapeSelected: { shapeType in
        viewModel.selectedShapeType = shapeType
    },
    penColor: Binding(
        get: { Color(hex: viewModel.stateManager.penColor) },
        set: { newColor in
            viewModel.stateManager.setPenColor(newColor.toHex() ?? "#000000")
            // 同步更新 NativeCanvasView
            canvasView?.updatePenSettings(
                color: UIColor(newColor),
                width: viewModel.stateManager.penLineWidth
            )
        }
    ),
    penWidth: Binding(
        get: { viewModel.stateManager.penLineWidth },
        set: { newWidth in
            viewModel.stateManager.setPenLineWidth(newWidth)
            canvasView?.updatePenSettings(
                color: UIColor(Color(hex: viewModel.stateManager.penColor)),
                width: newWidth
            )
        }
    )
)
```

##### 6. 扩展 `Color+Hex.swift`

添加 Color 转 Hex 方法（如果没有）：

```swift
extension Color {
    /// 将 Color 转换为十六进制字符串
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }

        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
```

---

## 实施步骤

### 阶段一：修复清屏功能（预计 30 分钟）

1. 修改 `NativeCanvasView.swift` 的 `removeAllLayers()` 方法
2. 添加箭头和形状视图的清理逻辑
3. 测试清屏功能：
   - 创建多个箭头
   - 创建多个形状
   - 添加图片
   - 绘制笔画
   - 点击清屏，验证所有内容都被清除

### 阶段二：画笔工具优化（预计 2 小时）

1. **新增文件**：
   - 创建 `PenSettingsPopover.swift`

2. **修改状态管理**：
   - `CanvasStateManager.swift` 添加画笔属性

3. **更新工具栏**：
   - `CanvasTool.swift` 更新图标
   - `CanvasToolbar.swift` 添加 `PenToolButton`

4. **更新画布**：
   - `NativeCanvasView.swift` 支持动态画笔设置

5. **更新编辑器**：
   - `NativeEditorView.swift` 绑定数据流

6. **测试画笔功能**：
   - 点击画笔工具
   - 弹出设置面板
   - 调整线宽
   - 选择颜色
   - 绘制验证

---

## 测试用例

### 清屏功能测试

| 编号 | 测试步骤 | 预期结果 |
|------|---------|---------|
| TC-01 | 创建 3 个箭头 -> 清屏 | 所有箭头消失 |
| TC-02 | 创建 3 个形状 -> 清屏 | 所有形状消失 |
| TC-03 | 添加 2 张图片 -> 清屏 | 所有图片消失 |
| TC-04 | 绘制笔画 -> 清屏 | 所有笔画消失 |
| TC-05 | 混合操作（箭头+形状+图片+笔画）-> 清屏 | 画布完全空白 |
| TC-06 | 清屏后撤销 | 所有内容恢复（如果支持） |

### 画笔工具测试

| 编号 | 测试步骤 | 预期结果 |
|------|---------|---------|
| TC-07 | 未选中画笔时点击画笔按钮 | 切换到画笔工具 |
| TC-08 | 已选中画笔时点击画笔按钮 | 弹出设置面板 |
| TC-09 | 拖动线宽滑块 | 预览区实时显示线宽变化 |
| TC-10 | 点击预设颜色 | 颜色被选中，预览更新 |
| TC-11 | 使用系统取色器选择自定义颜色 | 自定义颜色生效 |
| TC-12 | 设置后绘制 | 笔画使用新的颜色和线宽 |
| TC-13 | 切换到其他工具后再切回画笔 | 保留之前的设置 |

---

## 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `NativeCanvasView.swift` | 修改 | 清屏修复 + 动态画笔 |
| `CanvasStateManager.swift` | 修改 | 新增画笔属性 |
| `CanvasTool.swift` | 修改 | 更新画笔图标 |
| `CanvasToolbar.swift` | 修改 | 新增 PenToolButton |
| `PenSettingsPopover.swift` | 新增 | 画笔设置弹窗 |
| `NativeEditorView.swift` | 修改 | 数据流绑定 |
| `Color+Hex.swift` | 修改 | 添加 toHex 方法 |

---

## 设计参考

### UI 风格一致性

本方案遵循现有的 UI 设计语言：
- **毛玻璃背景**：`.ultraThinMaterial`
- **圆角**：16pt（与 `ShapePickerPopover` 一致）
- **阴影**：`opacity: 0.12, radius: 16`
- **品牌色**：`Theme.Colors.brandBlue`
- **动画**：Spring 动画，`response: 0.25, dampingFraction: 0.8`

### 交互模式

与 `ShapePickerPopover` 保持一致：
- 弹出方向：`.bottom`（向上弹出）
- 关闭方式：点击外部自动关闭
- 选择后：立即生效，无需确认按钮

### 行业参考

- **Apple Notes**：简洁的笔触选择器
- **Procreate**：专业级画笔设置（可作为后续扩展参考）
- **Figma**：悬浮式属性面板

---

## 后续扩展建议

1. **笔触类型**：支持钢笔、马克笔、荧光笔等多种笔触
2. **压感支持**：Apple Pencil 压感映射
3. **收藏颜色**：用户自定义颜色收藏
4. **橡皮擦设置**：同样的模式添加橡皮擦大小选择

---

## 版本历史

| 版本 | 日期 | 作者 | 说明 |
|------|------|------|------|
| v1.0 | 2025-12-16 | Claude | 初始版本 |
