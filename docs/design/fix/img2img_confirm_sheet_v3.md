# 图生图确认弹窗优化方案 v3.0

> 日期: 2025-12-17
> 状态: 设计完成，待开发
> 优先级: 高
> 前置文档: [editor_ui_optimization_v2.md](editor_ui_optimization_v2.md)

## 一、问题概述

基于真机测试截图，发现图生图确认弹窗（ImageToImageConfirmSheet）存在以下问题：

| 序号 | 问题 | 严重程度 | 截图证据 |
|-----|-----|---------|---------|
| 1 | 预览图没有显示画布内容（用户画的"123"未出现） | 严重 | 预览区显示空白棋盘格背景，右上角显示"537 x 405" |
| 2 | 弹窗高度固定不足，提示词和按钮被挤出视野 | 严重 | 弹窗底部被截断，"取消"和"确认生成"按钮不可见 |
| 3 | 预览区域太小 | 中等 | 预览区占比偏低，视觉效果不理想 |
| 4 | 缺少点击放大功能 | 中等 | 无法查看预览图细节 |

### 截图分析

从截图可见：
- 画布上用户绘制了"123"字样，被蓝色选框框住
- 图生图弹窗标题显示"确认生成"
- 预览区域标签"选区预览"和尺寸"537 x 405"都正常显示
- **但预览图内容为空白**（只有棋盘格背景，没有"123"）
- 提示词区域显示"123"（这是正确的）
- **按钮区域完全不可见**（被挤出视野）

---

## 二、问题1：预览图未显示画布内容

### 2.1 根本原因分析

预览图显示空白，但尺寸"537 x 405"是有值的，说明截图函数确实返回了图片，但图片内容不正确。

**可能原因（按可能性排序）**：

1. **坐标转换问题**（最可能）
   - `contentRect(forViewportRect:)` 坐标转换逻辑可能有问题
   - MagicFrame 的坐标系与画布内容坐标系存在偏差
   - 缩放/偏移计算顺序可能错误

2. **渲染顺序问题**
   - `captureContentSnapshot()` 先渲染白色背景，可能覆盖了对象层
   - PencilKit 笔画渲染在错误的区域

3. **视图层级问题**
   - `objectLayerView.layer.render(in:)` 可能没有正确渲染笔画
   - PencilKit 内容不在 `objectLayerView` 中，需要单独导出

### 2.2 代码审查

查看 `NativeCanvasView.swift` 中的关键方法：

```swift
// 坐标转换
func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
    let rectInCanvas = pencilCanvas.convert(viewportRect, from: self)
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset

    let result = CGRect(
        x: (rectInCanvas.origin.x + offset.x) / scale,
        y: (rectInCanvas.origin.y + offset.y) / scale,
        width: rectInCanvas.width / scale,
        height: rectInCanvas.height / scale
    )
    return result
}

// 截图
func captureContentSnapshot(rect contentRect: CGRect) -> UIImage? {
    // ... 边界检查
    let drawingImage = pencilCanvas.drawing.image(from: bounded, scale: scale)

    let renderer = UIGraphicsImageRenderer(size: bounded.size, format: format)
    let result = renderer.image { rendererContext in
        let ctx = rendererContext.cgContext

        // 白色背景
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: bounded.size))

        ctx.saveGState()
        ctx.translateBy(x: -bounded.origin.x, y: -bounded.origin.y)
        objectLayerView.layer.render(in: ctx)  // 渲染对象层
        ctx.restoreGState()

        drawingImage.draw(in: CGRect(origin: .zero, size: bounded.size))  // 渲染笔画
    }
    return result
}
```

**问题发现**：
- 笔画渲染使用 `drawingImage.draw(in:)` 是正确的
- 但 `pencilCanvas.drawing.image(from: bounded, scale:)` 依赖正确的 `bounded` 坐标
- 如果 `bounded` 坐标偏移到画布外的空白区域，返回的就是空白图片

### 2.3 解决方案

**方案A：修复坐标转换逻辑**

坐标转换公式可能有误。正确的逻辑应该是：

