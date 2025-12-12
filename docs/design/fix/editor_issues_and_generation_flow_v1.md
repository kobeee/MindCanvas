# 编辑器问题修复与生成流程优化方案 v1.0

| 版本 | 日期 | 说明 |
|:---|:---|:---|
| v1.0 | 2025-12-12 | 初始版本，包含问题排查分析和生成流程优化方案 |

---

## 一、问题排查与修复方案

### 问题1：缩放 +/- 按钮点击后百分比数字不变化

**现象**：
- 点击左下角缩放 HUD 的 `+` 或 `-` 按钮后，百分比数字没有更新
- 最小缩放限制在 50%（这是设计限制，保持不变）

**原因分析**：

在 `NativeCanvasViewWrapper` 中，`onZoomChanged` 回调只在 `makeUIView` 时绑定一次：

```swift
// NativeCanvasViewWrapper.swift
func makeUIView(context: Context) -> NativeCanvasView {
    let view = NativeCanvasView()
    view.onZoomChanged = onZoomChanged  // ← 只在创建时设置
    return view
}

func updateUIView(_ uiView: NativeCanvasView, context: Context) {
    // ← 这里没有更新 onZoomChanged，闭包可能失效
}
```

SwiftUI 在状态变化时会重建闭包，但 `updateUIView` 没有重新绑定，导致回调链路断开。

**修复方案**：

```swift
func updateUIView(_ uiView: NativeCanvasView, context: Context) {
    if uiView.currentMode != toolMode {
        uiView.currentMode = toolMode
    }
    // 重新绑定回调，确保闭包引用最新
    uiView.onZoomChanged = onZoomChanged
}
```

**涉及文件**：
- `Views/Editor/Canvas/NativeCanvasView.swift`（`NativeCanvasViewWrapper` 部分）

---

### 问题2：双指捏合缩放不支持

**现象**：
- 双指捏合（pinch）手势无法缩放画布
- 在绘图模式和对象模式下都无效

**原因分析**：

UIScrollView 本身支持 pinch 缩放（已配置 `minimumZoomScale`/`maximumZoomScale`），但被上层视图的手势拦截：

1. **绘图模式**：`PKCanvasView` 的 `drawingPolicy = .anyInput` 会拦截所有触摸事件，包括 pinch
2. **对象模式**：`ResizableImageView` 有自己的 `UIPinchGestureRecognizer`，如果手指落在图片上会被捕获

**修复方案**：

需要配置手势的同时识别，让 scrollView 的 pinch 手势能够穿透上层视图。

```swift
// 方案A：让 PencilKit 的手势与 scrollView 缩放共存
// 在 NativeCanvasView 中设置
scrollView.pinchGestureRecognizer?.require(toFail: pencilCanvas.gestureRecognizers?.first { $0 is UIPinchGestureRecognizer })

// 方案B：在绘图模式下，通过 UIGestureRecognizerDelegate 允许同时识别
extension NativeCanvasView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                          shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 允许 scrollView 的 pinch 与其他手势同时识别
        if gestureRecognizer == scrollView.pinchGestureRecognizer {
            return true
        }
        return false
    }
}
```

**涉及文件**：
- `Views/Editor/Canvas/NativeCanvasView.swift`

---

### 问题3：绘画模式下笔划消失

**现象**：
- 单指绘制时，所有之前画完的笔划会先消失
- 松手后立即恢复显示

**原因分析**：

这是 PencilKit 与 UIScrollView 组合使用时的一个典型渲染问题。可能的原因：

1. **`scrollViewDidZoom` 触发布局更新**：
   ```swift
   func scrollViewDidZoom(_ scrollView: UIScrollView) {
       contentView.center = CGPoint(...)  // ← 修改 center 可能触发 PKCanvasView 重绘
   }
   ```

2. **`drawingPolicy = .anyInput` 的副作用**：
   在 anyInput 模式下，PencilKit 会尝试处理所有输入，可能与 UIScrollView 的手势产生冲突

3. **PKCanvasView 的 opaque/backgroundColor 设置**：
   虽然已设置 `isOpaque = false` 和 `backgroundColor = .clear`，但在某些布局变化时可能被重置

**排查步骤**：

1. 在 `canvasViewDrawingDidChange` 中添加日志，确认是否在绘制过程中被频繁调用
2. 临时禁用 `scrollViewDidZoom` 中的 center 调整，观察是否改善
3. 尝试将 `drawingPolicy` 改为 `.pencilOnly`，观察是否仍有问题
4. 检查是否有其他地方在绘制过程中触发了 `pencilCanvas.drawing = ...`

**修复方向**：

```swift
// 方案A：绘制过程中锁定布局更新
private var isDrawing = false

func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
    isDrawing = true
}

func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
    isDrawing = false
}

func scrollViewDidZoom(_ scrollView: UIScrollView) {
    guard !isDrawing else { return }  // 绘制中不更新布局
    // ... 原有逻辑
}
```

