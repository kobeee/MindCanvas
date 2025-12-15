# 箭头撤销问题修复方案 v1.0

> 创建日期: 2025-12-15
> 状态: 待开发
> 优先级: 高

## 一、问题描述

### 1.1 用户操作序列
1. 先绘制一个箭头
2. 然后用画笔绘制数字 1、2、3
3. 撤销操作：数字 3 和箭头一起消失（错误！应该只撤销数字 3）
4. 恢复操作：只有数字 3 被恢复，箭头彻底消失

### 1.2 预期行为
- 每个操作（箭头、笔画1、笔画2、笔画3）应该独立记录在撤销栈中
- 撤销时应该按照 LIFO（后进先出）顺序逐个撤销
- 箭头应该在撤销最后一笔画时才被撤销

---

## 二、根因分析

### 2.1 问题时间线

```
用户操作序列：
  [1] 创建箭头 → AddArrowAction 入栈
  [2] 绘制笔画1 → DrawingAction(A→B) 入栈
  [3] 绘制笔画2 → DrawingAction(B→C) 入栈
  [4] 绘制笔画3 → DrawingAction(C→D) 入栈

撤销栈状态：
  [AddArrowAction, DrawingAction(A→B), DrawingAction(B→C), DrawingAction(C→D)]

第1次撤销（撤销笔画3）：
  → 执行 DrawingAction(C→D).undo()
  → 调用 loadDrawing(fromDrawingData: C)
  → 触发 recreateCanvasViewWithDrawing(C)
  → PKCanvasView 重建，objectLayerView 视图层次破坏
  → 结果：笔画3消失，但箭头也意外消失！
```

### 2.2 核心问题：PKCanvasView 重建导致视图层次混乱

**问题代码位置**：`NativeCanvasView.swift` 第 582-620 行

```swift
private func recreateCanvasViewWithDrawing(_ data: Data) {
    // 保存箭头视图的引用
    let arrowViewsToRestore = arrowViews  // (1) 保存引用

    // 从父视图中移除旧的canvas
    pencilCanvas.removeFromSuperview()    // (2) 移除旧canvas

    // 创建新的PKCanvasView实例
    pencilCanvas = PKCanvasView()
    setupPencilCanvas()                   // (3) 问题点！

    // ...

    // 恢复箭头视图到新的objectLayerView中
    for (_, arrowView) in arrowViewsToRestore {
        objectLayerView.addSubview(arrowView)  // (4) 重复添加
    }
}
```

**`setupPencilCanvas()` 中的问题**（第 643 行）：

```swift
private func setupPencilCanvas() {
    // ...
    pencilCanvas.insertSubview(objectLayerView, at: 0)  // 问题！
    addSubview(pencilCanvas)
}
```

### 2.3 问题链条分析

```
问题链条：

[A] objectLayerView 生命周期问题
    ├─ 初始化时：pencilCanvas.addSubview(objectLayerView)
    ├─ 重建时：pencilCanvas 被移除，但 objectLayerView 仍被旧 canvas 持有
    └─ setupPencilCanvas 再次插入：insertSubview(objectLayerView, at: 0)
       └─ UIView 规则：一个 view 只能有一个 superview
          └─ objectLayerView 被从旧 canvas 移到新 canvas，但内部状态可能混乱

[B] 箭头视图状态丢失
    ├─ arrowViewsToRestore 保存的是对旧视图的引用
    ├─ 这些视图已经在 objectLayerView 中（因为 objectLayerView 被复用）
    └─ 再次 addSubview 实际上是无效操作，但视图层次已经被破坏

[C] 视觉结果
    └─ 箭头视图存在于 arrowViews 字典中，但其 superview 链已断裂
       └─ 结果：箭头不再被渲染显示
```

### 2.4 为什么恢复时箭头彻底消失？

```
恢复操作：
  → 执行 DrawingAction(C→D).execute()
  → 调用 loadDrawing(toDrawingData: D)
  → 再次触发 recreateCanvasViewWithDrawing(D)
  → 再次重建 PKCanvasView
  → 箭头视图的 superview 链再次被破坏
  → 箭头彻底消失，无法恢复
```

---

## 三、解决方案

### 方案选择

| 方案 | 复杂度 | 风险 | 推荐度 |
|:---|:---:|:---:|:---:|
| A. 将箭头视图提升为兄弟视图 | 中 | 低 | **推荐** |
| B. 避免 PKCanvasView 重建 | 低 | 中 | 备选 |
| C. 完全重建 objectLayerView | 高 | 高 | 不推荐 |

