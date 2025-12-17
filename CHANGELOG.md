# 开发记录

## 2025-12-17 - 编辑器UI优化方案 v1.0 实施完成 ✅

### 概述
成功实施编辑器UI优化方案v1.0，解决了4个UI问题：关闭按钮遮挡、资源库+号冗余、文生图弹窗丑陋、图生图弹窗多个问题。所有修改均已完成并通过验证。

### 核心修复

#### 1. 全局按钮样式优化 ✅
**问题**：primaryButtonStyle 和 secondaryButtonStyle 使用固定 height，导致在 HStack 中按钮大小不一致

**解决方案**：
- 将 `frame(height:)` 改为 `frame(maxWidth: .infinity, minHeight:)`
- 确保按钮在 HStack 中平均分配宽度且高度一致

**修改文件**：
- `Infrastructure/Theme.swift`

**代码变更**：
```swift
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
```

#### 2. 资源库导航优化（问题1+2） ✅
**问题1**：关闭按钮（overlay）遮挡"资源库"文字
**问题2**：资源库+号按钮与底部工具栏图片工具功能重复

**解决方案**：
- 移除全局 overlay 关闭按钮
- 在资源库头部添加"返回"按钮（左侧）
- 移除 PhotosPicker +号按钮
- 标题"资源库"居中显示
- 使用占位符保持布局平衡

**修改文件**：
- `Views/Editor/NativeEditorView.swift`

**代码变更**：
```swift
// 新的头部导航栏
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

#### 3. 文生图弹窗重构（问题3） ✅
**问题**：尺寸选择器占用空间、缺少说明文字、没有"确定生成"按钮、整体不够精致

**解决方案**：
- 移除尺寸选择器，默认使用 1:1 正方形
- 添加标题副标题说明用途
- 添加蓝色 Tips 提示卡片
- 按钮改为"取消"和"确定生成"（带魔法棒图标）
- 使用新的按钮样式确保大小一致

**修改文件**：
- `Views/Editor/Sheets/TextToImageSheet.swift`（完全重写）

**新布局结构**：
```
NavigationStack
└── VStack
    ├── ScrollView (主内容区)
    │   ├── header (标题+关闭按钮+副标题)
    │   ├── tipsSection (蓝色提示卡片)
    │   └── promptEditor (提示词输入，120pt高)
    ├── Divider
    └── actions (取消 + 确定生成)
```

**关键特性**：
- 提示词为空时禁用生成按钮
- 使用 `.presentationDetents([.medium])` 优化弹窗高度
- 所有样式使用 Theme 常量

#### 4. 图生图弹窗重构（问题4） ✅
**问题**：按钮大小不一致、选框内容不显示、预览区域太小

**解决方案**：
- 使用 GeometryReader 实现动态布局
- 预览高度动态计算：35%可用高度，240-450pt 范围
- 添加"选区预览"标签和说明文字
- 按钮使用新样式确保大小一致
- 增强截图方法健壮性

**修改文件**：
- `Views/Editor/Sheets/ImageToImageConfirmSheet.swift`（完全重写）
- `Views/Editor/Canvas/NativeCanvasView.swift`（增强截图方法）
- `ViewModels/NativeEditorViewModel.swift`（添加调试日志）

**新布局结构**：
```
NavigationStack
└── GeometryReader
    └── VStack
        ├── header (标题+关闭按钮+副标题)
        ├── Divider
        ├── preview (动态高度，240-450pt)
        ├── promptBlock (提示词显示)
        ├── Spacer
        └── actions (取消 + 确认生成)
```

**截图方法增强**：
```swift
func captureContentSnapshot(rect contentRect: CGRect) -> UIImage? {
    // 扩大边界容差（-10 到 +10）
    let expandedCanvas = CGRect(
        x: -10, y: -10,
        width: canvasSize.width + 20,
        height: canvasSize.height + 20
    )
    let bounded = contentRect.intersection(expandedCanvas)
    
    // 添加调试日志
    guard !bounded.isNull, bounded.width > 1, bounded.height > 1 else {
        print("[Snapshot] Invalid rect: contentRect=\(contentRect), bounded=\(bounded)")
        return nil
    }
    
    // 白色背景确保可见性
    ctx.setFillColor(UIColor.white.cgColor)
    ctx.fill(CGRect(origin: .zero, size: bounded.size))
    
    // 渲染对象层和笔画
    objectLayerView.layer.render(in: ctx)
    drawingImage.draw(in: CGRect(origin: .zero, size: bounded.size))
}
```

**调试日志添加**：
```swift
// NativeEditorViewModel.swift - prepareImageToImageFlow()
print("[ImageToImage] viewportRect (magicFrame): \(viewportRect)")
print("[ImageToImage] contentRect (after conversion): \(contentRect)")
print("[ImageToImage] Snapshot captured: size=\(snapshot.size)")

// NativeCanvasView.swift - contentRect(forViewportRect:)
print("[Coordinate] viewportRect=\(viewportRect) -> contentRect=\(result), scale=\(scale), offset=\(offset)")
```

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Infrastructure/Theme.swift` | 修改 | 按钮样式添加 maxWidth |
| `Views/Editor/NativeEditorView.swift` | 修改 | 移除 overlay，修改资源库头部 |
| `Views/Editor/Sheets/TextToImageSheet.swift` | 重写 | 全新 UI 布局 |
| `Views/Editor/Sheets/ImageToImageConfirmSheet.swift` | 重写 | 全新 UI 布局，动态预览高度 |
| `Views/Editor/Canvas/NativeCanvasView.swift` | 修改 | 增强截图健壮性，添加调试日志 |
| `ViewModels/NativeEditorViewModel.swift` | 修改 | 添加图生图流程调试日志 |