```swift
func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
    // 1. 先将视口坐标转换为 pencilCanvas 本地坐标
    let rectInCanvas = pencilCanvas.convert(viewportRect, from: self)

    // 2. 考虑 PKCanvasView 的 contentOffset 和 zoomScale
    // PKCanvasView 继承自 UIScrollView，其坐标系统：
    // - contentOffset 表示滚动偏移
    // - zoomScale 表示缩放比例
    // 画布内容坐标 = (视口坐标 + contentOffset) / zoomScale

    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset

    // 修正：直接使用转换后的坐标，因为 convert 已经考虑了变换
    // 但我们需要的是"画布内容坐标"，不是"视口坐标"

    // 正确计算：从视口坐标到画布内容坐标
    let contentOriginX = (viewportRect.origin.x - pencilCanvas.frame.origin.x + offset.x) / scale
    let contentOriginY = (viewportRect.origin.y - pencilCanvas.frame.origin.y + offset.y) / scale
    let contentWidth = viewportRect.width / scale
    let contentHeight = viewportRect.height / scale

    return CGRect(
        x: contentOriginX,
        y: contentOriginY,
        width: contentWidth,
        height: contentHeight
    )
}
```

**方案B：使用更直接的截图方法**

绕过复杂的坐标转换，直接截取视图层级：

```swift
func captureContentSnapshot(rect viewportRect: CGRect) -> UIImage? {
    // 直接从 self（NativeCanvasView）截图
    let renderer = UIGraphicsImageRenderer(size: viewportRect.size)
    return renderer.image { context in
        // 平移上下文到截图区域
        context.cgContext.translateBy(x: -viewportRect.origin.x, y: -viewportRect.origin.y)
        // 渲染整个视图层级
        self.layer.render(in: context.cgContext)
    }
}
```

### 2.4 实现建议

**推荐方案B**，因为：
1. 代码更简单，不需要复杂的坐标转换
2. 渲染整个视图层级，确保所有内容都被捕获
3. 避免 PencilKit 和对象层分别渲染的问题

**实现步骤**：

1. 在 `NativeCanvasView.swift` 中添加新方法：

```swift
/// 直接截取视口区域的快照（简化版）
func captureViewportSnapshotSimple(rect viewportRect: CGRect) -> UIImage? {
    print("[Snapshot-Simple] ===== Begin =====")
    print("[Snapshot-Simple] viewportRect: \(viewportRect)")

    guard viewportRect.width >= 10, viewportRect.height >= 10 else {
        print("[Snapshot-Simple] Error: rect too small")
        return nil
    }

    let scale = UIScreen.main.scale
    let renderer = UIGraphicsImageRenderer(size: viewportRect.size, format: {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = scale
        fmt.opaque = false
        return fmt
    }())

    let result = renderer.image { context in
        // 平移上下文
        context.cgContext.translateBy(x: -viewportRect.origin.x, y: -viewportRect.origin.y)

        // 渲染 pencilCanvas（包含笔画）
        pencilCanvas.layer.render(in: context.cgContext)

        // 渲染 overlayContainerView（包含对象层）
        overlayContainerView.layer.render(in: context.cgContext)
    }

    print("[Snapshot-Simple] Result size: \(result.size)")
    print("[Snapshot-Simple] ===== End =====")
    return result
}
```

2. 修改 `NativeEditorViewModel.swift` 的 `prepareImageToImageFlow()`：

```swift
// 修改：使用简化版截图方法
let viewportRect = stateManager.magicFrame
guard let snapshot = canvasView.captureViewportSnapshotSimple(rect: viewportRect),
      let imageData = snapshot.pngData() else {
    // ...
}
```

---

## 三、问题2+3：弹窗高度和预览尺寸优化

### 3.1 问题分析

当前实现：
```swift
.presentationDetents([.medium, .large])
```

问题：
- `.medium` 约为屏幕50%，在iPad上可能不够
- 布局使用 `VStack`，当内容超出时会被截断
- `fixedElementsHeight: CGFloat = 280` 估算不准确

### 3.2 解决方案

**完全重构 ImageToImageConfirmSheet.swift**

设计理念：
- 使用 `.large` 作为默认，提供充足空间
- 预览区域自适应，占据主要空间
- 底部按钮固定，始终可见
- 支持点击预览图放大查看

### 3.3 新布局结构

