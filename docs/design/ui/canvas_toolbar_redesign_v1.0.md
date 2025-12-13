# 画布工具栏重构设计方案 v1.0

## 概述

本方案将画布从"模式切换"架构重构为"工具切换"架构，参考 Figma/Canva 等专业设计工具的交互模式。核心目标是：

1. **消除手势冲突**：每个工具独占手势，彻底解决笔画漂移问题
2. **提升操作直觉**：工具即功能，所见即所得
3. **简化状态管理**：无需维护复杂的模式切换逻辑

---

## 设计理念：优雅、高级、有品味

### 视觉原则

| 原则 | 说明 | 实现 |
|:---|:---|:---|
| **克制** | 少即是多，避免视觉噪音 | 单一品牌色，极简图标，大量留白 |
| **一致** | 所有组件遵循统一设计语言 | 复用 Theme.swift 变量，禁止硬编码 |
| **精致** | 细节决定品质感 | 柔和阴影，流畅动画，精确间距 |
| **原生** | 尊重 Apple 设计规范 | 使用系统 Material、SF Symbols |

### 色彩策略

- **主色**：品牌蓝 `#007AFF`，仅用于选中态和关键操作
- **中性色**：大面积使用 `systemGray6`、`secondaryText`
- **强调色**：金色渐变仅用于 Pro 功能标识
- **警告色**：橙色仅用于提示，红色仅用于删除

### 动效策略

- **工具切换**：`.spring(response: 0.3, dampingFraction: 0.7)` - 轻快有弹性
- **选中态**：`.spring(response: 0.25, dampingFraction: 0.8)` - 即时响应
- **面板展开**：`.easeInOut(duration: 0.2)` - 平滑过渡
- **禁止**：突兀的线性动画、过长的持续时间、频繁的闪烁

---

## 一、架构变化

### 1.1 移除的概念

| 移除项 | 原因 |
|:---|:---|
| `CanvasToolMode.objectMode` | 改为选择工具 |
| `CanvasToolMode.drawingMode` | 改为画笔/橡皮擦工具 |
| 双指捏合缩放 | 改为滑动条缩放，避免手势冲突 |
| 资源库加号按钮 | 迁移到图片工具 |
| Zoom HUD 的 +/- 按钮 | 改为滑动条 |

### 1.2 新增的概念

| 新增项 | 说明 |
|:---|:---|
| `CanvasTool` 枚举 | 定义所有可用工具 |
| 底部工具栏 | 工具选择入口 |
| 左上角功能键 | 撤销/恢复/复制/清屏 |
| 缩放滑动条 | 替代 +/- 按钮 |

---

## 二、工具栏设计

### 2.1 底部工具栏

从左到右依次为：

| 序号 | 图标 | 工具名称 | 功能描述 | 快捷键 |
|:---:|:---:|:---|:---|:---:|
| 1 | `arrow.up.left.and.arrow.down.right` | **选择工具** | 选中/移动/缩放/旋转对象 | V |
| 2 | `hand.raised` | **平移工具** | 拖动平移整个画布 | H |
| 3 | `pencil` | **画笔工具** | 自由绘制笔画 | B |
| 4 | `eraser` | **橡皮擦** | 擦除笔画 | E |
| 5 | `arrow.up.right` | **箭头工具** | 绘制箭头/线条 | L |
| 6 | `textformat` | **文字工具** | 添加文字标注 | T |
| 7 | `bubble.left` | **标注工具** | 添加气泡标注 | C |
| 8 | `photo` | **图片工具** | 导入相册/拍照 | I |
| 9 | `rectangle` | **矩形工具** | 绘制矩形 | R |
| 10 | `chevron.up` | **更多** | 展开更多工具（预留） | - |

**视觉设计**（与 Theme.swift 保持一致）：
- 工具栏背景：毛玻璃效果 `.ultraThinMaterial`
- 形状：圆角矩形 `RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)` (16pt)
- 选中态：品牌蓝 `Theme.Colors.brandBlue` 填充 + 白色图标
- 未选中态：透明背景 + `Theme.Colors.secondaryText` 图标
- 图标大小：22pt（与现有工具栏一致）
- 工具间距：`Theme.Spacing.sm` (8pt)
- 内边距：水平 `Theme.Spacing.lg` (16pt)，垂直 `Theme.Spacing.md` (12pt)
- 工具栏距底部：`Theme.Spacing.xl` (20pt)
- 阴影：`Theme.Shapes.cardShadow()` - `Color.black.opacity(0.08), radius: 8`

**工具按钮规格**：
- 按钮尺寸：40x40pt（触控区域友好）
- 圆角：`Theme.Shapes.buttonCornerRadius` (12pt)
- 选中动画：`.spring(response: 0.3, dampingFraction: 0.7)`

### 2.2 左上角功能键

