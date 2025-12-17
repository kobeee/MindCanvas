# 编辑器UI优化方案 v1.0

> 日期: 2025-12-17
> 状态: 设计完成，待开发
> 优先级: 高

## 一、问题概述

本文档针对编辑器界面存在的4个UI问题提供完整的优化改造方案：

| 序号 | 问题 | 严重程度 | 影响范围 |
|-----|-----|---------|---------|
| 1 | 关闭按钮遮挡"资源库"文字 | 中 | 视觉体验 |
| 2 | 资源库+号按钮冗余 | 低 | 界面简洁度 |
| 3 | 文生图弹窗UI丑陋 | 高 | 用户体验 |
| 4 | 图生图弹窗多个问题 | 高 | 功能可用性 |

---

## 二、问题1：关闭按钮遮挡资源库文字

### 2.1 问题现状

**代码位置**: [NativeEditorView.swift:99-113](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift#L99-L113)

```swift
.overlay(alignment: .topLeading) {
    Button {
        dismiss()
    } label: {
        Image(systemName: "xmark.circle.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .background(
                Circle()
                    .fill(.black.opacity(0.3))
                    .frame(width: 32, height: 32)
            )
    }
    .padding()
}
```

**问题分析**:
- 使用 `.overlay(alignment: .topLeading)` 直接放在主 HStack 上
- 关闭按钮（32pt + padding）与"资源库"标题重叠
- 固定在左上角，无论屏幕大小都遮挡标题

### 2.2 解决方案（推荐方案A）

**方案A: 将关闭按钮集成到资源库头部（推荐）**

将"关闭"功能改为"返回"按钮，集成到资源库面板的头部导航栏中。

**优势**:
- 改动最小，快速解决遮挡问题
- 符合iPad编辑器习惯（Figma、Procreate等）
- 与资源库功能逻辑相关，用户直观

**界面效果**:
```
┌─────────────────────────────────┐
│ < 返回        资源库             │  <- 专用导航栏
├─────────────────────────────────┤
│ [生成图1]                        │
│ [生成图2]                        │
│ ...                             │
└─────────────────────────────────┘
```

### 2.3 实现步骤

#### 步骤1: 修改 NativeAssetLibraryView 结构体

**文件**: [NativeEditorView.swift](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift)

在 `NativeAssetLibraryView` 结构体中添加关闭回调参数和新的头部布局：

```swift
private struct NativeAssetLibraryView: View {
    // 现有参数保持不变
    let assets: [Asset]
    @Binding var selectedAsset: Asset?
    let onDelete: (Asset) -> Void
    let onImport: (Data) -> Void

    // 新增参数
    let onClose: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            // 新的头部导航栏
            header

            Divider()

            // 原有的资源列表内容保持不变
            assetList
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    onImport(data)
                }
            }
            selectedPhotoItem = nil
        }
    }

    // 新的头部导航栏
    private var header: some View {
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

            // 占位符保持居中（可选：移除+号后用 Color.clear 占位）
            Color.clear
                .frame(width: 60)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.regularMaterial)
    }

    // 资源列表（原有代码）
    private var assetList: some View {
        // ... 原有的 ScrollView + LazyVGrid 代码保持不变
    }
}
```

#### 步骤2: 移除全局 overlay

**位置**: [NativeEditorView.swift:99-113](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift#L99-L113)

删除以下代码块：

```swift
// 删除整个 overlay
.overlay(alignment: .topLeading) {
    Button {
        dismiss()
    } label: {
        Image(systemName: "xmark.circle.fill")
            .font(.title2)
            .foregroundStyle(.white)
            .background(
                Circle()
                    .fill(.black.opacity(0.3))
                    .frame(width: 32, height: 32)
            )
    }
    .padding()
}
```

#### 步骤3: 更新 NativeAssetLibraryView 调用处

**位置**: [NativeEditorView.swift](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift) 中的 body

```swift
NativeAssetLibraryView(
    assets: viewModel.assets,
    selectedAsset: $viewModel.selectedAsset,
    onDelete: { asset in
        Task { await viewModel.deleteAsset(asset) }
    },
    onImport: { data in
        Task { await viewModel.importImage(data) }
    },
    onClose: { dismiss() }  // 新增
)
.frame(width: 300)
```

### 2.4 测试验证

| 测试项 | 预期结果 |
|-------|---------|
| 返回按钮显示 | 左上角显示"< 返回"按钮，样式为蓝色 |
| 资源库标题 | 标题"资源库"居中显示，不被遮挡 |
| 返回功能 | 点击返回按钮，编辑器关闭，返回项目列表 |
| iPad各尺寸适配 | 12.9"、11"、10.9"均正常显示 |

---

## 三、问题2：移除资源库+号按钮

### 3.1 问题现状

**代码位置**: [NativeEditorView.swift:946-953](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift#L946-L953)

```swift
PhotosPicker(
    selection: $selectedPhotoItem,
    matching: .images
) {
    Image(systemName: "plus.circle.fill")
        .font(.title3)
}
```

**功能分析**:
- 此按钮用于从相册导入图片
- 底部工具栏的图片工具已完全覆盖此功能（且额外支持拍照）
- 两者最终都调用同一个 `viewModel.importImage()` 方法

### 3.2 解决方案

直接移除+号按钮，保留底部工具栏的图片工具作为唯一入口。

### 3.3 实现步骤

#### 步骤1: 移除 PhotosPicker 代码

**位置**: [NativeEditorView.swift:946-953](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift#L946-L953)

删除以下代码：

```swift
// 删除
PhotosPicker(
    selection: $selectedPhotoItem,
    matching: .images
) {
    Image(systemName: "plus.circle.fill")
        .font(.title3)
}
```

#### 步骤2: 调整头部布局

由于移除了+号按钮，头部需要调整为只有"返回"和"资源库"：

```swift
private var header: some View {
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
}
```

#### 步骤3: 移除相关状态变量（可选）

如果 `selectedPhotoItem` 状态变量没有其他用途，可以移除：

```swift
// 如果确认无其他引用，可移除
@State private var selectedPhotoItem: PhotosPickerItem?
```

以及对应的 `.onChange` 处理：

```swift
// 如果确认无其他引用，可移除
.onChange(of: selectedPhotoItem) { _, newItem in
    // ...
}
```

### 3.4 测试验证

| 测试项 | 预期结果 |
|-------|---------|
| +号按钮消失 | 资源库面板头部不再显示+号按钮 |
| 底部图片工具 | 点击底部工具栏图片图标，弹出来源选择浮窗 |
| 图片导入功能 | 从相册/拍照导入图片后，资源库显示新图片 |

---

## 四、问题3：文生图弹窗UI优化

### 4.1 问题现状

**代码位置**: [TextToImageSheet.swift](src/MindCanvas/MindCanvas/Views/Editor/Sheets/TextToImageSheet.swift)

**现有问题**:
1. 尺寸选择器（5个按钮的网格）占用大量空间且不美观
2. 缺少上方说明文字和使用提示
3. 没有"确定生成"按钮（只有"生成资源"）
4. 整体视觉不够精致

### 4.2 解决方案

重构文生图弹窗，采用简洁友好的设计：

**新布局结构**:
```
┌─────────────────────────────────────┐
│ 文生图                           ×  │ <- header
├─────────────────────────────────────┤
│ 输入提示词直接生成图片素材            │ <- 说明文字
├─────────────────────────────────────┤
│ ┌─────────────────────────────────┐ │
│ │ i  快速提示                      │ │ <- Tips卡片
│ │    默认生成1:1正方形图片。        │ │
│ │    可在提示词中指定尺寸...        │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ 提示词                              │
│ ┌─────────────────────────────────┐ │
│ │                                 │ │ <- TextEditor
│ │                                 │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│     [取消]      [确定生成]           │ <- 按钮
└─────────────────────────────────────┘
```

### 4.3 实现步骤

#### 步骤1: 重写 TextToImageSheet

**文件**: [TextToImageSheet.swift](src/MindCanvas/MindCanvas/Views/Editor/Sheets/TextToImageSheet.swift)

```swift
import SwiftUI

struct TextToImageSheet: View {
    @State private var prompt: String = ""
    let onGenerate: (String, ImageAspectRatio) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        header
                        tipsSection
                        promptEditor
                    }
                    .padding(Theme.Spacing.xxl)
                }

                Divider()

                actions
                    .padding(Theme.Spacing.xxl)
                    .padding(.bottom, Theme.Spacing.lg)
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium])
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

    // MARK: - Prompt Editor
    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("提示词")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            TextEditor(text: $prompt)
                .frame(height: 120)
                .padding(Theme.Spacing.md)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.appBackground)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
    }

    // MARK: - Actions
    private var actions: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button("取消", action: onCancel)
                .frame(maxWidth: .infinity, minHeight: Theme.Sizes.buttonHeight)
                .background(Theme.Colors.cardBackground)
                .foregroundColor(Theme.Colors.brandBlue)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .stroke(Theme.Colors.brandBlue.opacity(0.3), lineWidth: 1)
                )
                .font(Theme.Fonts.bodyBold)

            Button {
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                onGenerate(trimmed, .square)  // 默认使用 1:1
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                    Text("确定生成")
                }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Sizes.buttonHeight)
            .background(isGenerateDisabled ? Theme.Colors.brandBlue.opacity(0.5) : Theme.Colors.brandBlue)
            .foregroundColor(.white)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            .font(Theme.Fonts.bodyBold)
            .disabled(isGenerateDisabled)
        }
    }

    private var isGenerateDisabled: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Preview
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

### 4.4 关键改动说明

| 改动项 | 原设计 | 新设计 |
|-------|-------|-------|
| 尺寸选择器 | 5个按钮的网格 | 移除，使用默认1:1 |
| 说明文字 | 无 | 添加副标题说明用途 |
| Tips提示 | 无 | 添加蓝色提示卡片 |
| 生成按钮 | "生成资源" | "确定生成"（带图标） |
| 按钮样式 | 大小可能不一致 | 统一使用 maxWidth + minHeight |

### 4.5 测试验证

| 测试项 | 预期结果 |
|-------|---------|
| 弹窗显示 | 弹窗以半屏形式显示，有拖拽指示器 |
| 说明文字 | 标题下方显示"输入提示词直接生成图片素材" |
| Tips卡片 | 显示蓝色背景的提示卡片，内容清晰可读 |
| 提示词输入 | TextEditor可正常输入，高度120pt |
| 按钮状态 | 提示词为空时，"确定生成"按钮置灰不可点击 |
| 按钮大小 | 两个按钮高度一致，宽度平均分配 |
| 生成功能 | 点击"确定生成"后，使用默认1:1比例调用回调 |

---

## 五、问题4：图生图弹窗修复

### 5.1 问题现状

**代码位置**: [ImageToImageConfirmSheet.swift](src/MindCanvas/MindCanvas/Views/Editor/Sheets/ImageToImageConfirmSheet.swift)

**现有问题**:
1. "取消"和"确认生成"按钮大小不一致
2. 选框内容不显示（可能存在bug）
3. 预览区域太小（固定320pt高度）

### 5.2 问题分析

#### 问题4.1: 按钮大小不一致

**原因**:
- "取消"按钮使用纯文字
- "确认生成"按钮使用 `Label`（图标+文字）
- 虽然都应用了 `primaryButtonStyle/secondaryButtonStyle`，但内容类型不同导致布局差异

**当前代码** [ImageToImageConfirmSheet.swift:79-91](src/MindCanvas/MindCanvas/Views/Editor/Sheets/ImageToImageConfirmSheet.swift#L79-L91):
```swift
private var actions: some View {
    HStack(spacing: Theme.Spacing.lg) {
        Button("取消", action: onCancel)
            .secondaryButtonStyle()

        Button {
            onConfirm()
        } label: {
            Label("确认生成", systemImage: "wand.and.stars")
        }
        .primaryButtonStyle()
    }
}
```

#### 问题4.2: 选框内容不显示

**可能原因**:
1. 坐标转换问题：MagicFrameView坐标与画布坐标转换错误
2. 截图边界检查过严：contentRect可能超出画布范围导致返回nil
3. 渲染层级问题：objectLayerView可能为空或渲染失败

**相关代码**:
- [NativeEditorViewModel.swift:204-206](src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift#L204-L206) - 坐标转换
- [NativeCanvasView.swift:820-856](src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift#L820-L856) - 截图方法

#### 问题4.3: 预览区域太小

**原因**: 固定 `maxHeight: 320`，在iPad的Sheet中显得过小

**当前代码** [ImageToImageConfirmSheet.swift:46-57](src/MindCanvas/MindCanvas/Views/Editor/Sheets/ImageToImageConfirmSheet.swift#L46-L57):
```swift
private var preview: some View {
    Image(uiImage: previewImage)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(maxHeight: 320)  // 固定高度太小
        // ...
}
```

### 5.3 解决方案

#### 方案4.1: 修复按钮样式

**方法**: 统一按钮样式，确保两个按钮都使用相同的frame约束

**修改 Theme.swift 中的按钮样式**:

```swift
// 文件: Infrastructure/Theme.swift

extension View {
    func primaryButtonStyle() -> some View {
        self
            .frame(maxWidth: .infinity, minHeight: Theme.Sizes.buttonHeight)
            .background(Theme.Colors.brandBlue)
            .foregroundColor(.white)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            .font(Theme.Fonts.bodyBold)
    }

    func secondaryButtonStyle() -> some View {
        self
            .frame(maxWidth: .infinity, minHeight: Theme.Sizes.buttonHeight)
            .background(Theme.Colors.cardBackground)
            .foregroundColor(Theme.Colors.brandBlue)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .stroke(Theme.Colors.brandBlue.opacity(0.3), lineWidth: 1)
            )
            .font(Theme.Fonts.bodyBold)
    }
}
```

**关键改动**:
- `frame(height: ...)` 改为 `frame(maxWidth: .infinity, minHeight: ...)`
- `maxWidth: .infinity` 确保在 HStack 中平均分配宽度
- `minHeight` 替代 `height` 保证最小高度但允许内容适配

#### 方案4.2: 修复选框内容显示

**步骤1: 添加调试日志**（临时）

在 [NativeEditorViewModel.swift](src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift) 的 `prepareImageToImageFlow()` 方法中添加：

```swift
func prepareImageToImageFlow() async {
    guard let canvasView = canvasView else {
        print("[ImageToImage] Error: canvasView is nil")
        return
    }

    let viewportRect = stateManager.magicFrame
    print("[ImageToImage] viewportRect (magicFrame): \(viewportRect)")

    let contentRect = canvasView.contentRect(forViewportRect: viewportRect)
    print("[ImageToImage] contentRect (after conversion): \(contentRect)")

    guard let snapshot = canvasView.captureContentSnapshot(rect: contentRect) else {
        print("[ImageToImage] Error: Failed to capture snapshot")
        flowHintMessage = "截图失败，请确保选框内有内容"
        return
    }

    print("[ImageToImage] Snapshot captured: size=\(snapshot.size)")

    pendingImageToImagePreview = snapshot
    showImageToImageConfirm = true
}
```

**步骤2: 增强截图方法的健壮性**

在 [NativeCanvasView.swift](src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift) 的 `captureContentSnapshot` 方法中：

```swift
func captureContentSnapshot(rect contentRect: CGRect) -> UIImage? {
    // 扩大边界容差
    let expandedCanvas = CGRect(
        x: -10,
        y: -10,
        width: canvasSize.width + 20,
        height: canvasSize.height + 20
    )
    let bounded = contentRect.intersection(expandedCanvas)

    guard !bounded.isNull, bounded.width > 1, bounded.height > 1 else {
        print("[Snapshot] Invalid rect: contentRect=\(contentRect), bounded=\(bounded)")
        return nil
    }

    let scale = UIScreen.main.scale
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false

    let drawingImage = pencilCanvas.drawing.image(from: bounded, scale: scale)

    let renderer = UIGraphicsImageRenderer(size: bounded.size, format: format)
    return renderer.image { rendererContext in
        let ctx = rendererContext.cgContext

        // 白色背景（确保可见性）
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: bounded.size))

        ctx.saveGState()
        ctx.translateBy(x: -bounded.origin.x, y: -bounded.origin.y)

        // 渲染对象层
        objectLayerView.layer.render(in: ctx)

        ctx.restoreGState()

        // 渲染 PencilKit 笔画
        drawingImage.draw(in: CGRect(origin: .zero, size: bounded.size))
    }
}
```

**步骤3: 验证坐标转换**

检查 `contentRect(forViewportRect:)` 方法的坐标转换逻辑：

```swift
func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
    // 确保viewportRect是相对于NativeCanvasView的坐标
    let rectInCanvas = pencilCanvas.convert(viewportRect, from: self)
    let scale = pencilCanvas.zoomScale
    let offset = pencilCanvas.contentOffset

    let result = CGRect(
        x: (rectInCanvas.origin.x + offset.x) / scale,
        y: (rectInCanvas.origin.y + offset.y) / scale,
        width: rectInCanvas.width / scale,
        height: rectInCanvas.height / scale
    )

    print("[Coordinate] viewportRect=\(viewportRect) -> contentRect=\(result), scale=\(scale), offset=\(offset)")
    return result
}
```

#### 方案4.3: 优化预览区域尺寸

**重写 ImageToImageConfirmSheet**:

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
                VStack(spacing: Theme.Spacing.xl) {
                    header

                    Divider()

                    // 动态计算预览高度
                    preview(availableHeight: proxy.size.height)

                    promptBlock

                    Spacer(minLength: Theme.Spacing.lg)

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

    // MARK: - Preview (动态高度)
    private func preview(availableHeight: CGFloat) -> some View {
        // 预览区域占用35%的可用高度，最小240pt，最大450pt
        let previewHeight = min(450, max(240, availableHeight * 0.35))

        return VStack(spacing: Theme.Spacing.sm) {
            Text("选区预览")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: previewHeight)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
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
        }
    }

    // MARK: - Actions
    private var actions: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button("取消", action: onCancel)
                .frame(maxWidth: .infinity, minHeight: Theme.Sizes.buttonHeight)
                .background(Theme.Colors.cardBackground)
                .foregroundColor(Theme.Colors.brandBlue)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .stroke(Theme.Colors.brandBlue.opacity(0.3), lineWidth: 1)
                )
                .font(Theme.Fonts.bodyBold)

            Button {
                onConfirm()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                    Text("确认生成")
                }
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Sizes.buttonHeight)
            .background(Theme.Colors.brandBlue)
            .foregroundColor(.white)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            .font(Theme.Fonts.bodyBold)
        }
    }
}

// MARK: - Preview
#Preview {
    ImageToImageConfirmSheet(
        previewImage: UIImage(systemName: "photo")!,
        prompt: "a beautiful sunset",
        onConfirm: { print("Confirm") },
        onCancel: { print("Cancel") }
    )
}
```