### 方案 A：将箭头视图提升为兄弟视图（推荐）

**核心思想**：将 `objectLayerView` 从 PKCanvasView 内部提升出来，作为其兄弟视图。这样 PKCanvasView 重建时不会影响箭头视图。

#### 3.1 新的视图层级结构

**当前结构**（有问题）：
```
NativeCanvasView (UIView)
└── pencilCanvas (PKCanvasView)
    └── objectLayerView (UIView)      <- 受 PKCanvasView 重建影响
        └── SelectableArrowView...
```

**新结构**（推荐）：
```
NativeCanvasView (UIView)
├── pencilCanvas (PKCanvasView)       <- 只负责绘图
└── overlayContainerView (UIView)     <- 滚动同步容器
    └── objectLayerView (UIView)      <- 不受 PKCanvasView 重建影响
        └── SelectableArrowView...
```

#### 3.2 详细修改步骤

##### 步骤 1：添加新的容器视图

**文件**：`NativeCanvasView.swift`

**位置**：第 40-50 行附近，在属性声明区域

```swift
// 新增：覆盖层容器视图（与 pencilCanvas 同级，用于承载箭头等对象）
private let overlayContainerView = UIView()
```

##### 步骤 2：修改 setupViews() 方法

**文件**：`NativeCanvasView.swift`

**位置**：第 134-180 行的 `setupViews()` 方法

**修改内容**：

```swift
private func setupViews() {
    backgroundColor = .systemGray6

    // 配置 PKCanvasView
    pencilCanvas.backgroundColor = .white
    pencilCanvas.isOpaque = true
    pencilCanvas.tool = inkingTool
    pencilCanvas.delegate = self
    pencilCanvas.contentSize = canvasSize
    pencilCanvas.minimumZoomScale = minZoomScale
    pencilCanvas.maximumZoomScale = maxZoomScale
    pencilCanvas.showsVerticalScrollIndicator = false
    pencilCanvas.showsHorizontalScrollIndicator = false
    pencilCanvas.bounces = true
    pencilCanvas.bouncesZoom = true

    // 配置覆盖层容器视图
    overlayContainerView.backgroundColor = .clear
    overlayContainerView.isUserInteractionEnabled = true
    overlayContainerView.clipsToBounds = true  // 裁剪超出部分

    // 配置对象图层
    objectLayerView.backgroundColor = .clear
    objectLayerView.isUserInteractionEnabled = true
    objectLayerView.frame = CGRect(origin: .zero, size: canvasSize)
    objectLayerView.clipsToBounds = false
    objectLayerView.isOpaque = false

    // 添加视图层级
    addSubview(pencilCanvas)
    addSubview(overlayContainerView)  // 覆盖在 pencilCanvas 上方
    overlayContainerView.addSubview(objectLayerView)

    // 初始化完成后设置状态
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.centerCanvas()
        self.updateForTool(self.currentTool)
        self.onZoomChanged?(self.pencilCanvas.zoomScale)
    }
}
```

##### 步骤 3：修改 setupConstraints() 方法

**文件**：`NativeCanvasView.swift`

**位置**：第 182-191 行的 `setupConstraints()` 方法

**修改内容**：

```swift
private func setupConstraints() {
    pencilCanvas.translatesAutoresizingMaskIntoConstraints = false
    overlayContainerView.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
        // pencilCanvas 填满整个视图
        pencilCanvas.topAnchor.constraint(equalTo: topAnchor),
        pencilCanvas.leadingAnchor.constraint(equalTo: leadingAnchor),
        pencilCanvas.trailingAnchor.constraint(equalTo: trailingAnchor),
        pencilCanvas.bottomAnchor.constraint(equalTo: bottomAnchor),

        // overlayContainerView 与 pencilCanvas 完全重叠
        overlayContainerView.topAnchor.constraint(equalTo: topAnchor),
        overlayContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
        overlayContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        overlayContainerView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
}
```

##### 步骤 4：添加滚动同步机制

**文件**：`NativeCanvasView.swift`

**位置**：在 `UIScrollViewDelegate` 扩展中添加

**原理**：`objectLayerView` 需要随着 `pencilCanvas` 的滚动和缩放同步变换