| 序号 | 图标 | 功能 | 说明 |
|:---:|:---:|:---|:---|
| 1 | `arrow.uturn.backward` | **撤销** | 撤销上一步操作 |
| 2 | `arrow.uturn.forward` | **恢复** | 恢复撤销的操作 |
| 3 | `doc.on.doc` | **复制** | 复制选中对象 |
| 4 | `trash` | **清屏** | 清除画布所有内容 |

**视觉设计**（与 Theme.swift 保持一致）：
- 背景：`.ultraThinMaterial` + `RoundedRectangle(cornerRadius: 12)`
- 按钮排列：水平排列
- 按钮尺寸：36x36pt
- 按钮间距：`Theme.Spacing.sm` (8pt)
- 内边距：水平 12pt，垂直 8pt
- 距左上角：`Theme.Spacing.lg` (16pt)
- 图标大小：18pt
- 禁用态：`opacity(0.4)`
- 阴影：`Color.black.opacity(0.05), radius: 4`

### 2.3 缩放控制（左下角）

**布局**：
```
[=======●==========] 100%
         ↑
      可拖动滑块
```

**视觉设计**（与 Theme.swift 保持一致）：
- 滑动条宽度：140pt
- 滑动范围：50% ~ 300%（对应 zoomScale 0.5 ~ 3.0）
- 滑块样式：品牌蓝圆形
- 轨道样式：灰色轨道，已填充部分为品牌蓝
- 数字显示：等宽字体 `Theme.Fonts.monospacedSmall`，点击可输入精确值
- 背景：`.ultraThinMaterial` + `RoundedRectangle(cornerRadius: 12)`
- 内边距：水平 12pt，垂直 8pt
- 距左下角：`Theme.Spacing.lg` (16pt)
- 阴影：`Color.black.opacity(0.05), radius: 4`

---

## 三、工具行为定义

### 3.1 选择工具（Selection Tool）

**激活时的状态**：
- `PKCanvasView.isUserInteractionEnabled = false`
- `objectLayerView.isUserInteractionEnabled = true`
- `scrollView` 手势禁用

**交互行为**：

| 操作 | 行为 |
|:---|:---|
| 点击空白处 | 取消当前选中 |
| 点击对象 | 选中该对象（z-index 最高优先） |
| 拖动对象 | 移动对象位置 |
| 拖动角点（内侧） | 等比缩放对象 |
| 拖动角点（外侧） | 旋转对象 |
| 点击 Magic Frame | 选中选框，可拖动调整 |

**选中态视觉**（与 Theme.swift 保持一致）：
- 边框：品牌蓝 `Theme.Colors.brandBlue` 虚线边框，2pt 线宽
- 缩放手柄：四角显示，10x10pt 圆角矩形，白色填充 + 品牌蓝边框
- 旋转手柄：角点外围 16pt 处显示，8pt 圆形，品牌蓝填充
- 选中动画：`.spring(response: 0.25, dampingFraction: 0.8)`
- 手柄悬停效果：`.scaleEffect(1.2)` + 阴影增强

### 3.2 平移工具（Pan Tool）

**激活时的状态**：
- `PKCanvasView.isUserInteractionEnabled = false`
- `objectLayerView.isUserInteractionEnabled = false`
- `scrollView.panGestureRecognizer.isEnabled = true`
- `scrollView.isScrollEnabled = true`

**交互行为**：

| 操作 | 行为 |
|:---|:---|
| 单指拖动 | 平移画布 |
| - | - |

### 3.3 画笔工具（Pen Tool）

**激活时的状态**：
- `PKCanvasView.isUserInteractionEnabled = true`
- `PKCanvasView.tool = PKInkingTool(.pen, color: .black, width: 5)`
- `objectLayerView.isUserInteractionEnabled = false`
- `scrollView` 手势全部禁用
- `scrollView.contentOffset` 锁定

**交互行为**：

| 操作 | 行为 |
|:---|:---|
| 任意输入绘制 | 在 PencilKit 上绘制笔画 |

**绘图策略**：
- `drawingPolicy = .anyInput`（支持手指/Apple Pencil/鼠标）

### 3.4 橡皮擦工具（Eraser Tool）

**激活时的状态**：
- 同画笔工具
- `PKCanvasView.tool = PKEraserTool(.bitmap)`

**交互行为**：

| 操作 | 行为 |
|:---|:---|
| 任意输入擦除 | 擦除触碰到的笔画 |

### 3.5 箭头工具（Arrow Tool）

**激活时的状态**：
- 自定义绘制层（非 PencilKit）
- `objectLayerView` 上添加临时绘制层

**交互行为**：

| 操作 | 行为 |
|:---|:---|
| 拖动 | 从起点到终点绘制箭头 |
| 释放 | 创建箭头对象，可后续选中编辑 |