### 5.4 关键改动说明

| 改动项 | 原设计 | 新设计 |
|-------|-------|-------|
| 按钮样式 | 大小不一致 | 统一使用 maxWidth + minHeight |
| 预览高度 | 固定 320pt | 动态计算：35%可用高度，240-450pt范围 |
| 预览标签 | 无 | 添加"选区预览"标签 |
| 预览背景 | 无 | 浅灰色背景，确保空白内容也可见 |
| 说明文字 | 无 | 添加副标题"请确认将作为参考的画布内容" |

### 5.5 测试验证

| 测试项 | 预期结果 |
|-------|---------|
| 按钮大小 | "取消"和"确认生成"按钮高度、宽度一致 |
| 选框截图 | 控制台日志正常输出坐标信息，预览图显示选框内容 |
| 预览尺寸 | medium状态下预览至少240pt高，large状态下更大 |
| 空内容处理 | 选框内无内容时，显示浅灰色背景提示 |

---

## 六、实施优先级

| 优先级 | 任务 | 预计工时 | 依赖 |
|-------|-----|---------|-----|
| P0 | 修复按钮样式（Theme.swift） | 0.5h | 无 |
| P0 | 修复选框内容显示bug | 2h | 需要调试 |
| P1 | 重构文生图弹窗 | 2h | P0按钮样式 |
| P1 | 重构图生图弹窗 | 2h | P0按钮样式 |
| P2 | 移除+号按钮 | 0.5h | 无 |
| P2 | 添加返回按钮 | 1h | P2移除+号 |