```swift
// MARK: - UIScrollViewDelegate (PKCanvasView 继承自 UIScrollView)

extension NativeCanvasView: PKCanvasViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 同步覆盖层的位置
        syncOverlayTransform()

        // ... 其他原有代码 ...
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // 同步覆盖层的缩放
        syncOverlayTransform()

        // 回调缩放变化
        onZoomChanged?(scrollView.zoomScale)
    }

    /// 同步覆盖层的变换（位置和缩放）
    private func syncOverlayTransform() {
        let offset = pencilCanvas.contentOffset
        let scale = pencilCanvas.zoomScale

        // 计算 objectLayerView 应该的变换
        // 原点移动 = -contentOffset
        // 缩放 = zoomScale
        objectLayerView.transform = CGAffineTransform(scaleX: scale, y: scale)
        objectLayerView.frame.origin = CGPoint(
            x: -offset.x,
            y: -offset.y
        )
    }
}
```

##### 步骤 5：修改 recreateCanvasViewWithDrawing() 方法

**文件**：`NativeCanvasView.swift`

**位置**：第 582-620 行

**修改内容**：不再需要恢复箭头视图，因为它们不在 PKCanvasView 内部

```swift
private func recreateCanvasViewWithDrawing(_ data: Data) {
    // 保存当前状态
    let oldZoomScale = pencilCanvas.zoomScale
    let oldContentOffset = pencilCanvas.contentOffset
    let oldDelegate = pencilCanvas.delegate

    // 注意：不再需要保存和恢复箭头视图，因为它们现在在 overlayContainerView 中
    // 与 PKCanvasView 完全独立

    // 从父视图中移除旧的canvas
    pencilCanvas.removeFromSuperview()

    // 创建新的PKCanvasView实例
    pencilCanvas = PKCanvasView()
    setupPencilCanvasOnly()  // 使用新方法，不涉及 objectLayerView

    // 恢复状态
    pencilCanvas.delegate = oldDelegate
    pencilCanvas.zoomScale = oldZoomScale
    pencilCanvas.contentOffset = oldContentOffset

    // 设置绘图数据
    if !data.isEmpty {
        do {
            let drawing = try PKDrawing(data: data)
            pencilCanvas.drawing = drawing
        } catch {
            // 静默处理错误
        }
    }

    // 同步覆盖层位置
    syncOverlayTransform()

    // 同步更新撤销基准数据
    strokeStartDrawingData = getDrawingData()
}
```

##### 步骤 6：新增 setupPencilCanvasOnly() 方法

**文件**：`NativeCanvasView.swift`

**位置**：在 `setupPencilCanvas()` 方法附近

```swift
/// 仅设置 PKCanvasView 的基本属性（不涉及 objectLayerView）
private func setupPencilCanvasOnly() {
    pencilCanvas.backgroundColor = .white
    pencilCanvas.isOpaque = true
    pencilCanvas.tool = inkingTool
    pencilCanvas.delegate = self

    pencilCanvas.contentSize = canvasSize
    pencilCanvas.minimumZoomScale = minZoomScale
    pencilCanvas.maximumZoomScale = maxZoomScale

    pencilCanvas.showsVerticalScrollIndicator = false
    pencilCanvas.showsHorizontalScrollIndicator = false
    pencilCanvas.bounces = true
    pencilCanvas.bouncesZoom = true

    // 插入到 overlayContainerView 下方
    insertSubview(pencilCanvas, belowSubview: overlayContainerView)

    // 更新约束
    pencilCanvas.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        pencilCanvas.topAnchor.constraint(equalTo: topAnchor),
        pencilCanvas.leadingAnchor.constraint(equalTo: leadingAnchor),
        pencilCanvas.trailingAnchor.constraint(equalTo: trailingAnchor),
        pencilCanvas.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    // 更新工具状态
    updateForTool(currentTool)
}
```

##### 步骤 7：修改 updateForTool() 方法中的手势处理

**文件**：`NativeCanvasView.swift`

**位置**：`updateForTool(_ tool: CanvasTool)` 方法

**修改内容**：需要同时处理 `overlayContainerView` 的交互状态