```
┌─────────────────────────────────────┐
│ 确认生成                         × │  <- Header (固定 ~80pt)
│ 请确认将作为参考的画布内容           │
├─────────────────────────────────────┤
│                                     │
│      ┌─────────────────────┐        │
│      │                     │        │
│      │   (预览图区域)       │        │  <- 预览区 (弹性)
│      │   点击放大查看       │        │       最小高度: 250pt
│      │                     │        │       最大高度: 屏幕60%
│      └─────────────────────┘        │
│      选区预览              537x405   │
│                                     │
├─────────────────────────────────────┤
│ 提示词                              │  <- 提示词 (固定 ~60pt)
│ ┌─────────────────────────────────┐ │
│ │ 123                             │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│   [  取消  ]    [  确认生成  ]      │  <- 按钮 (固定 ~70pt)
└─────────────────────────────────────┘
```

### 3.4 实现代码

```swift
import SwiftUI

struct ImageToImageConfirmSheet: View {
    let previewImage: UIImage
    let prompt: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var showFullscreenPreview = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let safeHeight = proxy.size.height
                let safeWidth = proxy.size.width

                // 动态计算预览高度
                // Header: ~80pt, PromptBlock: ~100pt, Actions: ~90pt, Padding: ~48pt
                let fixedHeight: CGFloat = 318
                let availableHeight = max(250, safeHeight - fixedHeight)
                let previewMaxHeight = min(safeHeight * 0.55, availableHeight)

                VStack(spacing: 0) {
                    // Header
                    header
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.md)

                    Divider()

                    // 中间区域（弹性）
                    ScrollView {
                        VStack(spacing: Theme.Spacing.lg) {
                            // 预览区域
                            previewSection(
                                maxHeight: previewMaxHeight,
                                containerWidth: safeWidth - Theme.Spacing.xxl * 2
                            )

                            // 提示词区域
                            promptBlock
                        }
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.vertical, Theme.Spacing.lg)
                    }

                    Divider()

                    // 底部按钮（固定）
                    actions
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.vertical, Theme.Spacing.lg)
                }
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.large])  // 固定使用 large
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showFullscreenPreview) {
            FullscreenImagePreview(
                image: previewImage,
                onDismiss: { showFullscreenPreview = false }
            )
        }
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
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            Text("请确认将作为参考的画布内容")
                .font(Theme.Fonts.subheadline)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Preview Section
    private func previewSection(maxHeight: CGFloat, containerWidth: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            // 预览图片（可点击放大）
            Button {
                showFullscreenPreview = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    // 棋盘格背景 + 图片
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: containerWidth, maxHeight: maxHeight)
                        .background(
                            CheckerboardPattern()
                                .foregroundStyle(Color.gray.opacity(0.1))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)

                    // 放大提示图标
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(Theme.Spacing.md)
                }
            }
            .buttonStyle(.plain)

            // 标签行
            HStack {
                Text("选区预览")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Spacer()

                // 点击提示
                Text("点击放大查看")
                    .font(Theme.Fonts.caption2)
                    .foregroundStyle(Theme.Colors.brandBlue)

                Spacer()

                // 图片尺寸
                Text("\(Int(previewImage.size.width)) x \(Int(previewImage.size.height))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.6))
            }
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
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.appBackground)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
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

// MARK: - 全屏预览视图
struct FullscreenImagePreview: View {
    let image: UIImage
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // 半透明背景
                Color.black.opacity(0.9)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }

                // 图片
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 0.5), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1.0 {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.0
                            }
                        }
                    }

                // 关闭按钮
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(Theme.Spacing.xl)
                    }
                    Spacer()
                }

                // 底部信息
                VStack {
                    Spacer()
                    HStack {
                        Text("双指缩放 | 双击重置 | 点击背景关闭")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.bottom, Theme.Spacing.xxl)
                }
            }
        }
    }
}

// MARK: - 棋盘格背景
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
        previewImage: UIImage(systemName: "photo.artframe")!,
        prompt: "一只可爱的猫咪在草地上玩耍",
        onConfirm: { print("Confirm") },
        onCancel: { print("Cancel") }
    )
}
```

---

## 四、关键改动说明

### 4.1 截图方法修复

| 改动项 | 原实现 | 新实现 | 效果 |
|-------|-------|-------|------|
| 截图方式 | 分别渲染对象层和笔画层 | 直接渲染整个视图层级 | 避免坐标转换问题 |
| 坐标系统 | 复杂的内容坐标转换 | 使用视口坐标直接截图 | 简化逻辑，减少bug |