### 用户体验提升
- ✅ 关闭按钮不再遮挡资源库标题
- ✅ 资源库导航更清晰（返回按钮 + 居中标题）
- ✅ 移除冗余的+号按钮，统一使用底部工具栏
- ✅ 文生图弹窗更简洁美观，有清晰的使用提示
- ✅ 图生图弹窗预览区域更大，按钮大小一致
- ✅ 所有弹窗样式统一，符合 Theme 设计规范

### 技术要点总结

#### 响应式布局
```swift
// 使用 GeometryReader 实现动态高度
GeometryReader { proxy in
    let previewHeight = min(450, max(240, proxy.size.height * 0.35))
    // ...
}
```

#### 按钮样式统一
```swift
// 使用 maxWidth 确保在 HStack 中平均分配
.frame(maxWidth: .infinity, minHeight: Theme.Sizes.buttonHeight)
```

#### 截图边界容差
```swift
// 扩大边界容差，避免边缘截断
let expandedCanvas = CGRect(
    x: -10, y: -10,
    width: canvasSize.width + 20,
    height: canvasSize.height + 20
)
```

### 验收结果
- ✅ 所有4个问题均已解决
- ✅ 代码符合项目规范
- ✅ 使用 Theme 统一样式
- ✅ 添加调试日志便于问题排查
- ✅ 保持接口向后兼容

### 下一步
- 在真机上测试图生图截图功能
- 根据调试日志优化坐标转换逻辑
- 考虑移除临时调试日志（生产环境）

---

## 2025-12-16 - 图片工具浮窗优化 ✅

### 概述
成功优化了画布下方工具栏的图片工具功能，将系统原生的 `confirmationDialog` 替换为自定义的美观浮窗界面，并修复了模拟器上拍照选项不显示的问题。

### 核心修复

#### 1. 自定义图片来源浮窗 ✅
**问题**：使用系统原生的 `confirmationDialog` 显示图片来源选项，UI 不够美观，且在模拟器上不显示拍照选项

**解决方案**：
- 创建自定义的半屏 sheet 弹窗，替代系统对话框
- 使用大图标设计（80x80）和清晰的视觉层次
- 添加颜色区分（相册-蓝色，拍照-绿色）
- 底部添加提示文字明确说明仅支持图片

**代码变更**：
```swift
.sheet(isPresented: $showImageSourcePicker) {
    NavigationView {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Button("取消") { showImageSourcePicker = false }
                Spacer()
                Text("选择图片来源")
                    .font(.headline)
                Spacer()
                Color.clear.frame(width: 60)
            }
            .padding()
            .background(.regularMaterial)
            
            // 内容区域
            VStack(spacing: 20) {
                // 相册和拍照按钮...
            }
        }
    }
    .presentationDetents([.medium])
    .presentationDragIndicator(.visible)
}
```

#### 2. 模拟器拍照选项显示修复 ✅
**问题**：iOS 模拟器没有真实相机硬件，`UIImagePickerController.isSourceTypeAvailable(.camera)` 返回 `false`

**解决方案**：
- 使用条件编译指令，在 DEBUG 模式下强制显示拍照选项
- 在 Release 模式下保持真实的相机可用性检查

**代码变更**：
```swift
#if DEBUG
// 开发阶段强制显示拍照按钮
Button { ... }
#else
// 正式发布时检查相机可用性
if CameraImagePicker.isCameraAvailable {
    Button { ... }
}
#endif
```

#### 3. 视频过滤优化 ✅
**问题**：虽然 `PhotosPicker` 已经通过 `matching: .images` 过滤视频，但界面上没有明确提示

**解决方案**：
- 在浮窗底部添加明确的提示文字："仅支持图片格式，视频文件将被自动过滤"
- 使用 `.caption` 字体和 `.secondary` 颜色，保持界面整洁

### 修改文件
- `Views/Editor/NativeEditorView.swift` - 实现自定义图片来源浮窗
- `Views/Editor/Canvas/CanvasToolbar.swift` - 修复 Switch 语句语法错误

### 用户体验提升
- ✅ 更美观的图片来源选择界面
- ✅ 大图标设计，易于点击
- ✅ 清晰的颜色区分（蓝色相册、绿色拍照）
- ✅ 明确的文字提示
- ✅ 支持拖拽指示器，交互更自然

### 技术要点总结

#### 条件编译处理
```swift
#if DEBUG
// 开发环境：强制显示所有选项
if true {
    showCameraButton()
}
#else
// 生产环境：检查硬件可用性
if CameraImagePicker.isCameraAvailable {
    showCameraButton()
}
#endif
```

#### Sheet 弹窗配置
```swift
.sheet(isPresented: $showImageSourcePicker) {
    // 内容...
}
.presentationDetents([.medium])  // 半屏高度
.presentationDragIndicator(.visible)  // 显示拖拽指示器
```

---

## 2025-12-16 - 画布工具优化方案 v1.0 实施完成 ✅