# 编辑器原生化重构实施方案

> **基于**: `editor_optimization_v3.md` - Native Layer Engine  
> **目标**: 将 WebView/tldraw 方案重构为纯原生 SwiftUI + PencilKit + UIKit 技术栈  
> **状态**: 设计阶段  
> **创建日期**: 2025-12-11

---

## 1. 现状分析

### 1.1 当前架构 (WebView方案)

**组件结构**:
```
EditorView (SwiftUI)
├── AssetLibraryView (左侧，300pt)
├── CanvasContainerView (中间)
│   └── CanvasWebView (WKWebView)
│       └── HTML5 Canvas (Fallback)
└── ControlPanelView (右侧，320pt)
```

**核心问题**:
1. **WebView 延迟**: JS Bridge 通信存在性能损耗
2. **手势冲突**: Web 事件和原生手势难以协调
3. **绘图体验**: 无法利用 PencilKit 的原生压感和低延迟
4. **对象操控**: 图片元素无法作为独立对象自由移动和缩放
5. **维护成本**: Web/Native 双栈维护，调试困难

### 1.2 用户核心需求痛点

从 PRD 和设计文档梳理的核心需求：
- ✅ 无限画布 (缩放、漫游)
- ✅ Apple Pencil 原生绘图 (压感、倾斜)
- ✅ 图片对象独立操控 (移动、缩放、旋转、层级)
- ✅ 混合编辑 (绘图 + 拖拽图片) 无冲突
- ✅ AI 生成区域框选 (Magic Frame)
- ✅ 图层合并快照 (用于 AI 生成)

---

## 2. 新架构设计 (三明治图层模型)

### 2.1 技术栈选型

| 层级 | 技术方案 | 职责 |
|:---|:---|:---|
| **Layer 0** | `UIScrollView` + UIKit | 无限画布容器，缩放漫游 |
| **Layer 1** | 自定义 `UIView` / SwiftUI `ZStack` | 图片对象层 |
| **Layer 2** | `PKCanvasView` (PencilKit) | 绘图层 (Apple Pencil) |
| **Layer 3** | SwiftUI Overlay | 交互层 (选框、手柄) |

### 2.2 垂直图层堆叠关系

```
┌─────────────────────────────────────┐
│ Layer 3: Interaction Layer (SwiftUI)│  ← Magic Frame, Selection Handles
├─────────────────────────────────────┤
│ Layer 2: PKCanvasView (PencilKit)   │  ← 绘图层 (透明背景)
├─────────────────────────────────────┤
│ Layer 1: Object Layer (UIView/ZStack)│ ← 图片节点 (可拖拽缩放)
├─────────────────────────────────────┤
│ Layer 0: UIScrollView (Container)   │  ← 画布容器 (缩放漫游)
└─────────────────────────────────────┘
```

### 2.3 关键设计决策

#### 决策 1: UIKit vs SwiftUI 混合架构
**选择**: UIKit (Layer 0/1) + SwiftUI (Layer 3) + PencilKit (Layer 2)

**理由**:
- `UIScrollView` 的缩放和滚动是成熟方案，手势处理完善
- PencilKit 的 `PKCanvasView` 必须是 `UIView`
- SwiftUI 适合快速构建 UI 交互层 (选框、手柄)
- 通过 `UIViewRepresentable` 桥接

#### 决策 2: 图层渲染顺序
**Z-Index 管理**: 使用数组索引决定渲染顺序
- `layers: [LayerNode]` 数组，index 越大越靠上
- 支持"置顶/置底/上移/下移"操作

#### 决策 3: 触控冲突解决方案
采用**状态机 + 手势委托**模式：

| 工具模式 | PencilKit 状态 | Layer 1 手势 | 手指行为 | Pencil 行为 |
|:---|:---|:---|:---|:---|
| **对象模式** | `isUserInteractionEnabled = false` | ✅ 启用 | 拖拽图片 | - |
| **绘图模式** | `drawingPolicy = .pencilOnly` | ❌ 禁用 | 滚动画布 | 绘图 |