### 4.2 弹窗布局优化

| 改动项 | 原实现 | 新实现 | 效果 |
|-------|-------|-------|------|
| presentationDetents | `[.medium, .large]` | `[.large]` | 固定大尺寸，避免内容被截断 |
| 布局结构 | 单一 VStack | Header + ScrollView + 固定 Actions | 按钮始终可见 |
| 预览高度 | `min(500, availableHeight * 0.7)` | `min(screenHeight * 0.55, availableHeight)` | 更大的预览区域 |

### 4.3 新增功能

| 功能 | 实现方式 | 效果 |
|-----|---------|------|
| 点击放大预览 | `fullScreenCover` + `FullscreenImagePreview` | 全屏查看预览图细节 |
| 手势交互 | 双指缩放 + 拖动 + 双击重置 | 便捷的图片浏览体验 |
| 视觉提示 | 右下角放大图标 + "点击放大查看"文字 | 引导用户操作 |

---

## 五、修改文件清单

| 文件 | 修改类型 | 说明 |
|-----|---------|------|
| [NativeCanvasView.swift](../../../src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift) | 新增方法 | 添加 `captureViewportSnapshotSimple()` |
| [NativeEditorViewModel.swift](../../../src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift) | 修改 | 修改 `prepareImageToImageFlow()` 使用新截图方法 |
| [ImageToImageConfirmSheet.swift](../../../src/MindCanvas/MindCanvas/Views/Editor/Sheets/ImageToImageConfirmSheet.swift) | 重写 | 新布局 + 点击放大功能 |

---

## 六、实施步骤

### 第一步：修复截图问题 (P0)

1. 在 `NativeCanvasView.swift` 中添加新的截图方法 `captureViewportSnapshotSimple()`
2. 修改 `NativeEditorViewModel.swift` 使用新方法
3. 测试验证预览图是否正确显示画布内容

### 第二步：重构弹窗布局 (P0)

1. 完全重写 `ImageToImageConfirmSheet.swift`
2. 实现新的布局结构（Header + ScrollView + 固定 Actions）
3. 测试验证按钮始终可见

### 第三步：添加点击放大功能 (P1)

1. 实现 `FullscreenImagePreview` 视图
2. 添加手势交互（缩放、拖动、双击重置）
3. 测试验证全屏预览功能

---

## 七、验收标准

### 7.1 功能验收

- [ ] 预览图正确显示画布选框内的内容（包括笔画）
- [ ] 弹窗打开时"取消"和"确认生成"按钮可见
- [ ] 预览区域足够大（至少占弹窗高度的50%）
- [ ] 点击预览图可进入全屏查看模式
- [ ] 全屏模式支持双指缩放和拖动
- [ ] 全屏模式支持双击重置缩放
- [ ] 点击背景或X按钮可退出全屏模式

### 7.2 视觉验收

- [ ] 预览图有棋盘格背景显示透明区域
- [ ] 预览图有阴影和圆角，视觉效果精致
- [ ] 放大图标位于预览图右下角
- [ ] "点击放大查看"提示文字清晰可见
- [ ] 全屏模式有半透明黑色背景
- [ ] 全屏模式有操作提示文字

### 7.3 交互验收

- [ ] 点击预览图响应流畅
- [ ] 缩放手势响应灵敏
- [ ] 拖动手势流畅自然
- [ ] 双击重置动画平滑

---

## 八、注意事项

1. **截图方法选择**
   - 优先使用新的 `captureViewportSnapshotSimple()` 方法
   - 如果仍有问题，检查 MagicFrame 的坐标是否相对于正确的父视图

2. **内存管理**
   - 大图片可能占用较多内存
   - 全屏预览关闭时确保释放资源

3. **iPad 适配**
   - 测试不同 iPad 尺寸（12.9"/11"/10.9"）
   - 确保布局在各种屏幕尺寸下正常显示

4. **调试日志**
   - 新增方法需添加详细日志
   - 便于定位问题

---

## 九、参考资料

- [Apple HIG - Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [SwiftUI fullScreenCover](https://developer.apple.com/documentation/swiftui/view/fullscreencover(ispresented:ondismiss:content:))
- [PencilKit Drawing Export](https://developer.apple.com/documentation/pencilkit/pkdrawing/image(from:scale:))