```swift
func updateForTool(_ tool: CanvasTool) {
    currentTool = tool

    switch tool {
    case .select:
        pencilCanvas.isUserInteractionEnabled = true
        pencilCanvas.drawingGestureRecognizer.isEnabled = false
        pencilCanvas.drawingPolicy = .default
        pencilCanvas.isScrollEnabled = false

        // 关键：启用覆盖层交互
        overlayContainerView.isUserInteractionEnabled = true
        objectLayerView.isUserInteractionEnabled = true

        // 启用所有对象手势
        for imageView in imageViews.values {
            imageView.enableObjectGestures()
        }
        for arrowView in arrowViews.values {
            arrowView.enableArrowGestures()
        }

    case .pan:
        pencilCanvas.isUserInteractionEnabled = true
        pencilCanvas.drawingGestureRecognizer.isEnabled = false
        pencilCanvas.drawingPolicy = .default
        pencilCanvas.isScrollEnabled = true
        pencilCanvas.panGestureRecognizer.isEnabled = true
        pencilCanvas.pinchGestureRecognizer?.isEnabled = true

        // 关键：禁用覆盖层交互，让手势穿透到 pencilCanvas
        overlayContainerView.isUserInteractionEnabled = false

    case .pen, .eraser:
        pencilCanvas.isUserInteractionEnabled = true
        pencilCanvas.drawingGestureRecognizer.isEnabled = true
        pencilCanvas.drawingPolicy = .anyInput
        pencilCanvas.isScrollEnabled = false
        pencilCanvas.tool = (tool == .pen) ? inkingTool : eraserTool

        // 关键：禁用覆盖层交互
        overlayContainerView.isUserInteractionEnabled = false

    case .image, .arrow, .rectangle, .text, .annotation:
        pencilCanvas.isUserInteractionEnabled = true
        pencilCanvas.drawingGestureRecognizer.isEnabled = false
        pencilCanvas.drawingPolicy = .default
        pencilCanvas.isScrollEnabled = false

        // 这些工具可能需要与覆盖层交互
        overlayContainerView.isUserInteractionEnabled = true
        objectLayerView.isUserInteractionEnabled = true
    }
}
```

##### 步骤 8：修改 layoutSubviews() 方法

**文件**：`NativeCanvasView.swift`