```swift
// 方案B：使用 CATransaction 禁用隐式动画
func scrollViewDidZoom(_ scrollView: UIScrollView) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    contentView.center = CGPoint(...)
    CATransaction.commit()
}
```

**涉及文件**：
- `Views/Editor/Canvas/NativeCanvasView.swift`

---

## 二、生成流程优化方案

### 2.1 概述

当前生成流程存在的问题：
- 用户点击"生成图片"后，不知道 AI 会看到什么内容
- 缺少确认步骤，容易误操作
- 没有"文生图"（无参考图生成）功能

**优化目标**：
1. 增加图生图预览确认浮窗
2. 新增文生图功能
3. 明确区分两种生成模式

---

### 2.2 图生图流程（需要选框）

**触发条件**：
- 选框可见（`isMagicFrameVisible = true`）
- 提示词非空

**流程**：

```
用户点击 [图生图] 按钮
    ↓
立即截取选框区域内容
    ↓
弹出确认浮窗（Sheet）
┌─────────────────────────────────────┐
│  确认生成                      [X]  │
│  请确认将作为参考的画布内容          │
│                                     │
│  ┌─────────────────────────────┐   │
│  │      [选框区域截图预览]       │   │
│  │        (保持原比例显示)       │   │
│  └─────────────────────────────┘   │
│                                     │
│  提示词                             │
│  ┌─────────────────────────────┐   │
│  │  用户输入的提示词内容         │   │
│  └─────────────────────────────┘   │
│                                     │
│  [取消]              [✨ 确认生成]   │
└─────────────────────────────────────┘
    ↓
用户点击 [确认生成]
    ↓
关闭浮窗 → 资源库插入 Loading 占位 → 调用 AI API
    ↓
生成完成 → 更新 Asset → 添加到画布
```

**浮窗组件设计**：

```swift
struct ImageToImageConfirmSheet: View {
    let previewImage: UIImage
    let prompt: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            HStack {
                Text("确认生成")
                    .font(.headline)
                Spacer()
                Button { onCancel() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            
            Text("请确认将作为参考的画布内容")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // 预览图
            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 300)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            // 提示词
            VStack(alignment: .leading, spacing: 8) {
                Text("提示词")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(prompt)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // 按钮
            HStack(spacing: 16) {
                Button("取消") { onCancel() }
                    .buttonStyle(.bordered)
                
                Button {
                    onConfirm()
                } label: {
                    Label("确认生成", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
```

---

### 2.3 文生图流程（不需要选框）

**触发条件**：无（随时可用）

**流程**：

```
用户点击 [文生图] 按钮
    ↓
弹出输入浮窗（Sheet）
┌─────────────────────────────────────┐
│  文生图                        [X]  │
│  生成独立的图片素材，可拖入画布使用   │
│                                     │
│  提示词                             │
│  ┌─────────────────────────────┐   │
│  │  描述你想生成的内容...        │   │
│  │                             │   │
│  │                             │   │
│  └─────────────────────────────┘   │
│                                     │
│  尺寸                               │
│  ┌──────┐ ┌──────┐ ┌──────┐       │
│  │ 1:1  │ │ 16:9 │ │ 9:16 │       │
│  │ 正方 │ │ 横版  │ │ 竖版 │       │
│  └──────┘ └──────┘ └──────┘       │
│                                     │
│  [取消]              [✨ 生成资源]   │
└─────────────────────────────────────┘
    ↓
用户输入提示词 + 选择尺寸 + 点击 [生成资源]
    ↓
关闭浮窗 → 资源库插入 Loading 占位 → 调用 AI API
    ↓
生成完成 → 添加到资源库（类型 .generated）
```

**尺寸选项**：

| 选项 | 比例 | 说明 |
|:--|:--|:--|
| 1:1 | 正方形 | 默认选项 |
| 16:9 | 横版 | 适合风景、宽幅场景 |
| 9:16 | 竖版 | 适合人像、手机壁纸 |
| 4:3 | 标准横版 | 经典照片比例 |
| 3:4 | 标准竖版 | 经典肖像比例 |

**浮窗组件设计**：