---

## 3. 核心组件设计

### 3.1 数据模型

```swift
// 画布文档 (持久化)
struct CanvasDocument: Codable {
    var id: UUID
    var layers: [LayerNode]        // 图片节点数组
    var drawingData: Data          // PKDrawing 序列化数据
    var canvasTransform: Transform // 缩放/平移状态
}

// 图层节点
struct LayerNode: Identifiable, Codable {
    let id: UUID
    var type: NodeType             // .userImage / .aiGenerated
    var url: String?               // 图片 URL
    var frame: CGRect              // 位置和尺寸
    var rotation: Double           // 旋转角度
    var isLocked: Bool             // 是否锁定
    var zIndex: Int                // 渲染顺序
    var opacity: Double            // 透明度 (默认 1.0)
}

enum NodeType: String, Codable {
    case userImage      // 用户上传
    case aiGenerated    // AI 生成
}

// 画布变换
struct Transform: Codable {
    var scale: CGFloat = 1.0
    var offset: CGPoint = .zero
}
```

### 3.2 状态机设计

```swift
enum CanvasToolMode {
    case objectMode    // 对象操作模式 (移动/缩放图片)
    case drawingMode   // 绘图模式 (Apple Pencil)
}

@Observable
class CanvasStateManager {
    var currentMode: CanvasToolMode = .objectMode
    var selectedNodeID: UUID?      // 当前选中的图片节点
    var magicFrame: CGRect?        // AI 生成选框
    
    // 状态切换
    func switchMode(to mode: CanvasToolMode) {
        // 切换逻辑...
    }
}
```

### 3.3 核心组件拆解

#### 组件 1: NativeCanvasView (UIKit Container)
**职责**: 承载所有图层的根容器

```swift
class NativeCanvasView: UIView {
    private let scrollView = UIScrollView()      // Layer 0
    private let objectLayerView = UIView()       // Layer 1
    private let pencilCanvas = PKCanvasView()    // Layer 2
    
    private var stateManager: CanvasStateManager
    private var layers: [LayerNode] = []
    
    // 初始化图层堆叠
    private func setupLayers() {
        scrollView.addSubview(objectLayerView)
        scrollView.addSubview(pencilCanvas)
        addSubview(scrollView)
        
        pencilCanvas.backgroundColor = .clear
        pencilCanvas.isOpaque = false
    }
    
    // 手势协调
    func configureGestureHandling(mode: CanvasToolMode) {
        switch mode {
        case .objectMode:
            pencilCanvas.isUserInteractionEnabled = false
            enableObjectGestures()
        case .drawingMode:
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.drawingPolicy = .pencilOnly
            disableObjectGestures()
        }
    }
}
```

#### 组件 2: ResizableImageView (可操控图片对象)
**职责**: 单个图片节点的视图容器

```swift
class ResizableImageView: UIView {
    private let imageView = UIImageView()
    private var node: LayerNode
    
    private var panGesture: UIPanGestureRecognizer!
    private var pinchGesture: UIPinchGestureRecognizer!
    private var rotateGesture: UIRotationGestureRecognizer!
    
    // 手势处理
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !node.isLocked else { return }
        let translation = gesture.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, 
                        y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)
        
        if gesture.state == .ended {
            notifyNodeUpdated()
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard !node.isLocked else { return }
        transform = transform.scaledBy(x: gesture.scale, y: gesture.scale)
        gesture.scale = 1.0
        
        if gesture.state == .ended {
            notifyNodeUpdated()
        }
    }
}
```

#### 组件 3: MagicFrameView (AI 生成选框)
**SwiftUI Overlay 实现**:

```swift
struct MagicFrameView: View {
    @Binding var frame: CGRect
    @State private var isDragging = false
    
    var body: some View {
        Rectangle()
            .stroke(Color.blue, lineWidth: 3)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // 拖拽调整选框位置
                    }
            )
            .overlay(alignment: .bottomTrailing) {
                // 右下角缩放手柄
                Circle()
                    .fill(Color.blue)
                    .frame(width: 20, height: 20)
                    .gesture(resizeGesture)
            }
    }
}
```

---

## 4. AI 生成工作流实现

### 4.1 快照生成 (图层合并)

```swift
func captureFrame(rect: CGRect) -> UIImage {
    let renderer = UIGraphicsImageRenderer(bounds: rect)
    return renderer.image { context in
        // 1. 渲染 Layer 1 (图片对象)
        objectLayerView.drawHierarchy(in: rect, afterScreenUpdates: true)
        
        // 2. 渲染 Layer 2 (PencilKit 绘图)
        pencilCanvas.drawHierarchy(in: rect, afterScreenUpdates: true)
    }
}
```

### 4.2 生成流程

```
用户拖动 Magic Frame 选择区域
    ↓
点击 "Generate" 按钮
    ↓
调用 captureFrame(magicFrame)
    ↓
上传 Base64 + Prompt 到后端
    ↓
显示 Loading 占位符 (在 Layer 1)
    ↓
收到生成结果 URL
    ↓
创建新 LayerNode (type: .aiGenerated)
    ↓
插入到 layers 数组顶部
    ↓
渲染到画布上 (对齐 magicFrame 位置)
```

---

## 5. 重构实施计划

### 5.1 Phase 1: 基础容器搭建 (2-3天)
- [ ] 创建 `NativeCanvasView.swift` (UIKit)
- [ ] 实现 UIScrollView 缩放和滚动
- [ ] 集成 PencilKit 的 `PKCanvasView`
- [ ] 测试基础绘图功能

**验收标准**:
- 画布可缩放、双指漫游
- Apple Pencil 可绘制线条
- 手指滚动不触发绘图

### 5.2 Phase 2: 对象图层系统 (3-4天)
- [ ] 实现 `LayerNode` 数据模型
- [ ] 创建 `ResizableImageView` 组件
- [ ] 实现拖拽、缩放、旋转手势
- [ ] 支持图层顺序调整 (Z-Index)
- [ ] 实现锁定/解锁功能

**验收标准**:
- 图片可拖拽移动
- 双指缩放和旋转生效
- 锁定后不可移动
- 图层遮挡关系正确

### 5.3 Phase 3: 状态机和模式切换 (2天)
- [ ] 实现 `CanvasStateManager`
- [ ] 工具模式切换 UI (ControlPanel)
- [ ] 手势冲突解决逻辑
- [ ] 模式切换时正确启用/禁用手势

**验收标准**:
- 切换到"对象模式"时可拖拽图片
- 切换到"绘图模式"时只能用 Pencil 绘图
- 手指在绘图模式下仅用于滚动画布

### 5.4 Phase 4: Magic Frame 和快照 (2天)
- [ ] 实现 SwiftUI `MagicFrameView`
- [ ] 拖拽和缩放选框
- [ ] 实现 `captureFrame()` 图层合并
- [ ] 测试快照包含所有可见元素

**验收标准**:
- Magic Frame 可拖动和调整大小
- 快照图片包含框选区域内所有图层
- Base64 数据正确生成

### 5.5 Phase 5: AI 生成集成 (2天)
- [ ] 修改 `EditorViewModel` 适配新架构
- [ ] 生成结果作为 `LayerNode` 插入
- [ ] Loading 状态显示
- [ ] 支持删除/调整生成图

**验收标准**:
- 点击生成后显示 Loading
- 生成的图片出现在画布正确位置
- 可像其他图片一样操作生成结果

### 5.6 Phase 6: 替换旧架构 (1天)
- [ ] 删除 `CanvasWebView.swift`
- [ ] 更新 `CanvasContainerView` 使用 `NativeCanvasView`
- [ ] 清理 WebView 相关代码
- [ ] 更新文档