**建议执行顺序**:
1. 先修复 Theme.swift 中的按钮样式（全局影响）
2. 添加调试日志，定位选框内容不显示的根本原因
3. 重构两个弹窗的UI
4. 最后处理资源库的导航改造

---

## 七、涉及文件清单

| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| [Theme.swift](src/MindCanvas/MindCanvas/Infrastructure/Theme.swift) | 修改 | 按钮样式添加 maxWidth |
| [NativeEditorView.swift](src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift) | 修改 | 移除overlay，修改资源库头部 |
| [TextToImageSheet.swift](src/MindCanvas/MindCanvas/Views/Editor/Sheets/TextToImageSheet.swift) | 重写 | 全新UI布局 |
| [ImageToImageConfirmSheet.swift](src/MindCanvas/MindCanvas/Views/Editor/Sheets/ImageToImageConfirmSheet.swift) | 重写 | 全新UI布局，动态预览高度 |
| [NativeEditorViewModel.swift](src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift) | 修改 | 添加调试日志（临时） |
| [NativeCanvasView.swift](src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift) | 修改 | 增强截图健壮性 |

---

## 八、验收标准

### 8.1 功能验收

- [ ] 关闭按钮不再遮挡"资源库"文字
- [ ] 资源库面板显示"返回"按钮，点击可关闭编辑器
- [ ] 资源库+号按钮已移除
- [ ] 文生图弹窗显示Tips提示和说明文字
- [ ] 文生图弹窗有"确定生成"按钮
- [ ] 图生图弹窗按钮大小一致
- [ ] 图生图弹窗预览区域显示选框内容
- [ ] 图生图弹窗预览区域大小合适

### 8.2 视觉验收

- [ ] 两个弹窗的整体风格一致
- [ ] 按钮样式符合设计规范
- [ ] 间距、圆角、阴影符合Theme定义
- [ ] 在iPad各尺寸上布局正常

### 8.3 交互验收

- [ ] 弹窗支持拖拽指示器关闭
- [ ] 按钮点击反馈正常
- [ ] 禁用状态按钮视觉明显
- [ ] 键盘弹出时布局不错乱

---

## 九、参考资料

- [Apple Human Interface Guidelines - Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets)
- [SwiftUI presentationDetents](https://developer.apple.com/documentation/swiftui/view/presentationdetents(_:))
- Figma iPad应用设计模式
- Procreate编辑器导航设计