```swift
enum ImageAspectRatio: String, CaseIterable, Identifiable {
    case square = "1:1"
    case landscape = "16:9"
    case portrait = "9:16"
    case standard = "4:3"
    case standardPortrait = "3:4"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .square: return "正方"
        case .landscape: return "横版"
        case .portrait: return "竖版"
        case .standard: return "标准横"
        case .standardPortrait: return "标准竖"
        }
    }
}

struct TextToImageSheet: View {
    @State private var prompt: String = ""
    @State private var selectedRatio: ImageAspectRatio = .square
    let onGenerate: (String, ImageAspectRatio) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // 标题
            HStack {
                Text("文生图")
                    .font(.headline)
                Spacer()
                Button { onCancel() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            
            Text("生成独立的图片素材，可拖入画布使用")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            // 提示词输入
            VStack(alignment: .leading, spacing: 8) {
                Text("提示词")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextEditor(text: $prompt)
                    .frame(height: 100)
                    .padding(8)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
            }
            
            // 尺寸选择
            VStack(alignment: .leading, spacing: 8) {
                Text("尺寸")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    ForEach(ImageAspectRatio.allCases) { ratio in
                        RatioButton(
                            ratio: ratio,
                            isSelected: selectedRatio == ratio,
                            onTap: { selectedRatio = ratio }
                        )
                    }
                }
            }
            
            Spacer()
            
            // 按钮
            HStack(spacing: 16) {
                Button("取消") { onCancel() }
                    .buttonStyle(.bordered)
                
                Button {
                    onGenerate(prompt, selectedRatio)
                } label: {
                    Label("生成资源", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.isEmpty)
            }
        }
        .padding()
    }
}
```

---

### 2.4 右侧面板布局调整

```
┌──────────────────────────┐
│ 📋 API 配置              │
│ ┌────────────────────┐  │
│ │ 服务      官方服务  │  │
│ └────────────────────┘  │
├──────────────────────────┤
│ ✨ 生成模型              │
│ ┌────────────────────┐  │
│ │ Nano Banana Pro    │  │
│ │ v1.0 (Gemini 3)  🔒│  │
│ └────────────────────┘  │
├──────────────────────────┤
│ 💬 生成描述              │
│ ┌────────────────────┐  │
│ │                    │  │
│ │   输入提示词...     │  │
│ │                    │  │
│ └────────────────────┘  │
├──────────────────────────┤
│                          │
│  ┌────────────────────┐ │
│  │   ✨ 图生图         │ │  ← 主按钮（borderedProminent）
│  └────────────────────┘ │     需要选框可见 + prompt 非空
│                          │
│  ┌────────────────────┐ │
│  │   🎨 文生图         │ │  ← 次要按钮（bordered）
│  └────────────────────┘ │     无前置条件
│                          │
├──────────────────────────┤
│ ℹ️ 使用提示              │
│ 📍 显示选框并框选区域     │
│ 📝 输入描述内容           │
│ ✨ 点击图生图开始创作     │
│                          │
│ ⚠️ 请先显示选框          │  ← 仅图生图条件不满足时显示
└──────────────────────────┘
```

---

### 2.5 数据模型

Asset 类型保持不变，两种生成方式的结果都标记为 `.generated`：

```swift
enum AssetType: String, Codable {
    case upload      // 用户从相册导入
    case generated   // AI 生成（包括图生图和文生图）
}
```

可选扩展：增加生成模式字段用于区分

```swift
enum GenerationMode: String, Codable {
    case img2img  // 图生图
    case txt2img  // 文生图
}

// Asset 可选字段
var generationMode: GenerationMode?
var aspectRatio: String?  // 记录生成时的尺寸比例
```

---

## 三、开发优先级

| 优先级 | 任务 | 类型 | 预估工时 |
|:--|:--|:--|:--|
| P0 | 问题3：绘画笔划消失 | Bug修复 | 2h |
| P0 | 问题2：双指缩放不支持 | Bug修复 | 1h |
| P1 | 问题1：缩放按钮百分比不更新 | Bug修复 | 0.5h |
| P1 | 图生图预览确认浮窗 | 新功能 | 2h |
| P2 | 文生图功能 | 新功能 | 3h |

---

## 四、涉及文件清单

### 修复相关
- `Views/Editor/Canvas/NativeCanvasView.swift`
- `Views/Editor/Canvas/NativeCanvasViewWrapper`（同一文件内）

### 新功能相关
- `Views/Editor/NativeEditorView.swift`（右侧面板调整）
- `Views/Editor/Sheets/ImageToImageConfirmSheet.swift`（新增）
- `Views/Editor/Sheets/TextToImageSheet.swift`（新增）
- `ViewModels/NativeEditorViewModel.swift`（增加文生图方法）
- `Models/Asset.swift`（可选：增加 generationMode 字段）

---

## 五、测试验证

### 问题修复验证
1. [ ] 点击缩放 +/- 按钮，百分比数字正常更新
2. [ ] 双指捏合可以缩放画布
3. [ ] 绘画过程中笔划不消失

### 图生图功能验证
1. [ ] 选框隐藏时，图生图按钮禁用
2. [ ] prompt 为空时，图生图按钮禁用
3. [ ] 点击图生图，弹出预览浮窗，显示正确的截图和提示词
4. [ ] 点击确认生成，关闭浮窗，资源库出现 Loading 占位
5. [ ] 生成完成，资源正确添加到资源库

### 文生图功能验证
1. [ ] 点击文生图，弹出输入浮窗
2. [ ] 可以输入提示词和选择尺寸
3. [ ] prompt 为空时，生成按钮禁用
4. [ ] 点击生成资源，关闭浮窗，资源库出现 Loading 占位
5. [ ] 生成完成，资源正确添加到资源库

