# 编辑器UI优化方案 v2.0

> 日期: 2025-12-17
> 状态: 设计完成，待开发
> 优先级: 高
> 前置文档: [editor_ui_optimization_v1.md](editor_ui_optimization_v1.md)

## 一、问题概述

本文档针对v1.0方案实施后仍存在的3个UI问题提供完整的优化改造方案：

| 序号 | 问题 | 严重程度 | 根本原因 |
|-----|-----|---------|---------|
| 1 | 资源库返回按钮样式廉价、不够优雅高级 | 高 | 样式设计缺乏质感，布局机械化 |
| 2 | 文生图弹窗提示词输入框被折叠不可见 | 高 | presentationDetents高度不足，ScrollView布局问题 |
| 3 | 图生图弹窗选区截图预览不显示 | 高 | 坐标转换问题 + 截图边界检查过严 |

---

## 二、问题1：资源库返回按钮样式优化

### 2.1 问题现状

**代码位置**: [NativeEditorView.swift:928-960](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift#L928-L960)

**当前实现**:
```swift
HStack(spacing: Theme.Spacing.md) {
    // 返回按钮
    Button {
        onClose()
    } label: {
        HStack(spacing: 4) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
            Text("返回")
                .font(.system(size: 16, weight: .medium))
        }
        .foregroundStyle(Theme.Colors.brandBlue)
    }
    .buttonStyle(.plain)

    Spacer()

    Text("资源库")
        .font(.headline)
        .foregroundStyle(Theme.Colors.primaryText)

    Spacer()

    // 占位符保持标题居中
    Color.clear
        .frame(width: 60)
}
.padding(.horizontal, Theme.Spacing.lg)
.padding(.vertical, Theme.Spacing.md)
.background(.regularMaterial)
```

**问题分析**:

1. **视觉层级感不足**（"廉价感"的根源）
   - 返回按钮与标题视觉权重不匹配
   - 纯色文字+图标组合显得生硬单薄
   - `.regularMaterial`背景缺乏深度感

2. **布局设计机械化**
   - 三个Spacer()对称布局显得呆板
   - 右侧`Color.clear`占位符是"代码味"的解决方案
   - 缺少右侧功能入口

3. **缺少交互反馈**
   - 按钮没有hover/press状态视觉反馈
   - 没有按钮活跃状态提示

### 2.2 业界参考

| 应用 | 侧边栏设计 | 返回方式 | 特点 |
|-----|----------|---------|------|
| Figma | 侧边栏无返回按钮 | 菜单/快捷键 | 最简化 |
| Procreate | 工具面板 | 手势/菜单 | 沉浸式 |
| Apple Notes | 分屏列表 | 侧滑手势 | 原生风格 |
| Adobe | 可折叠面板 | 面板控制 | 功能导向 |

**关键洞察**: 业界标杆iPad应用普遍**不在侧边栏放"返回"按钮**，而是依赖手势或顶部导航。

### 2.3 解决方案（推荐方案A）

**方案A: 精简高级设计**（改动适中，效果明显）

改进方向：
- 返回按钮加微妙背景，提升质感
- 右侧放功能菜单替代空白占位符
- 使用`.ultraThinMaterial`替代`.regularMaterial`
- 调整字体大小和权重建立清晰层级

**新布局效果**:
```
┌─────────────────────────────────┐
│ [< 返回]      资源库       [...]  │
├─────────────────────────────────┤
│ [生成图1]                        │
│ [生成图2]                        │
│ ...                             │
└─────────────────────────────────┘
```

### 2.4 实现代码

**位置**: [NativeEditorView.swift](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift) 中的 `NativeAssetLibraryView`

**替换第928-960行的header部分**:

```swift
var body: some View {
    VStack(spacing: 0) {
        // 精致的头部导航栏
        HStack(spacing: Theme.Spacing.lg) {
            // 返回按钮 - 轻量级设计，有微妙背景
            Button {
                onClose()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("返回")
                        .font(.system(size: 15, weight: .regular))
                }
                .foregroundStyle(Theme.Colors.brandBlue)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Theme.Colors.brandBlue.opacity(0.08))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            Spacer()

            // 标题 - 突出但不侵入
            Text("资源库")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.primaryText)

            Spacer()

            // 功能菜单 - 替代空白占位符
            Menu {
                Button("刷新", systemImage: "arrow.clockwise") {
                    // 预留：刷新资源列表
                }
                Divider()
                Button("清空资源库", systemImage: "trash", role: .destructive) {
                    // 预留：清空资源库
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial)

        Divider()

        // 资源列表保持不变...
    }
}
```

### 2.5 关键改动说明

| 改动项 | 原设计 | 新设计 | 效果 |
|-------|-------|-------|------|
| 返回按钮背景 | 无背景 | `brandBlue.opacity(0.08)` | 增加质感 |
| 返回按钮圆角 | 无 | `cornerRadius(8)` | 更现代 |
| 返回按钮padding | 无 | `8pt/12pt` | 触摸区域更大 |
| 右侧占位符 | `Color.clear` | 功能菜单 | 增加实用性 |
| 背景材质 | `.regularMaterial` | `.ultraThinMaterial` | 更轻盈通透 |
| 标题字体 | `.headline` | `.system(16, semibold)` | 更精确控制 |

### 2.6 备选方案B（更激进）

如果希望更国际化、更高端，可以完全移除返回按钮，依赖iOS原生侧滑手势返回：

```swift
HStack(spacing: Theme.Spacing.lg) {
    Text("资源库")
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(Theme.Colors.primaryText)

    Spacer()

    Menu {
        // 功能菜单...
    } label: {
        Image(systemName: "ellipsis.circle")
            .font(.system(size: 18))
            .foregroundStyle(Theme.Colors.secondaryText)
    }
    .buttonStyle(.plain)
}
```

**优点**: 更简洁、更国际范儿
**缺点**: 中文用户可能不习惯（需要知道侧滑可返回）

### 2.7 测试验证

| 测试项 | 预期结果 |
|-------|---------|
| 返回按钮样式 | 有微妙蓝色背景，圆角8pt |
| 返回按钮点击 | 编辑器正常关闭 |
| 菜单按钮显示 | 右侧显示省略号图标 |
| 菜单展开 | 点击显示"刷新"和"清空资源库"选项 |
| 整体视觉 | 背景通透，层级分明 |
| iPad适配 | 各尺寸显示正常 |

---

## 三、问题2：文生图弹窗提示词输入框优化

### 3.1 问题现状

**代码位置**: [TextToImageSheet.swift](src/MindCanvas/MindCanvas/Views/Editor/Sheets/TextToImageSheet.swift)

**当前实现问题**:
```swift
.presentationDetents([.medium])  // 只有.medium，高度不足
```

**问题分析**:

1. **`.medium`高度不足**
   - iPad上`.medium`约为屏幕50%（~512pt）
   - 需要容纳: Header(~70pt) + Tips(~90pt) + TextEditor(120pt) + Divider(1pt) + Actions(~50pt) + Padding(~96pt) = **427pt**
   - 实际ScrollView可用高度更小，TextEditor被压缩

2. **ScrollView贪心布局**
   - ScrollView会尽量收缩子视图高度
   - TextEditor在ScrollView内容区可能被压缩到不可见

3. **布局结构问题**
   - 整个内容区域都在ScrollView中
   - TextEditor应该独立出来

### 3.2 解决方案

**核心修复**:
1. `presentationDetents`改为`[.medium, .large]`
2. 重构布局：将TextEditor从ScrollView中独立出来
3. 限制Tips卡片的ScrollView高度

### 3.3 实现代码

**完全重写 TextToImageSheet.swift**:

```swift
import SwiftUI

struct TextToImageSheet: View {
    @State private var prompt: String = ""
    @FocusState private var isPromptFocused: Bool
    let onGenerate: (String, ImageAspectRatio) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部：Header（固定）
                header
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.xxl)
                    .padding(.bottom, Theme.Spacing.lg)

                Divider()

                // 中部：Tips卡片（可滚动，高度受限）
                ScrollView {
                    tipsSection
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.vertical, Theme.Spacing.lg)
                }
                .frame(maxHeight: 120)  // 限制Tips区域最大高度

                // 提示词输入区域（独立，不在ScrollView中）
                promptEditor
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.vertical, Theme.Spacing.lg)

                Divider()

                // 底部：按钮（固定）
                actions
                    .padding(Theme.Spacing.xxl)
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])  // 支持两种高度
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("文生图")
                    .font(Theme.Fonts.title3)
                    .foregroundStyle(Theme.Colors.primaryText)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Text("输入提示词直接生成图片素材")
                .font(Theme.Fonts.subheadline)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Tips Section
    private var tipsSection: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.brandBlue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("快速提示")
                    .font(Theme.Fonts.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.primaryText)

                Text("默认生成 1:1 正方形图片。可在提示词中指定尺寸，如\"1920x1080 宽屏\"或\"竖屏手机壁纸\"")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.brandBlue.opacity(0.08))
        .cornerRadius(Theme.Shapes.buttonCornerRadius)
    }

    // MARK: - Prompt Editor（独立于ScrollView）
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
        }
    }

    // MARK: - Actions
    private var actions: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button("取消", action: onCancel)
                .secondaryButtonStyle()

            Button {
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                onGenerate(trimmed, .square)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                    Text("确定生成")
                }
            }
            .primaryButtonStyle()
            .disabled(isGenerateDisabled)
            .opacity(isGenerateDisabled ? 0.5 : 1.0)
        }
    }

    private var isGenerateDisabled: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    TextToImageSheet(
        onGenerate: { prompt, ratio in
            print("Generate: \(prompt), ratio: \(ratio)")
        },
        onCancel: {
            print("Cancel")
        }
    )
}
```

### 3.4 关键改动说明

| 改动项 | 原设计 | 新设计 | 效果 |
|-------|-------|-------|------|
| presentationDetents | `[.medium]` | `[.medium, .large]` | 用户可调整高度 |
| ScrollView范围 | 包裹全部内容 | 仅包裹tipsSection | TextEditor不被压缩 |
| Tips区域高度 | 无限制 | `maxHeight: 120` | 为TextEditor留出空间 |
| TextEditor位置 | 在ScrollView内 | 独立出来 | 保证始终可见 |
| 焦点管理 | 无 | `@FocusState` | 边框颜色反馈 |
| 边框焦点状态 | 无变化 | 聚焦时蓝色加粗 | 清晰的交互反馈 |

### 3.5 测试验证

| 测试项 | 预期结果 |
|-------|---------|
| TextEditor可见性 | 弹窗打开时TextEditor完全可见，无需滚动 |
| 高度调整 | 拖拽indicator可在.medium和.large间切换 |
| 键盘弹出 | 弹出键盘后TextEditor保持可见 |
| 焦点反馈 | 点击TextEditor后边框变为蓝色 |
| 按钮状态 | 提示词为空时"确定生成"按钮半透明不可点击 |
| iPad各尺寸 | 12.9"/11"/10.9"均正常显示 |

---

## 四、问题3：图生图弹窗选区截图预览修复

### 4.1 问题现状

**相关代码位置**:
- [ImageToImageConfirmSheet.swift](src/MindCanvas/MindCanvas/Views/Editor/Sheets/ImageToImageConfirmSheet.swift)
- [NativeEditorViewModel.swift](src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift) - `prepareImageToImageFlow()`
- [NativeCanvasView.swift](src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift) - `captureContentSnapshot()`, `contentRect()`

**问题分析**:

1. **坐标转换可能错误**
   - MagicFrameView坐标是相对于GeometryReader的
   - `contentRect(forViewportRect:)`期望的是相对于NativeCanvasView的坐标
   - 可能存在偏差

2. **截图边界检查过严**
   ```swift
   guard !bounded.isNull, bounded.width > 1, bounded.height > 1 else {
       return nil
   }
   ```
   - 当contentRect部分越界时，交集可能很小
   - 用户在远处标记的小选框可能触发此条件

3. **预览图片传递问题**
   - `pendingImageToImagePreview`可能在Sheet显示前被清空
   - 或者根本没有成功捕获截图

### 4.2 解决方案

**分三步修复**:

1. **增加诊断日志**（快速定位问题）
2. **放宽截图边界条件**（修复边缘情况）
3. **优化预览区域尺寸**（改善显示效果）

### 4.3 实现代码

#### 步骤1: NativeEditorViewModel.swift 添加诊断日志

**位置**: `prepareImageToImageFlow()` 方法

```swift
func prepareImageToImageFlow() -> Bool {
    print("[ImageToImage] ===== Begin prepareImageToImageFlow =====")

    // 验证提示词
    let prompt = stateManager.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    print("[ImageToImage] prompt: \(prompt.isEmpty ? "(empty)" : prompt)")

    // 验证 Magic Frame 可见性
    guard stateManager.isMagicFrameVisible else {
        print("[ImageToImage] Error: Magic Frame not visible")
        flowHintMessage = "请先显示选框"
        return false
    }

    // 验证画布视图
    guard let canvasView = canvasView else {
        print("[ImageToImage] Error: canvasView is nil")
        flowHintMessage = "画布未就绪"
        return false
    }

    // 获取选框区域
    let viewportRect = stateManager.magicFrame
    print("[ImageToImage] viewportRect (magicFrame): \(viewportRect)")
    print("[ImageToImage] viewportRect size: \(viewportRect.width) x \(viewportRect.height)")

    // 转换为画布内容坐标
    let contentRect = canvasView.contentRect(forViewportRect: viewportRect)
    print("[ImageToImage] contentRect (after conversion): \(contentRect)")
    print("[ImageToImage] pencilCanvas.zoomScale: \(canvasView.pencilCanvas.zoomScale)")
    print("[ImageToImage] pencilCanvas.contentOffset: \(canvasView.pencilCanvas.contentOffset)")

    // 验证contentRect是否在合理范围内
    let canvasSize = canvasView.canvasSize
    print("[ImageToImage] canvasSize: \(canvasSize)")
    let isInBounds = contentRect.intersects(CGRect(origin: .zero, size: canvasSize))
    print("[ImageToImage] contentRect intersects canvas: \(isInBounds)")

    // 捕获截图
    guard let snapshot = canvasView.captureContentSnapshot(rect: contentRect) else {
        print("[ImageToImage] Error: Failed to capture snapshot")
        print("[ImageToImage] Possible reasons: contentRect out of bounds, or area too small")
        flowHintMessage = "截图失败，请确保选框内有内容"
        return false
    }

    print("[ImageToImage] Snapshot captured successfully!")
    print("[ImageToImage] Snapshot size: \(snapshot.size)")

    // 存储预览图
    pendingImageToImagePreview = snapshot
    pendingImageToImagePrompt = prompt

    print("[ImageToImage] ===== End prepareImageToImageFlow (success) =====")
    return true
}
```

#### 步骤2: NativeCanvasView.swift 增强截图方法

**位置**: `captureContentSnapshot(rect:)` 方法

```swift
func captureContentSnapshot(rect contentRect: CGRect) -> UIImage? {
    print("[Snapshot] ===== Begin captureContentSnapshot =====")
    print("[Snapshot] Input contentRect: \(contentRect)")
    print("[Snapshot] Canvas size: \(canvasSize)")
    print("[Snapshot] objectLayerView.subviews.count: \(objectLayerView.subviews.count)")

    // 扩大边界容差（从+-10扩大到+-100）
    let expandedCanvas = CGRect(
        x: -100,
        y: -100,
        width: canvasSize.width + 200,
        height: canvasSize.height + 200
    )
    let bounded = contentRect.intersection(expandedCanvas)

    print("[Snapshot] Expanded canvas bounds: \(expandedCanvas)")
    print("[Snapshot] Bounded rect (intersection): \(bounded)")

    // 放宽最小尺寸检查（从1pt放宽到10pt）
    guard !bounded.isNull, bounded.width >= 10, bounded.height >= 10 else {
        print("[Snapshot] Error: Invalid or too small rect")
        print("[Snapshot] bounded.isNull: \(bounded.isNull)")
        if !bounded.isNull {
            print("[Snapshot] bounded size: \(bounded.width) x \(bounded.height)")
        }
        return nil
    }

    let scale = UIScreen.main.scale
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false

    print("[Snapshot] Rendering with scale: \(scale)")
    print("[Snapshot] Final render size: \(bounded.size)")

    // 使用PencilKit导出笔画
    let drawingImage = pencilCanvas.drawing.image(from: bounded, scale: scale)
    print("[Snapshot] Drawing image size: \(drawingImage.size)")

    let renderer = UIGraphicsImageRenderer(size: bounded.size, format: format)
    let result = renderer.image { rendererContext in
        let ctx = rendererContext.cgContext

        // 白色背景
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: bounded.size))

        ctx.saveGState()
        ctx.translateBy(x: -bounded.origin.x, y: -bounded.origin.y)

        // 渲染对象层
        print("[Snapshot] Rendering objectLayerView at origin: \(-bounded.origin.x), \(-bounded.origin.y)")
        objectLayerView.layer.render(in: ctx)

        ctx.restoreGState()

        // 渲染笔画
        drawingImage.draw(in: CGRect(origin: .zero, size: bounded.size))
    }

    print("[Snapshot] ===== End captureContentSnapshot (success) =====")
    print("[Snapshot] Result image size: \(result.size)")
    return result
}
```

#### 步骤3: NativeCanvasView.swift 增强坐标转换

**位置**: `contentRect(forViewportRect:)` 方法

```swift
func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
    print("[Coordinate] ===== Begin contentRect conversion =====")
    print("[Coordinate] Input viewportRect: \(viewportRect)")

    // 从视口坐标转换到Canvas坐标
    let rectInCanvas = pencilCanvas.convert(viewportRect, from: self)
    print("[Coordinate] After convert (rectInCanvas): \(rectInCanvas)")

    // 获取缩放和偏移
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset
    print("[Coordinate] zoomScale: \(scale), contentOffset: \(offset)")

    // 应用缩放和偏移
    let result = CGRect(
        x: (rectInCanvas.origin.x + offset.x) / scale,
        y: (rectInCanvas.origin.y + offset.y) / scale,
        width: rectInCanvas.width / scale,
        height: rectInCanvas.height / scale
    )

    print("[Coordinate] Result contentRect: \(result)")
    print("[Coordinate] ===== End contentRect conversion =====")
    return result
}
```

#### 步骤4: ImageToImageConfirmSheet.swift 优化预览尺寸

```swift
import SwiftUI

struct ImageToImageConfirmSheet: View {
    let previewImage: UIImage
    let prompt: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let safeHeight = proxy.size.height
                // 更激进的尺寸计算：减去固定元素后，预览占60%
                let fixedElementsHeight: CGFloat = 280 // header + prompt + actions + padding
                let availableForPreview = max(200, safeHeight - fixedElementsHeight)
                let previewHeight = min(500, availableForPreview * 0.7)

                VStack(spacing: Theme.Spacing.lg) {
                    header

                    Divider()

                    // 预览区域
                    previewSection(height: previewHeight)

                    promptBlock

                    Spacer(minLength: Theme.Spacing.md)

                    actions
                }
                .padding(Theme.Spacing.xxl)
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("确认生成")
                    .font(Theme.Fonts.title3)
                    .foregroundStyle(Theme.Colors.primaryText)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            Text("请确认将作为参考的画布内容")
                .font(Theme.Fonts.subheadline)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Preview Section（优化尺寸）
    private func previewSection(height: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Text("选区预览")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                Spacer()
                // 显示预览图实际尺寸
                Text("\(Int(previewImage.size.width)) x \(Int(previewImage.size.height))")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.6))
            }

            // 预览图片
            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .background(
                    // 棋盘格背景，显示透明区域
                    CheckerboardPattern()
                        .foregroundStyle(Color.gray.opacity(0.1))
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        }
    }

    // MARK: - Prompt Block
    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("提示词")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            Text(prompt.isEmpty ? "无提示词" : prompt)
                .font(Theme.Fonts.body)
                .foregroundStyle(prompt.isEmpty ? Theme.Colors.secondaryText : Theme.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.appBackground)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
                .lineLimit(3)
        }
    }

    // MARK: - Actions
    private var actions: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button("取消", action: onCancel)
                .secondaryButtonStyle()

            Button {
                onConfirm()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                    Text("确认生成")
                }
            }
            .primaryButtonStyle()
        }
    }
}

// MARK: - 棋盘格背景（显示透明区域）
private struct CheckerboardPattern: View {
    var body: some View {
        GeometryReader { geo in
            let size: CGFloat = 10
            let rows = Int(ceil(geo.size.height / size))
            let cols = Int(ceil(geo.size.width / size))

            Canvas { context, _ in
                for row in 0..<rows {
                    for col in 0..<cols {
                        if (row + col) % 2 == 0 {
                            let rect = CGRect(
                                x: CGFloat(col) * size,
                                y: CGFloat(row) * size,
                                width: size,
                                height: size
                            )
                            context.fill(Path(rect), with: .foreground)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ImageToImageConfirmSheet(
        previewImage: UIImage(systemName: "photo")!,
        prompt: "a beautiful sunset",
        onConfirm: { print("Confirm") },
        onCancel: { print("Cancel") }
    )
}
```

### 4.4 关键改动说明

| 改动项 | 原设计 | 新设计 | 效果 |
|-------|-------|-------|------|
| 边界容差 | +-10pt | +-100pt | 允许更多越界情况 |
| 最小尺寸 | >1pt | >=10pt | 避免过小截图 |
| 预览高度计算 | `availableHeight * 0.35` | `(height - 280) * 0.7` | 更大预览区域 |
| 预览背景 | 纯灰色 | 棋盘格 | 显示透明区域 |
| 图片尺寸显示 | 无 | 右上角显示 | 信息更完整 |
| 调试日志 | 简单 | 详细完整 | 快速定位问题 |

### 4.5 调试排查流程

如果预览仍不显示，按以下顺序检查控制台日志：

1. **检查是否进入了截图流程**
   ```
   [ImageToImage] ===== Begin prepareImageToImageFlow =====
   ```
   如果没有此日志，说明未触发图生图流程

2. **检查Magic Frame可见性**
   ```
   [ImageToImage] Error: Magic Frame not visible
   ```
   需要先显示选框

3. **检查坐标转换结果**
   ```
   [Coordinate] Result contentRect: CGRect(...)
   ```
   如果坐标超出5000x5000范围，说明转换有问题

4. **检查截图边界**
   ```
   [Snapshot] Error: Invalid or too small rect
   ```
   说明截取区域过小或完全越界

5. **检查截图成功**
   ```
   [Snapshot] Result image size: ...
   ```
   如果有此日志但预览仍不显示，说明是传递问题

### 4.6 测试验证

| 测试项 | 预期结果 |
|-------|---------|
| 正常选框截图 | 预览区显示选框内的画布内容 |
| 小选框(100x100) | 能成功截图并显示 |
| 边缘选框 | 部分越界也能截图 |
| 空白区域 | 显示白色背景 |
| 预览尺寸 | 至少200pt高，充分展示内容 |
| 图片尺寸显示 | 右上角显示实际像素尺寸 |

---

## 五、实施计划

### 5.1 优先级排序

| 优先级 | 任务 | 预计时间 | 依赖 |
|-------|-----|---------|-----|
| P0 | 修复文生图弹窗presentationDetents | 5分钟 | 无 |
| P0 | 图生图添加诊断日志 | 15分钟 | 无 |
| P1 | 重构文生图弹窗布局 | 30分钟 | P0 |
| P1 | 放宽图生图截图边界条件 | 20分钟 | P0 |
| P1 | 优化资源库header样式 | 30分钟 | 无 |
| P2 | 优化图生图预览区域尺寸 | 20分钟 | P1 |
| P3 | 移除调试日志(生产环境) | 10分钟 | 验证通过后 |

### 5.2 建议执行顺序

```
1. 先执行P0任务（快速修复）
   - 修改TextToImageSheet.swift第28行
   - 添加图生图诊断日志

2. 在真机上运行测试
   - 确认文生图输入框可见
   - 查看图生图控制台日志

3. 根据日志结果执行P1任务
   - 如果坐标转换有问题，先修复坐标转换
   - 如果边界检查过严，放宽边界条件

4. 完成资源库header优化

5. 最后执行P2任务优化预览尺寸
```

---

## 六、修改文件清单

| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| [NativeEditorView.swift](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift) | 修改 | 资源库header样式优化 |
| [TextToImageSheet.swift](src/MindCanvas/MindCanvas/Views/Editor/Sheets/TextToImageSheet.swift) | 重写 | 修复输入框折叠，优化布局 |
| [ImageToImageConfirmSheet.swift](src/MindCanvas/MindCanvas/Views/Editor/Sheets/ImageToImageConfirmSheet.swift) | 修改 | 优化预览尺寸，添加棋盘格背景 |
| [NativeEditorViewModel.swift](src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift) | 修改 | 添加图生图诊断日志 |
| [NativeCanvasView.swift](src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift) | 修改 | 放宽截图边界，增强日志 |

---

## 七、验收标准

### 7.1 功能验收

- [ ] 资源库返回按钮有微妙蓝色背景，视觉更高级
- [ ] 资源库右侧显示功能菜单图标
- [ ] 文生图弹窗打开时TextEditor完全可见
- [ ] 文生图弹窗支持.medium和.large两种高度
- [ ] 图生图弹窗预览区显示选框截图内容
- [ ] 图生图弹窗预览区大小合适（至少200pt高）

### 7.2 视觉验收

- [ ] 资源库header背景通透（ultraThinMaterial）
- [ ] 返回按钮有圆角和微妙背景
- [ ] 文生图TextEditor有焦点状态视觉反馈
- [ ] 图生图预览区有棋盘格背景显示透明

### 7.3 交互验收

- [ ] 点击返回按钮正常关闭编辑器
- [ ] 功能菜单可正常展开和操作
- [ ] 拖拽弹窗indicator可调整高度
- [ ] 键盘弹出时布局正常

---

## 八、注意事项

1. **关于调试日志**
   - 诊断日志仅用于开发调试
   - 问题解决后需移除或用编译标志包裹（`#if DEBUG`）

2. **关于坐标系统**
   - MagicFrameView坐标是相对于容器的
   - 需要正确转换到画布内容坐标
   - 注意缩放和偏移的计算顺序

3. **关于截图边界**
   - 扩大容差可能导致截取到画布外的空白
   - 这是可接受的，比截图失败更好

4. **关于测试设备**
   - 务必在真机上测试图生图功能
   - 模拟器可能有不同的行为

---

## 九、参考资料

- [Apple Human Interface Guidelines - Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [SwiftUI presentationDetents](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:))
- [PencilKit Drawing Export](https://developer.apple.com/documentation/pencilkit/pkdrawing/image(from:scale:))
- 项目前置文档: [editor_ui_optimization_v1.md](editor_ui_optimization_v1.md)