**位置**：第 193-197 行

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    // 对象图层始终保持画布大小
    objectLayerView.frame = CGRect(origin: .zero, size: canvasSize)
    // 同步覆盖层变换
    syncOverlayTransform()
}
```

##### 步骤 9：删除旧的 setupPencilCanvas() 中的 objectLayerView 相关代码

**文件**：`NativeCanvasView.swift`

**位置**：第 622-657 行的 `setupPencilCanvas()` 方法

**修改内容**：删除第 643 行 `pencilCanvas.insertSubview(objectLayerView, at: 0)`

```swift
private func setupPencilCanvas() {
    pencilCanvas.backgroundColor = .white
    pencilCanvas.isOpaque = true
    pencilCanvas.tool = inkingTool
    pencilCanvas.delegate = self

    pencilCanvas.contentSize = canvasSize
    pencilCanvas.minimumZoomScale = minZoomScale
    pencilCanvas.maximumZoomScale = maxZoomScale

    pencilCanvas.showsVerticalScrollIndicator = false
    pencilCanvas.showsHorizontalScrollIndicator = false
    pencilCanvas.bounces = true
    pencilCanvas.bouncesZoom = true

    // 删除这行！不再将 objectLayerView 插入到 pencilCanvas 中
    // pencilCanvas.insertSubview(objectLayerView, at: 0)  <- 删除

    // 插入到 overlayContainerView 下方
    insertSubview(pencilCanvas, belowSubview: overlayContainerView)

    pencilCanvas.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        pencilCanvas.topAnchor.constraint(equalTo: topAnchor),
        pencilCanvas.leadingAnchor.constraint(equalTo: leadingAnchor),
        pencilCanvas.trailingAnchor.constraint(equalTo: trailingAnchor),
        pencilCanvas.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])

    updateForTool(currentTool)
}
```

---

## 四、修改文件清单

| 文件 | 修改类型 | 说明 |
|:---|:---:|:---|
| `NativeCanvasView.swift` | 修改 | 主要修改文件，涉及视图层级重构 |

### 4.1 NativeCanvasView.swift 修改点汇总

| 行号范围 | 修改内容 |
|:---|:---|
| ~40-50 | 新增 `overlayContainerView` 属性声明 |
| 134-180 | 重写 `setupViews()` 方法 |
| 182-191 | 重写 `setupConstraints()` 方法 |
| 193-197 | 修改 `layoutSubviews()` 方法 |
| ~450-550 | 修改 `updateForTool()` 方法，添加 `overlayContainerView` 处理 |
| 582-620 | 重写 `recreateCanvasViewWithDrawing()` 方法 |
| 622-657 | 修改 `setupPencilCanvas()` 方法，删除 objectLayerView 相关代码 |
| 新增 | 添加 `setupPencilCanvasOnly()` 方法 |
| 新增 | 添加 `syncOverlayTransform()` 方法 |
| UIScrollViewDelegate | 在 `scrollViewDidScroll` 和 `scrollViewDidZoom` 中调用 `syncOverlayTransform()` |

---

## 五、测试用例

### 5.1 基础功能测试

| 测试项 | 操作步骤 | 预期结果 |
|:---|:---|:---|
| 单独绘制箭头 | 选择箭头工具，在画布上拖动绘制 | 箭头正常显示 |
| 单独绘制笔画 | 选择画笔工具，绘制一条线 | 笔画正常显示 |
| 箭头+笔画混合 | 先绘制箭头，再绘制3条笔画 | 所有内容正常显示 |

### 5.2 撤销功能测试

| 测试项 | 操作步骤 | 预期结果 |
|:---|:---|:---|
| 撤销笔画 | 绘制箭头 → 绘制3条笔画 → 撤销 | 只有笔画3消失，箭头保留 |
| 连续撤销 | 继续撤销 | 笔画2消失 → 笔画1消失 → 箭头消失 |
| 恢复笔画 | 在上述基础上恢复 | 箭头恢复 → 笔画1恢复 → 笔画2恢复 → 笔画3恢复 |

### 5.3 视图同步测试

| 测试项 | 操作步骤 | 预期结果 |
|:---|:---|:---|
| 缩放同步 | 绘制箭头后，使用缩放滑块缩放画布 | 箭头随画布同步缩放 |
| 平移同步 | 选择平移工具，拖动画布 | 箭头随画布同步移动 |
| 选择功能 | 选择工具模式下点击箭头 | 箭头可被正常选中，显示选中边框 |
| 拖动箭头 | 选中箭头后拖动 | 箭头可正常移动 |

### 5.4 边界情况测试

| 测试项 | 操作步骤 | 预期结果 |
|:---|:---|:---|
| 多次撤销恢复 | 反复撤销和恢复10次以上 | 状态始终一致，无异常 |
| 清屏后重建 | 清屏 → 撤销清屏 | 所有内容正确恢复 |
| 保存加载 | 保存文档 → 关闭 → 重新打开 | 箭头和笔画都正确恢复 |

---

## 六、风险评估

### 6.1 潜在风险

| 风险 | 等级 | 应对措施 |
|:---|:---:|:---|
| 手势冲突 | 中 | 通过 `isUserInteractionEnabled` 控制手势穿透 |
| 性能影响 | 低 | 变换计算简单，影响可忽略 |
| 坐标转换错误 | 中 | 仔细测试缩放和平移场景 |

### 6.2 回退方案

如果方案 A 遇到不可预见的问题，可以考虑方案 B：

**方案 B：避免 PKCanvasView 重建**

将 `shouldRecreateCanvasViewOnLoad` 设置为 `false`，使用 `loadDrawingUsingAppend()` 方法加载绘图数据，避免重建 PKCanvasView。

```swift
// NativeCanvasView.swift 第 ~95 行
private let shouldRecreateCanvasViewOnLoad = false  // 改为 false
```

此方案风险：可能在某些边界情况下有内存泄漏或状态残留问题。

---

## 七、参考资料

- [simonbs/InfiniteCanvas](https://github.com/simonbs/InfiniteCanvas) - PKCanvasView 无限画布实现
- [codelynx/PKCanvasViewTester](https://github.com/codelynx/PKCanvasViewTester) - PKCanvasView 测试项目
- [Asana/Drawsana](https://github.com/Asana/Drawsana) - iOS 绘图库，参考其分层架构
- [PKCanvasView | Apple Developer Documentation](https://developer.apple.com/documentation/pencilkit/pkcanvasview)
- [Drawing Over Image With PencilKit](https://particle41.com/insights/drawing-over-image-with-pencilkit/) - PencilKit 覆盖层最佳实践
- [SwiftUI/PencilKit: Infinite Canvas](https://levelup.gitconnected.com/swiftui-pencilkit-infinite-canvas-1b5360438a5c) - 无限画布实现参考

---

## 八、实施检查清单

- [ ] 阅读并理解本方案
- [ ] 备份当前 `NativeCanvasView.swift` 文件
- [ ] 按步骤 1-9 逐步修改代码
- [ ] 编译通过，无错误
- [ ] 执行 5.1 基础功能测试
- [ ] 执行 5.2 撤销功能测试
- [ ] 执行 5.3 视图同步测试
- [ ] 执行 5.4 边界情况测试
- [ ] 在真机上验证（排除 Simulator 特有问题）
- [ ] 更新 CHANGELOG.md