**验收标准**:
- 旧 WebView 代码完全移除
- 编辑器使用纯原生架构
- 无编译错误和警告

### 5.7 Phase 7: 优化和测试 (2-3天)
- [ ] 性能优化 (懒加载、内存管理)
- [ ] 手势灵敏度调优
- [ ] 边界情况测试
- [ ] 用户体验打磨

---

## 6. 技术风险评估

### 6.1 高风险项

#### 风险 1: PencilKit 与 UIScrollView 手势冲突
**概率**: 中  
**影响**: 高  
**缓解措施**:
- 使用 `UIGestureRecognizerDelegate` 精确控制手势优先级
- 参考 Apple 官方 PencilKit 示例
- 必要时使用 `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)` 共存

#### 风险 2: 图层合并快照性能
**概率**: 低  
**影响**: 中  
**缓解措施**:
- 使用 `afterScreenUpdates: true` 确保渲染完整
- 限制画布尺寸上限 (如 8000x8000)
- 仅对选框区域截图，不全画布截图

#### 风险 3: SwiftUI 与 UIKit 桥接复杂度
**概率**: 低  
**影响**: 中  
**缓解措施**:
- 使用成熟的 `UIViewRepresentable` 模式
- 通过 `Coordinator` 管理生命周期
- 状态同步使用 `@Binding` 和 `@Bindable`

### 6.2 低风险项
- ✅ PencilKit API 稳定 (iOS 13+)
- ✅ UIScrollView 成熟方案
- ✅ 手势识别器文档完善
- ✅ SwiftUI/UIKit 混合架构有大量实践案例

---

## 7. 成功标准

### 7.1 功能完整性
- [x] 无限画布 (缩放、漫游)
- [x] Apple Pencil 原生绘图
- [x] 图片独立操控 (移动/缩放/旋转)
- [x] 工具模式切换无冲突
- [x] Magic Frame 框选
- [x] AI 生成集成

### 7.2 性能指标
- PencilKit 绘图延迟 < 10ms
- 画布缩放流畅 (60fps)
- 图片拖拽无掉帧
- 快照生成时间 < 500ms

### 7.3 用户体验
- 手势操作符合直觉
- 模式切换反馈清晰
- 无误触和意外操作
- 视觉反馈流畅

---

## 8. 后续优化方向

### 8.1 短期优化 (v1.1)
- [ ] 支持撤销/重做 (Undo/Redo)
- [ ] 图片裁剪功能
- [ ] 多选和批量操作
- [ ] 网格/参考线

### 8.2 长期优化 (v2.0)
- [ ] 形状工具 (矩形、圆形、箭头)
- [ ] 文字图层
- [ ] 蒙版和混合模式
- [ ] 动画和时间轴

---

## 9. 附录

### 9.1 关键 API 参考

**PencilKit**:
- `PKCanvasView`: 主画布视图
- `PKDrawing`: 绘图数据模型 (可序列化)
- `PKInkingTool`: 绘图工具
- `PKEraserTool`: 橡皮擦工具
- `drawingPolicy`: 控制 Pencil/Finger 行为

**UIKit 手势**:
- `UIPanGestureRecognizer`: 拖拽
- `UIPinchGestureRecognizer`: 缩放
- `UIRotationGestureRecognizer`: 旋转

**UIScrollView**:
- `minimumZoomScale` / `maximumZoomScale`: 缩放范围
- `contentSize`: 内容尺寸
- `delegate`: 滚动和缩放事件

### 9.2 参考资料
- [Apple PencilKit Documentation](https://developer.apple.com/documentation/pencilkit)
- [UIScrollView Programming Guide](https://developer.apple.com/documentation/uikit/uiscrollview)
- [Gesture Recognizers in UIKit](https://developer.apple.com/documentation/uikit/touches_presses_and_gestures)

---

**文档版本**: 1.0  
**最后更新**: 2025-12-11  
**状态**: ✅ 待评审