### 3.6 文字工具（Text Tool）

**交互行为**：

| 操作 | 行为 |
|:---|:---|
| 点击画布 | 在点击位置创建文字输入框 |
| 输入完成 | 创建文字对象 |

### 3.7 标注工具（Annotation Tool）

**交互行为**：

| 操作 | 行为 |
|:---|:---|
| 拖动 | 绘制气泡标注框 |
| 释放 | 弹出文字输入 |

### 3.8 图片工具（Image Tool）

**交互行为**：

| 操作 | 行为 |
|:---|:---|
| 点击工具 | 弹出选择菜单：从相册选择 / 拍照 |
| 选择图片后 | 图片添加到画布中心 |

**菜单选项**：
- 从相册选择（PhotosPicker）
- 拍照（Camera，需要真机）

### 3.9 矩形工具（Rectangle Tool）

**交互行为**：

| 操作 | 行为 |
|:---|:---|
| 拖动 | 绘制矩形 |
| 释放 | 创建矩形对象 |

---

## 四、状态管理重构

### 4.1 新增枚举：CanvasTool

```swift
enum CanvasTool: String, CaseIterable {
    case select = "select"      // 选择工具
    case pan = "pan"            // 平移工具
    case pen = "pen"            // 画笔工具
    case eraser = "eraser"      // 橡皮擦
    case arrow = "arrow"        // 箭头工具
    case text = "text"          // 文字工具
    case annotation = "annotation" // 标注工具
    case image = "image"        // 图片工具
    case rectangle = "rectangle" // 矩形工具
    
    var iconName: String { ... }
    var displayName: String { ... }
    var shortcut: String? { ... }
}
```

### 4.2 CanvasStateManager 重构

```swift
@Observable
class CanvasStateManager {
    // 当前工具（替代原来的 currentMode）
    var currentTool: CanvasTool = .select
    
    // 选中状态
    var selectedNodeID: UUID?
    
    // Magic Frame（保持不变）
    var isMagicFrameVisible: Bool = false
    var magicFrame: CGRect = ...
    
    // 缩放（保持不变）
    var zoomScale: CGFloat = 1.0
    
    // 撤销/恢复栈
    var undoStack: [CanvasAction] = []
    var redoStack: [CanvasAction] = []
    
    // 工具切换
    func selectTool(_ tool: CanvasTool) { ... }
    
    // 撤销/恢复
    func undo() { ... }
    func redo() { ... }
    func recordAction(_ action: CanvasAction) { ... }
    
    // 复制/清屏
    func duplicateSelected() { ... }
    func clearCanvas() { ... }
}
```

### 4.3 撤销/恢复系统（Command Pattern）

```swift
protocol CanvasAction {
    func execute()
    func undo()
}

struct AddLayerAction: CanvasAction { ... }
struct RemoveLayerAction: CanvasAction { ... }
struct MoveLayerAction: CanvasAction { ... }
struct ScaleLayerAction: CanvasAction { ... }
struct RotateLayerAction: CanvasAction { ... }
struct DrawingAction: CanvasAction { ... }
struct ClearCanvasAction: CanvasAction { ... }
```

---

## 五、视图层重构

### 5.1 移除的组件

- 顶部工具栏中的"对象模式/绘图模式"切换器
- 顶部工具栏中的画笔/橡皮擦切换
- Zoom HUD 中的 +/- 按钮
- 资源库中的加号按钮

### 5.2 新增的组件

#### CanvasToolbar.swift（底部工具栏）

```swift
struct CanvasToolbar: View {
    @Binding var currentTool: CanvasTool
    var onImageImport: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(CanvasTool.allCases, id: \.self) { tool in
                ToolButton(
                    tool: tool,
                    isSelected: currentTool == tool,
                    action: {
                        if tool == .image {
                            onImageImport()
                        } else {
                            currentTool = tool
                        }
                    }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}
```

#### CanvasActionBar.swift（左上角功能键）

```swift
struct CanvasActionBar: View {
    var canUndo: Bool
    var canRedo: Bool
    var hasSelection: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onDuplicate: () -> Void
    var onClear: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            ActionButton(icon: "arrow.uturn.backward", enabled: canUndo, action: onUndo)
            ActionButton(icon: "arrow.uturn.forward", enabled: canRedo, action: onRedo)
            ActionButton(icon: "doc.on.doc", enabled: hasSelection, action: onDuplicate)
            ActionButton(icon: "trash", enabled: true, action: onClear)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}
```

#### ZoomSlider.swift（缩放滑动条）

```swift
struct ZoomSlider: View {
    @Binding var zoomScale: CGFloat
    var onZoomChanged: (CGFloat) -> Void
    
    private var zoomPercent: Int {
        Int(zoomScale * 100)
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Slider(value: $zoomScale, in: 0.5...3.0)
                .frame(width: 120)
                .onChange(of: zoomScale) { _, newValue in
                    onZoomChanged(newValue)
                }
            
            Text("\(zoomPercent)%")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}
```

### 5.3 NativeCanvasView 重构

核心变化：

```swift
// 工具切换时更新手势
func updateForTool(_ tool: CanvasTool) {
    switch tool {
    case .select:
        pencilCanvas.isUserInteractionEnabled = false
        objectLayerView.isUserInteractionEnabled = true
        scrollView.isScrollEnabled = false
        
    case .pan:
        pencilCanvas.isUserInteractionEnabled = false
        objectLayerView.isUserInteractionEnabled = false
        scrollView.isScrollEnabled = true
        
    case .pen:
        pencilCanvas.isUserInteractionEnabled = true
        pencilCanvas.tool = PKInkingTool(.pen, color: .black, width: 5)
        objectLayerView.isUserInteractionEnabled = false
        scrollView.isScrollEnabled = false
        lockContentOffset()
        
    case .eraser:
        pencilCanvas.isUserInteractionEnabled = true
        pencilCanvas.tool = PKEraserTool(.bitmap)
        objectLayerView.isUserInteractionEnabled = false
        scrollView.isScrollEnabled = false
        lockContentOffset()
        
    // ... 其他工具
    }
}
```

---

## 六、实现计划

### Phase 1：核心工具（预计 1 天）

**目标**：完成最小可用版本，验证架构

1. [ ] 定义 `CanvasTool` 枚举
2. [ ] 重构 `CanvasStateManager`（移除 mode，添加 tool）
3. [ ] 实现 `CanvasToolbar` 组件
4. [ ] 实现 `ZoomSlider` 组件
5. [ ] 重构 `NativeCanvasView.updateForTool()`
6. [ ] 实现选择工具（选中/移动/缩放）
7. [ ] 实现平移工具
8. [ ] 实现画笔工具
9. [ ] 实现橡皮擦工具

### Phase 2：功能键和缩放（预计 0.5 天）

1. [ ] 实现 `CanvasActionBar` 组件
2. [ ] 实现清屏功能
3. [ ] 实现复制功能
4. [ ] 移除旧的 Zoom HUD +/- 按钮
5. [ ] 集成 `ZoomSlider`

### Phase 3：撤销/恢复系统（预计 1 天）

1. [ ] 定义 `CanvasAction` 协议
2. [ ] 实现各类 Action（Add/Remove/Move/Scale/Rotate/Drawing）
3. [ ] 实现 undo/redo 栈管理
4. [ ] 集成到各操作中

### Phase 4：高级工具（预计 1.5 天）

1. [ ] 实现旋转操作（角点外围拖动）
2. [ ] 实现图片工具（导入相册/拍照）
3. [ ] 实现箭头工具
4. [ ] 实现文字工具
5. [ ] 实现标注工具
6. [ ] 实现矩形工具

### Phase 5：收尾和清理（预计 0.5 天）

1. [ ] 移除资源库加号按钮
2. [ ] 移除旧的模式切换代码
3. [ ] 清理无用代码
4. [ ] 更新 CHANGELOG

---

## 七、风险评估

### 7.1 已识别风险

| 风险 | 影响 | 缓解措施 |
|:---|:---|:---|
| 撤销/恢复系统复杂度高 | 可能延期 | 先实现基础操作的撤销，复杂操作后续迭代 |
| 文字/标注工具实现难度 | 可能不完善 | 先实现基础功能，高级编辑后续迭代 |
| 旋转手势与缩放冲突 | 用户体验问题 | 使用明确的旋转手柄，与缩放手柄物理分离 |

### 7.2 回滚策略

- 保留旧代码（注释或分支），确保可快速回滚
- 分 Phase 发布，每个 Phase 可独立验证

---

## 八、验收标准

### 8.1 功能验收

- [ ] 底部工具栏显示所有工具
- [ ] 工具切换正常，选中态正确
- [ ] 选择工具：选中/移动/缩放/旋转正常
- [ ] 平移工具：画布平移流畅
- [ ] 画笔工具：绘制无漂移
- [ ] 橡皮擦：擦除正常
- [ ] 图片工具：导入/拍照正常
- [ ] 箭头/文字/标注/矩形：基础功能可用
- [ ] 撤销/恢复：操作可回退
- [ ] 复制/清屏：功能正常
- [ ] 缩放滑动条：拖动调整缩放正常

### 8.2 体验验收

- [ ] 无笔画漂移问题
- [ ] 工具切换无延迟
- [ ] 手势响应精准
- [ ] 视觉风格统一

---

## 九、参考资料

- Figma 工具栏设计
- Canva 编辑器交互
- Apple Freeform 应用
- Procreate 工具布局

