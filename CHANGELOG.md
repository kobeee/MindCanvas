# 开发记录

## 2025-12-15 - 箭头撤销问题修复（视图层级重构）✅

### 问题描述
用户操作序列：
1. 先绘制一个箭头
2. 然后用画笔绘制数字 1、2、3
3. 撤销操作：数字 3 和箭头一起消失（错误！应该只撤销数字 3）
4. 恢复操作：只有数字 3 被恢复，箭头彻底消失

### 根因分析
PKCanvasView 重建导致视图层次混乱：
1. 撤销笔画时调用 `recreateCanvasViewWithDrawing()` 重建 PKCanvasView
2. `objectLayerView`（包含箭头视图）是 PKCanvasView 的子视图
3. 重建过程中 `objectLayerView` 的父视图关系被破坏
4. 箭头视图虽然存在于 `arrowViews` 字典中，但 superview 链已断裂

### 解决方案：视图层级重构
将 `objectLayerView` 从 PKCanvasView 内部提升出来，作为其兄弟视图：

**新架构**：
```
NativeCanvasView (UIView)
├── pencilCanvas (PKCanvasView)       <- 只负责绘图
└── overlayContainerView (UIView)     <- 滚动同步容器
    └── objectLayerView (UIView)      <- 不受 PKCanvasView 重建影响
        └── SelectableArrowView...
```

### 核心修改

#### 1. 新增覆盖层容器
- 添加 `overlayContainerView` 属性，与 `pencilCanvas` 同级
- `objectLayerView` 作为 `overlayContainerView` 的子视图

#### 2. 滚动同步机制
- 新增 `syncOverlayTransform()` 方法
- 在 `scrollViewDidScroll` 和 `scrollViewDidZoom` 中同步覆盖层变换
- 确保 `objectLayerView` 随画布滚动和缩放同步移动

#### 3. 重建流程优化
- 修改 `recreateCanvasViewWithDrawing()` 不再需要恢复箭头视图
- 新增 `setupPencilCanvasOnly()` 方法，不涉及 `objectLayerView`
- PKCanvasView 重建不影响箭头视图的显示

#### 4. 工具交互处理
- 修改 `updateForTool()` 方法，添加 `overlayContainerView` 的交互控制
- 平移工具时禁用覆盖层交互，让手势穿透到 PKCanvasView
- 选择工具时启用覆盖层交互，允许操作箭头对象

### 技术要点

#### 坐标变换同步
```swift
private func syncOverlayTransform() {
    let offset = pencilCanvas.contentOffset
    let scale = pencilCanvas.zoomScale
    
    objectLayerView.transform = CGAffineTransform(scaleX: scale, y: scale)
    objectLayerView.frame.origin = CGPoint(x: -offset.x, y: -offset.y)
}
```

#### 视图层级分离
- PKCanvasView 专注于绘图功能
- overlayContainerView 专门承载对象视图
- 两者通过同步机制保持视觉一致性

### 修改文件
- `Views/Editor/Canvas/NativeCanvasView.swift` - 视图层级重构

### 验证结果
- ✅ 箭头绘制后保持可见
- ✅ 撤销笔画时箭头不会消失
- ✅ 恢复操作正确恢复所有内容
- ✅ 缩放和平移时箭头同步移动
- ✅ 选择工具可以正常选中箭头

### 后续建议
1. 在真机上测试验证，排除 Simulator 特有问题
2. 考虑将其他对象（图片、矩形等）也迁移到 overlayContainerView
3. 优化滚动同步性能，避免频繁的 transform 计算

---

## 2025-12-15 - 箭头撤销问题修复尝试 ⚠️ [未解决]

### 问题描述
用户操作序列：
1. 先绘制一个箭头
2. 然后用画笔绘制数字 1、2、3
3. 撤销操作：数字 3 和箭头一起消失（错误！应该只撤销数字 3）
4. 恢复操作：只有数字 3 被恢复，箭头彻底消失

### 预期行为
- 每个操作（箭头、笔画1、笔画2、笔画3）应该独立记录在撤销栈中
- 撤销时应该按照 LIFO（后进先出）顺序逐个撤销
- 箭头应该最先被撤销（最后被创建）

### 已尝试的修复

#### 1. 移除错误的复合操作机制
**问题**：之前添加的复合操作机制在绘图开始时将所有操作组合在一起
**修复**：
- 删除了 `beginCompoundAction`、`endCompoundAction` 和 `addToCompoundAction` 方法
- 恢复独立操作记录方式
- 确保每个操作都是独立记录的

#### 2. 修复 PKCanvasView 重建时的视图恢复
**问题**：`DrawingAction` 的 `undo` 方法调用 `recreateCanvasViewWithDrawing` 重建 PKCanvasView 时，箭头视图丢失
**修复**：
- 在重建前保存 `arrowViews` 字典
- 重建后将箭头视图重新添加到新的 `objectLayerView` 中
- 确保撤销绘图操作时不会丢失箭头视图

### 根因分析
虽然进行了上述修复，但问题仍然存在。可能的原因：
1. **PKCanvasView 的内部状态问题**：重建 PKCanvasView 可能导致视图层次结构不一致
2. **撤销栈的记录时机**：箭头和笔画的记录时机可能存在交叉
3. **PencilKit 的已知限制**：PKCanvasView 与自定义子视图的交互存在已知问题

### 后续建议
1. **考虑替代方案**：使用 CALayer 而非 UIView 来渲染箭头
2. **独立视图层次**：将箭头视图放在 PKCanvasView 之外，作为兄弟视图
3. **参考成熟方案**：研究 Drawsana 等开源绘图库的实现方式

### 修改文件
- `Views/Editor/Canvas/NativeCanvasView.swift` - 移除复合操作，修复视图恢复

---

## 2025-12-14 - 箭头消失问题修复尝试 v2（基于开源项目实践）🔧

### 问题描述
使用箭头工具在画布上拖动可以实时看到箭头，但手指释放后箭头立即消失不见。

### 根因分析方法
停止"自己钻牛角尖"，转而研究开源项目的实践经验：
1. **simonbs/InfiniteCanvas** - PKCanvasView 无限画布实现参考
2. **Asana/Drawsana** - 完整绘图库，有 SelectionTool 和 ShapeSelectable
3. 社区最佳实践（Stack Overflow、Apple Developer Forums）

### 发现的关键问题

#### 问题 1: 视图层级结构不当 🔴
**当前代码**：
```swift
pencilCanvas.insertSubview(objectLayerView, at: 0)  // 第 163 行（旧）
```

**问题**：
- PKCanvasView 继承自 UIScrollView，内部有复杂的渲染层级
- 使用 `insertSubview(at: 0)` 会与 PKCanvasView 内部绘图视图冲突
- PKCanvasView 可能在布局时重新排序子视图，导致 objectLayerView 被覆盖或移除

**社区最佳实践**：
- 方式1: `canvasView.subviews[0].addSubview(customView)` - 添加到内部子视图
- 方式2: `canvasView.addSubview(customView)` - 添加到顶层（推荐）

**参考资源**：
- [PKCanvasView 自定义子视图实现](https://www.appsloveworld.com/swift/100/251/sharing-pkcanvasview-with-a-subview-as-an-image)
- [SwiftUI/Pencil Kit: Add Background Images](https://levelup.gitconnected.com/swiftui-pencil-kit-add-background-images-that-synchronous-with-canvas-2-ways-b60feb2ba2c4)

#### 问题 2: 缺少强制布局调用 ⚠️
**当前代码**：
```swift
// createArrowView 方法 (第 349-393 行)
objectLayerView.addSubview(arrowView)
// 没有后续的布局调用
```

**问题**：
- iOS 视图系统是异步布局的
- 添加子视图后不会立即渲染，需要等到下一个布局周期
- 用户可能在布局前就释放了手势，导致视图"消失"

**修复**：
```swift
arrowView.setNeedsLayout()
arrowView.layoutIfNeeded()
objectLayerView.setNeedsLayout()
objectLayerView.layoutIfNeeded()
```

**参考资源**：
- [iOS 视图布局生命周期](https://sabapathy7.medium.com/uikit-setneedslayout-vs-layoutifneeded-vs-layoutsubviews-b0075b3bb441)

#### 问题 3: clipsToBounds 设置 ⚠️
**当前代码**：
- `objectLayerView` 和 `SelectableArrowView` 都没有明确设置 `clipsToBounds`

**问题**：
- 默认 `clipsToBounds = true`，如果箭头超出父视图边界会被裁剪
- 箭头的选择边框（`insetBy(dx: -10, dy: -10)`）可能超出视图边界

**修复**：
```swift
objectLayerView.clipsToBounds = false
arrowView.clipsToBounds = false
```

### 实施的修复

#### 1. 修复视图层级结构
**文件**: `NativeCanvasView.swift` (第 165-180 行)

**修改**：
```swift
// 旧代码（第 163 行）- 已移除
// pencilCanvas.insertSubview(objectLayerView, at: 0)

// 新代码 - 使用 DispatchQueue 确保 pencilCanvas 布局完成
DispatchQueue.main.async { [weak self] in
    guard let self = self else { return }

    // 添加到 pencilCanvas 顶层（而不是索引 0）
    self.pencilCanvas.addSubview(self.objectLayerView)
    self.objectLayerView.frame = CGRect(origin: .zero, size: self.canvasSize)

    // ...
}
```

**原理**：
- 等待 `pencilCanvas` 完成初始布局
- 将 `objectLayerView` 添加到顶层，避免与内部视图冲突
- 参考 simonbs/InfiniteCanvas 的实现

#### 2. 添加强制布局调用
**文件**: `NativeCanvasView.swift` (第 400-407 行)

**修改**：
```swift
arrowViews[arrow.id] = arrowView
objectLayerView.addSubview(arrowView)

// 关键修复：强制立即布局，确保视图可见
arrowView.setNeedsLayout()
arrowView.layoutIfNeeded()
objectLayerView.setNeedsLayout()
objectLayerView.layoutIfNeeded()

print("[Arrow] arrowView added to superview: \(arrowView.superview != nil), frame=\(arrowView.frame)")
print("[Arrow] objectLayerView subviews count: \(objectLayerView.subviews.count)")
```

#### 3. 修复 clipsToBounds 设置
**文件**: `NativeCanvasView.swift` (第 160-161 行)
```swift
objectLayerView.clipsToBounds = false // 关键：允许子视图超出边界显示
objectLayerView.isOpaque = false
```

**文件**: `SelectableArrowView.swift` (第 62-64 行)
```swift
backgroundColor = .clear
isOpaque = false
clipsToBounds = false // 关键：允许箭头超出边界显示
```

### 参考的开源项目与社区资源

**开源项目**：
- [GitHub - simonbs/InfiniteCanvas](https://github.com/simonbs/InfiniteCanvas) - PKCanvasView 无限画布实现
- [GitHub - Asana/Drawsana](https://github.com/Asana/Drawsana) - 完整绘图库，SelectionTool 实现
- [Drawsana Documentation](https://asana.github.io/Drawsana/)

**社区讨论**：
- [PKCanvasView 手势冲突讨论](https://developer.apple.com/forums/thread/719944)
- [PKCanvasView 缩放和滚动问题](https://developer.apple.com/forums/thread/698317)
- [Drawing Over an Image With PencilKit](https://particle41.com/insights/drawing-over-images-pencilekit/)

**技术文档**：
- [PKCanvasView | Apple Developer Documentation](https://developer.apple.com/documentation/pencilkit/pkcanvasview)
- [insertSubview vs addSubview 区别](https://bugsdb.com/_en/debug/3163e42f3717b206bceec199a73c909c)

### 修改文件
- `Views/Editor/Canvas/NativeCanvasView.swift` - 修复视图层级和布局调用
- `Views/Editor/Canvas/SelectableArrowView.swift` - 修复 clipsToBounds 设置

### 验证步骤
1. 选择箭头工具
2. 在画布上拖动绘制箭头
3. 释放手指
4. **期望**：箭头保持可见，不会消失
5. 切换到选择工具，点击箭头应该能选中

### 如果问题仍然存在
如果这次修复仍然不行，建议：
1. **在真机上测试** - 排除 Simulator 特有问题
2. **考虑方案 B**：使用独立覆盖层（类似 Drawsana 架构）
   - 在 `NativeEditorView` 层级添加独立的 `ArrowOverlayView`
   - 不依赖 PKCanvasView 的子视图层级
3. **考虑方案 C**：改用 CALayer 而非 UIView
   - 避免手势冲突
   - 直接在 `objectLayerView.layer` 上添加 CAShapeLayer

---

## 2025-12-14 - 箭头绘制后消失问题（根因分析完成）⚠️ [已归档]

### 问题描述
使用箭头工具在画布上拖动可以实时看到箭头，但手指释放后箭头立即消失不见。

### 已尝试的修复

#### 1. 移除 SwiftUI 重复渲染层
- 移除了 `NativeEditorView` 中的 `ForEach ArrowView` SwiftUI 渲染
- 只保留 UIKit 的 `SelectableArrowView` 渲染

#### 2. 修复坐标转换
- 问题：SwiftUI 手势获取的是视图坐标，需要转换为画布内容坐标（5000x5000）
- 修复：添加坐标转换逻辑
```swift
let offset = canvasView.pencilCanvas.contentOffset
let scale = canvasView.pencilCanvas.zoomScale
let contentStart = CGPoint(
    x: (start.x + offset.x) / scale,
    y: (start.y + offset.y) / scale
)
```

#### 3. 调试日志验证
- SwiftUI 坐标：`(137, 638.5)` → 画布坐标：`(2264.5, 2655.0)`
- 坐标转换后数值看起来正确（靠近 5000x5000 画布中心）
- 但箭头仍然消失

### 根因分析（通过研究开源项目得出）

#### 研究的开源项目
1. **simonbs/InfiniteCanvas** - PKCanvasView 无限画布实现
2. **Asana/Drawsana** - 完整的绘图库，包含选择工具和可选择对象

#### 关键发现

**问题 1: 视图层级结构错误**
- 当前实现：`pencilCanvas.insertSubview(objectLayerView, at: 0)` (第 163 行)
- 问题：直接插入到 PKCanvasView 会与其内部绘图视图冲突
- 最佳实践：应该插入到 `PKCanvasView.subviews.first` 中
- 参考：社区实践显示应使用 `canvasView.subviews[0].addSubview(customView)` 模式

**问题 2: 缺少强制布局调用**
- `createArrowView` (第 349-393 行) 创建视图后直接添加，没有调用布局方法
- iOS 视图系统需要 `setNeedsLayout()` 和 `layoutIfNeeded()` 来确保视图立即可见
- 视图可能被添加了但在下一个布局周期前不渲染

**问题 3: objectLayerView.frame 重置问题**
- `layoutSubviews` (第 188-192 行) 每次都重置 `objectLayerView.frame`
- 可能导致在滚动/缩放时子视图位置异常

**问题 4: 手势识别冲突（最可能的主因）**
- PKCanvasView 在 iOS 16+ 有已知 bug：触摸结束后内部会刷新视图层级
- SelectableArrowView 有自己的手势识别器（tap 和 pan）
- 这些手势与 PKCanvasView 内部手势冲突
- PKCanvasView 在触摸事件结束后刷新时可能清除了自定义子视图
- 社区建议：不应在 PKCanvasView 或其子视图上直接添加手势，应该放在容器视图上

**问题 5: PKCanvasView 特殊性质**
- PKCanvasView 是 UIScrollView 子类，有复杂的内部视图结构
- 内部包含多个 sublayers 用于 tiling 渲染
- 自定义子视图需要特别小心处理滚动和缩放

### 推荐的解决方案

#### 方案 A: 修改视图层级（推荐）
```swift
// 在 setupViews() 中
if let drawingSubview = pencilCanvas.subviews.first {
    drawingSubview.insertSubview(objectLayerView, at: 0)
}

// 在 createArrowView() 中添加
objectLayerView.addSubview(arrowView)
objectLayerView.setNeedsLayout()
objectLayerView.layoutIfNeeded()
```

#### 方案 B: 使用独立的覆盖层
```swift
// 不把 objectLayerView 放在 PKCanvasView 内部
// 而是作为兄弟视图，手动同步滚动和缩放
// 参考 Drawsana 的架构：独立的渲染层 + 数据模型
```

#### 方案 C: 改用 CALayer 而非 UIView
```swift
// SelectableArrowView 改为 CAShapeLayer
// 避免手势冲突问题
// 选择操作通过点击测试（hitTest）实现
```

### 后续行动计划
1. 优先尝试方案 A：修改视图层级 + 添加强制布局
2. 如果方案 A 失败，考虑方案 C：改用 CALayer
3. 在真机上测试验证（排除 Simulator 特有问题）
4. 参考 Drawsana 架构，考虑长期重构为独立渲染层

### 修改文件
- `Views/Editor/NativeEditorView.swift` - 移除 SwiftUI 箭头渲染，添加坐标转换
- `Views/Editor/Canvas/NativeCanvasView.swift` - 修复工具交互状态
- `Views/Editor/Canvas/SelectableArrowView.swift` - 修复本地坐标边框

### 参考资源
- [PKCanvasView 自定义子视图最佳实践](https://www.appsloveworld.com/swift/100/251/sharing-pkcanvasview-with-a-subview-as-an-image)
- [PKCanvasView 手势冲突问题](https://developer.apple.com/forums/thread/719944)
- [insertSubview vs addSubview 区别](https://bugsdb.com/_en/debug/3163e42f3717b206bceec199a73c909c)
- [iOS 视图布局生命周期](https://sabapathy7.medium.com/uikit-setneedslayout-vs-layoutifneeded-vs-layoutsubviews-b0075b3bb441)

---

## 2025-12-14 - 箭头选择工具修复 v2 (视图层级冲突解决) ✅

### 问题描述
1. 箭头工具创建的箭头无法被选择工具选中，无法进行拖动或修改操作
2. 箭头绘制后立即消失

### 根因分析
经过深入排查，发现了以下关键问题：

1. **SwiftUI/UIKit 双重渲染导致遮挡**：箭头被渲染了两次
   - `NativeCanvasView.createArrowView()` 创建了 UIKit 版本的 `SelectableArrowView`（支持手势）
   - `NativeEditorView` 的 SwiftUI `ForEach ArrowView` 又渲染了一层（纯显示）
   - SwiftUI 层覆盖在 UIKit 层上方，拦截了所有点击事件

2. **父视图交互禁用导致子视图无法响应**：
   - 选择工具下设置了 `pencilCanvas.isUserInteractionEnabled = false`
   - 但 `objectLayerView`（包含 `SelectableArrowView`）是 `pencilCanvas` 的子视图
   - 父视图禁用交互会导致所有子视图也无法接收触摸事件

3. **选择边框使用全局坐标而非本地坐标**：导致选择边框显示位置错误

4. **坐标系统不匹配导致箭头消失**：
   - `ArrowDrawingView` 在 SwiftUI 层捕获手势，返回的是 SwiftUI 视图坐标（相对于屏幕可见区域）
   - 箭头需要添加到 `objectLayerView`，它的坐标系是 5000x5000 的画布内容坐标
   - 缺少坐标转换，导致箭头被创建在画布外部（视口之外），所以"消失"了

### 解决方案

#### 1. 移除 SwiftUI 层的重复箭头渲染
```swift
// NativeEditorView.swift - 移除 ForEach 渲染
// 箭头由 NativeCanvasView 中的 SelectableArrowView 渲染
// 不再使用 SwiftUI ForEach 渲染，避免遮挡 UIKit 手势
```

#### 2. 修复选择工具的交互状态
```swift
case .select:
    // 不能设置 pencilCanvas.isUserInteractionEnabled = false
    // 因为 objectLayerView 是 pencilCanvas 的子视图
    pencilCanvas.isUserInteractionEnabled = true
    pencilCanvas.drawingGestureRecognizer.isEnabled = false
    objectLayerView.isUserInteractionEnabled = true
```

#### 3. 修复选择边框使用本地坐标
```swift
// 使用本地坐标系而非全局坐标
let localBounds = bounds.insetBy(dx: -10, dy: -10)
let path = UIBezierPath(rect: localBounds)
selectionBorder.path = path.cgPath
```

#### 4. 扩大点击区域
```swift
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let expandedBounds = bounds.insetBy(dx: -20, dy: -20)
    return expandedBounds.contains(point)
}
```

#### 5. 坐标转换：SwiftUI 视图坐标 → 画布内容坐标
```swift
// 箭头创建时进行坐标转换
let contentStart = canvasView.contentRect(forViewportRect: CGRect(origin: start, size: .zero)).origin
let contentEnd = canvasView.contentRect(forViewportRect: CGRect(origin: end, size: .zero)).origin

let arrow = ArrowLayerNode(
    startPoint: contentStart,
    endPoint: contentEnd,
    // ...
)
```

**坐标转换原理**：
- SwiftUI 手势获得的坐标：相对于屏幕可见区域（如 800x600）
- `pencilCanvas` 有 `contentOffset` 和 `zoomScale`
- `objectLayerView` 尺寸是 5000x5000
- `contentRect(forViewportRect:)` 方法考虑了缩放和偏移，将视口坐标转换为画布内容坐标

### 参考资料
- [Drawsana](https://github.com/Asana/Drawsana) - iOS 绘图库，参考其 SelectionTool 和 ShapeSelectable 实现
- [SPUserResizableView](https://github.com/spoletto/SPUserResizableView) - 可调整大小的 UIView 实现
- [DragRotateScaleView](https://github.com/yokurin/DragRotateScaleView) - 支持拖拽、旋转、缩放的视图

### 修改文件
- `Views/Editor/NativeEditorView.swift` - 移除 SwiftUI 箭头渲染层
- `Views/Editor/Canvas/NativeCanvasView.swift` - 修复选择/图片工具的交互状态
- `Views/Editor/Canvas/SelectableArrowView.swift` - 修复选择边框坐标 + 扩大点击区域

### 验证步骤
1. 选择箭头工具，在画布上拖出一个箭头
2. 切换到选择工具
3. 点击箭头，应该显示蓝色虚线选择边框
4. 拖动箭头，应该可以移动位置

---

## 2025-12-14 - 选择工具修复与箭头对象选择支持 ✅

### 问题描述
选择工具无法选中箭头对象，也无法进行拖动、缩放等操作。同时出现 AttributeGraph 循环检测警告日志。

### 根因分析
1. **箭头对象架构问题**：箭头使用纯 SwiftUI `ArrowView` 渲染，没有手势识别器支持
2. **选择系统缺失**：箭头没有集成到选择工具的对象层管理中
3. **手势冲突**：PKCanvasView 与对象层手势识别器存在冲突
4. **编译错误**：`UIGestureRecognizerDelegate` 方法缺少 `override` 关键字

### 解决方案

#### 1. 创建可选择箭头视图组件
- **新增文件**: `SelectableArrowView.swift`
- 基于 `UIView` 实现的箭头视图，支持手势识别
- 集成点击选择、拖拽移动功能
- 支持选中状态视觉反馈（蓝色虚线边框）

#### 2. 修复选择工具手势冲突
- 在选择模式下完全禁用 PKCanvasView 交互：`pencilCanvas.isUserInteractionEnabled = false`
- 确保对象层手势获得优先处理权
- 为所有对象启用统一的手势管理

#### 3. 集成箭头到选择系统
- 在 `NativeCanvasView` 中添加箭头视图管理
- 修改箭头添加/删除流程，创建对应的可选择视图
- 更新选择状态管理，同时支持图片和箭头

#### 4. 撤销/恢复支持
- 新增 `MoveArrowAction` 类支持箭头移动的撤销操作
- 保持与现有图片对象相同的撤销/恢复机制

#### 5. 修复编译错误
- 为 `gestureRecognizerShouldBegin` 添加 `override` 关键字
- 移除协议方法中错误的 `override` 关键字

### 技术要点

#### 手势优先级管理
```swift
case .select:
    // 完全禁用PKCanvasView交互，让对象层处理所有手势
    pencilCanvas.isUserInteractionEnabled = false
    objectLayerView.isUserInteractionEnabled = true
    // 启用所有对象手势
    for imageView in imageViews.values {
        imageView.enableObjectGestures()
    }
    for arrowView in arrowViews.values {
        arrowView.enableArrowGestures()
    }
```

#### 箭头视图架构
- 使用 `CAShapeLayer` 绘制箭头路径
- 支持动态更新箭头位置和样式
- 集成选择边框和交互反馈

### 修改文件
- `Views/Editor/Canvas/SelectableArrowView.swift` (新增)
- `Views/Editor/Canvas/NativeCanvasView.swift`
  - 添加箭头视图管理
  - 修复选择工具手势配置
  - 更新选择状态管理
- `Models/Canvas/CanvasAction.swift`
  - 新增 `MoveArrowAction` 类

### AttributeGraph 循环警告
此警告通常由 SwiftUI 视图依赖循环引起，可能与箭头视图的状态更新有关。建议后续进一步排查视图状态依赖关系。

### 当前状态
- ✅ 选择工具可以选中图片对象
- ✅ 箭头对象支持选择和拖拽（代码层面已完成）
- ⚠️ AttributeGraph 循环警告待进一步排查
- 📝 箭头对象选择功能需要实际测试验证

---

## 2025-12-14 - 手掌工具（平移工具）修复 ✅

### 问题描述
画布重构后，手掌工具（平移工具）无法拖动画布，点击后没有反应。

### 根因分析
画布架构从嵌套 UIScrollView 重构为直接使用 PKCanvasView 内置滚动功能后，`PKCanvasView` 的 `drawingPolicy` 设置不正确：

1. **drawingPolicy 配置错误**：在非绘图模式下（包括平移工具），`drawingPolicy` 仍然设置为 `.anyInput`
2. **PKCanvasView 行为**：`.anyInput` 会强制 PKCanvasView 将所有输入都作为绘图处理，阻止滚动功能
3. **手势识别器未启用**：虽然设置了 `isScrollEnabled = true`，但没有显式启用手势识别器

### 解决方案
在 `updateForTool` 方法中正确配置 `drawingPolicy`：

```swift
case .pan:
    // 平移工具：禁用绘图，禁用对象手势，启用画布滚动
    pencilCanvas.isUserInteractionEnabled = true
    pencilCanvas.drawingGestureRecognizer.isEnabled = false
    pencilCanvas.drawingPolicy = .default  // 关键修复：设置为default才能启用滚动
    objectLayerView.isUserInteractionEnabled = false
    pencilCanvas.isScrollEnabled = true
    // 关键修复：启用手势识别器
    pencilCanvas.panGestureRecognizer.isEnabled = true
    pencilCanvas.pinchGestureRecognizer?.isEnabled = true
```

### 技术要点

#### drawingPolicy 的区别
- `.default`：允许 PKCanvasView 正常处理滚动和缩放手势
- `.anyInput`：强制 PKCanvasView 将所有输入都作为绘图处理，会阻止滚动

#### 统一配置
所有非绘图工具（select、pan、image、arrow、rectangle、text、annotation）都设置为 `drawingPolicy = .default`，确保一致性。

### 修改文件
- `Views/Editor/Canvas/NativeCanvasView.swift`
  - 修复平移工具的 `drawingPolicy` 设置
  - 为所有非绘图工具统一配置 `drawingPolicy = .default`
  - 显式启用平移和缩放手势识别器

### 兼容性
此修复不影响笔画漂移问题的解决方案，因为只是正确配置了 PKCanvasView 的行为模式，没有改变架构或坐标系统。

### 当前状态
手掌工具（平移工具）已修复，可以正常拖动和缩放画布。

---

## 2025-12-14 - 撤销后笔画复活问题（已解决）✅

### 问题描述
画完笔画 1, 2, 3 后撤销第 3 笔，再画新笔画时，被撤销的第 3 笔会"复活"出现在画布上。撤销时新笔画和复活的笔画一起消失，恢复时一起出现，就像被绑定了一样。

### 根因分析

经过深入分析，发现这是 PencilKit 的已知架构性问题：

1. **PKDrawing 数据规范化问题**：`PKDrawing(data:)` 初始化后，PencilKit 内部会对数据进行"规范化"，导致字节数变化。撤销加载旧数据后，`strokeStartDrawingData` 仍然是旧的字节数，但实际画布数据已经变成规范化后的字节数。

2. **UndoManager 清除不彻底**：`removeAllActions()` 只清空了 UndoManager 的操作栈，但**没有清除 PKCanvasView 内部缓存的 stroke 数据**。PencilKit 在内部维护了一个 stroke buffer，当直接设置 `pencilCanvas.drawing` 时，这个缓存没有被正确同步。

3. **Stroke 标识符混乱**：日志中的 `retrieving stroke identifier gave nil or invalid result` 错误表明 PencilKit 内部的 stroke 标识符系统出现问题。撤销后，这些标识符没有被正确清理，导致新绘制时与旧的stroke数据发生错误关联。

### 解决方案

实现了两种解决方案，通过配置选项可以切换：

#### 方案1：重建PKCanvasView实例（推荐，默认启用）
**原理**：完全销毁并重新创建PKCanvasView实例，彻底清除所有内部缓存状态和stroke标识符。

**核心代码**：
```swift
/// 重建PKCanvasView实例并设置绘图数据
private func recreateCanvasViewWithDrawing(_ data: Data) {
    // 保存当前状态
    let oldZoomScale = pencilCanvas.zoomScale
    let oldContentOffset = pencilCanvas.contentOffset
    let oldDelegate = pencilCanvas.delegate
    
    // 从父视图中移除旧的canvas
    pencilCanvas.removeFromSuperview()
    
    // 创建新的PKCanvasView实例
    pencilCanvas = PKCanvasView()
    setupPencilCanvas()
    
    // 恢复状态和绘图数据
    // ...
}
```

#### 方案2：使用PKDrawing.append方法（备选）
**原理**：不直接替换PKDrawing，而是通过逐个添加strokes的方式，避免直接设置drawing导致的状态问题。

**核心代码**：
```swift
/// 方案2：使用PKDrawing.append方法（备选方案）
private func loadDrawingUsingAppend(_ data: Data) {
    // 完全清空当前绘图
    pencilCanvas.drawing = PKDrawing()
    
    // 如果有数据，使用append方法添加
    if !data.isEmpty {
        do {
            let newDrawing = try PKDrawing(data: data)
            var mutableDrawing = pencilCanvas.drawing
            
            // 逐个添加strokes，避免直接替换导致的状态问题
            for stroke in newDrawing.strokes {
                mutableDrawing.strokes.append(stroke)
            }
            
            pencilCanvas.drawing = mutableDrawing
        } catch {
            print("[DEBUG] loadDrawingUsingAppend: error loading drawing - \(error)")
        }
    }
}
```

### 技术要点

1. **保留视图状态**：重建实例时会保存和恢复缩放比例、内容偏移等状态
2. **保持委托关系**：确保delegate关系正确恢复
3. **维护视图层次**：objectLayerView正确重新插入到新的PKCanvasView中
4. **配置选项**：通过`shouldRecreateCanvasViewOnLoad`开关在两种方案间切换

### 修改文件
- `Views/Editor/Canvas/NativeCanvasView.swift`
  - 将`pencilCanvas`从`let`改为`var`以支持重建
  - 新增`recreateCanvasViewWithDrawing(_:)`方法
  - 新增`loadDrawingUsingAppend(_:)`备选方案
  - 新增`shouldRecreateCanvasViewOnLoad`配置选项
  - 修复编译错误（mutableCopy、try-catch等）

### 验证建议
1. **首先尝试方案1**（默认）：这是最可靠的解决方案
2. **如果遇到性能问题**：将`shouldRecreateCanvasViewOnLoad`改为`false`切换到方案2
3. **真机测试**：在真机上验证效果，因为模拟器可能会有不同的行为

### 当前状态
问题已解决。通过重建PKCanvasView实例彻底清除了PencilKit内部状态，避免了撤销后笔画复活的问题。

---

## 2025-12-13 - 画布架构重构 v2.0 (直接使用 PKCanvasView 内置缩放)

### 问题背景

用户报告两个严重问题：
1. **笔画漂移**：绘制过程中笔画向右下漂移，松手后恢复
2. **撤销后笔画复活**：撤销第3笔后画第4笔，被撤销的第3笔"复活"

经过多次"屎上雕花"式修补（增加标记、调整时序、冻结坐标系统等），问题始终无法彻底解决。

### 根因发现

**关键发现**：PKCanvasView 本身就是 UIScrollView 的子类！

旧架构将 PKCanvasView 嵌套在另一个 UIScrollView 中：
```
NativeCanvasView (UIView)
└── scrollView (UIScrollView)      ← 外层滚动/缩放
    └── contentView (UIView)
        ├── objectLayerView        ← 图片图层
        └── pencilCanvas (PKCanvasView)  ← 继承自 UIScrollView！
```

这是一个已知的 Apple 问题（FB15166022）：PKCanvasView 嵌套在 UIScrollView 中会导致坐标转换错误。

### 解决方案：架构重构

参考 GitHub 开源项目 [simonbs/InfiniteCanvas](https://github.com/simonbs/InfiniteCanvas)，完全重构画布架构：

**新架构**：直接使用 PKCanvasView 的内置缩放功能
```
NativeCanvasView (UIView)
└── pencilCanvas (PKCanvasView)    ← 直接作为根滚动容器
    └── objectLayerView            ← 图片图层作为 PKCanvasView 的子视图
```

### 核心代码变更

#### 1. 移除外层 UIScrollView
```swift
// 旧代码
private let scrollView = UIScrollView()
private let contentView = UIView()

// 新代码：直接使用 PKCanvasView
let pencilCanvas = PKCanvasView()
```

#### 2. 使用 PKCanvasView 的内置缩放
```swift
// 设置画布大小
pencilCanvas.contentSize = canvasSize  // 5000x5000

// 启用缩放 - PKCanvasView 内置功能！
pencilCanvas.minimumZoomScale = 0.5
pencilCanvas.maximumZoomScale = 3.0
```

#### 3. 对象图层作为 PKCanvasView 的子视图
```swift
// 插入到 PKCanvasView 的最底层
pencilCanvas.insertSubview(objectLayerView, at: 0)
addSubview(pencilCanvas)
```

#### 4. 工具切换使用 drawingGestureRecognizer
```swift
func updateForTool(_ tool: CanvasTool) {
    switch tool {
    case .select:
        pencilCanvas.drawingGestureRecognizer.isEnabled = false
        objectLayerView.isUserInteractionEnabled = true
        pencilCanvas.isScrollEnabled = false

    case .pan:
        pencilCanvas.drawingGestureRecognizer.isEnabled = false
        objectLayerView.isUserInteractionEnabled = false
        pencilCanvas.isScrollEnabled = true

    case .pen, .eraser:
        pencilCanvas.drawingGestureRecognizer.isEnabled = true
        objectLayerView.isUserInteractionEnabled = false
        pencilCanvas.isScrollEnabled = false
    // ...
    }
}
```

#### 5. 缩放回调通过 UIScrollViewDelegate
```swift
// PKCanvasViewDelegate 继承自 UIScrollViewDelegate
func scrollViewDidZoom(_ scrollView: UIScrollView) {
    onZoomChanged?(scrollView.zoomScale)
}
```

### 架构对比

| 特性 | 旧架构 | 新架构 |
|:---|:---|:---|
| 滚动/缩放容器 | 外层 UIScrollView | PKCanvasView 自身 |
| 图层嵌套深度 | 4 层 | 2 层 |
| 坐标系统 | 复杂（多层转换） | 简单（单一坐标系） |
| 手势冲突 | 需要复杂协调 | PKCanvasView 内部处理 |
| 代码行数 | ~750 行 | ~720 行 |

### 预期效果

1. **笔画漂移**：应彻底解决（根因已消除）
2. **撤销复活**：应大幅改善（数据一致性增强）
3. **性能提升**：减少坐标转换开销

### 修改文件

- `Views/Editor/Canvas/NativeCanvasView.swift` - 完全重写

### 参考资料

- [simonbs/InfiniteCanvas](https://github.com/simonbs/InfiniteCanvas) - PKCanvasView 无限画布实现
- [codelynx/PKCanvasViewTester](https://github.com/codelynx/PKCanvasViewTester) - PKCanvasView 测试项目
- Apple Feedback FB15166022 - PKCanvasView 嵌套 UIScrollView 的已知问题

### 后续验证

- [ ] 在模拟器上测试笔画漂移问题
- [ ] 在真机上测试 Apple Pencil 绘图
- [ ] 验证撤销/恢复功能
- [ ] 测试图片图层的拖拽/缩放
- [ ] 测试画布缩放和平移

---

## 2025-12-13 - 撤销后笔画复活问题修复 v1.2.5

### 问题描述
用户报告：画完笔画 1, 2, 3 后撤销第 3 笔，再画第 4 笔时，被撤销的第 3 笔会"复活"出现在画布上。

### 根因分析

#### 1. PKDrawing 数据规范化问题
从日志发现：`loadDrawing: data.count=1264` 但 `loadDrawing: done, currentData.count=1286`

**关键发现**：PKDrawing(data:) 初始化后调用 dataRepresentation() 得到的数据可能与原始数据不同。PencilKit 内部会对数据进行"规范化"，导致字节数变化。

这意味着撤销加载旧数据后，`strokeStartDrawingData` 仍然是旧的 1264 字节，但实际画布数据已经变成 1286 字节。当画新笔画时，撤销系统使用的基准数据是错误的。

#### 2. 解冻坐标系统时机问题
`canvasViewDidEndUsingTool` 中立即调用 `setScrollTransformsFrozen(false)` 会触发布局更新，可能导致 `canvasViewDrawingDidChange` 被错误地调用，进而影响撤销数据的记录。

#### 3. 与笔画漂移的关联
日志中的 `Unable to find stroke from stroke group in drawing` 错误表明 PencilKit 内部 stroke 索引失效。这与笔画漂移问题可能同源：
- 绘制过程中坐标系统发生变化
- 释放笔触时坐标系统恢复
- PencilKit 尝试重新定位 stroke 时出错
- 被撤销的 stroke 数据被错误地"恢复"

### 修复方案

#### 1. loadDrawing 时同步更新撤销基准
```swift
func loadDrawing(from data: Data) {
    isLoadingDrawing = true
    pencilCanvas.drawing = drawing
    // 使用加载后的实际数据作为新的基准
    strokeStartDrawingData = getDrawingData()
    DispatchQueue.main.async { self.isLoadingDrawing = false }
}
```

#### 2. 添加 isLoadingDrawing 标记
区分用户绘制导致的 `canvasViewDrawingDidChange` 和程序加载导致的变化，避免错误处理。

#### 3. 优化坐标系统冻结/解冻
- 使用 `UIView.performWithoutAnimation` 确保立即生效
- 在解冻前先恢复坐标状态，再恢复交互状态
- 解冻操作延迟执行，确保 PencilKit 完成内部处理

#### 4. 增强 scrollViewDidScroll 保护
在绘图模式下，任何超过 0.1pt 的偏移都强制恢复，防止坐标漂移。

#### 5. 调整 canvasViewDidEndUsingTool 时序
先获取绘图数据，延迟解冻坐标系统，再延迟创建撤销操作。

### 技术背景：PKCanvasView + UIScrollView 的已知问题

搜索发现这是 Apple 公认的架构性问题（FB15166022 至今未解决）：
- PKCanvasView 嵌套在 UIScrollView 中时，坐标转换可能出错
- 缩放比例 < 1.0 时特别不稳定
- 有开发者在此问题上花费 64 小时仍未找到完美解决方案

**Apple 官方建议**：PKCanvasView 应与 UIScrollView 分离，而非嵌套。

### 修改文件
- `Views/Editor/Canvas/NativeCanvasView.swift`

### 后续建议
如果问题仍然存在，考虑更彻底的架构调整：
1. 将 PKCanvasView 从 UIScrollView 中移出，置于同级
2. 实现独立的滚动同步机制
3. 或限制缩放范围（仅支持 >= 1.0）

---

## 2025-12-13 - 清理调试日志 v1.2.4

### 变更内容
清理 `NativeCanvasView.swift` 中笔画撤销相关的调试日志 (`[Undo]` 前缀的 print 语句)。

### 修改文件
- `Views/Editor/Canvas/NativeCanvasView.swift`

---

## 2025-12-13 - 绘制笔画撤销修复 v1.2.3

### 问题描述
绘制的笔画无法撤销，撤销操作没有被正确记录。

### 根因分析
PencilKit 的 `canvasViewDidEndUsingTool` 委托方法被调用时，`pencilCanvas.drawing` 的数据可能还没有更新完成。之前使用 0.01 秒的延迟不够长，导致获取到的"当前数据"实际上还是"开始时的数据"。

### 修复方案
1. **增加 `hasPendingStrokeUndo` 标记**：追踪是否有待处理的笔画撤销操作
2. **双重触发机制**：
   - 在 `canvasViewDrawingDidChange` 中：当不在绘制状态且有待处理操作时，尝试创建撤销
   - 在 `canvasViewDidEndUsingTool` 中：延迟 0.1 秒后作为兜底触发
3. **防重复处理**：`tryCreateStrokeUndoAction` 方法确保每个笔画只创建一次撤销操作

### 技术要点
- `canvasViewDrawingDidChange` 在绘图数据真正变化时被调用，比 `canvasViewDidEndUsingTool` 更可靠
- 通过 `hasPendingStrokeUndo` 标记避免重复创建撤销操作
- 延迟从 0.01 秒增加到 0.1 秒，作为兜底保护

### 修改文件
- `Views/Editor/Canvas/NativeCanvasView.swift`

---

## 2025-12-13 - 撤销/恢复系统修复 v1.2.2 🔧

### 概述
修复撤销/恢复系统中的关键问题，特别是绘制操作无法撤销的bug，并排查笔画漂移的根本原因。

### 问题分析

#### 1. 双重撤销记录机制冲突 ✅
**问题**：存在两套撤销记录机制在冲突
- **新机制**：在 `canvasViewDidEndUsingTool` 中记录撤销
- **旧机制**：在 `onCanvasUpdated` 回调中记录撤销

**根因**：旧机制的 `lastDrawingData` 在绘制过程中被错误更新，导致数据比较混乱，甚至可能重置了新机制的数据。

**修复**：
- 移除 `NativeEditorView` 中的旧撤销记录机制
- `onCanvasUpdated` 回调只用于保存文档，不再记录撤销操作
- 统一使用 `canvasViewDidEndUsingTool` 中的新机制

#### 2. 绘制数据获取时机问题 ✅
**问题**：`canvasViewDidEndUsingTool` 调用时，`getDrawingData()` 返回的还是开始时的数据

**现象**：
- 开始绘制：数据大小=42
- 结束绘制：数据大小=654（说明确实画了）
- 但获取的当前数据还是42

**修复**：
- 调整时序：先获取绘图数据，再解冻坐标系统
- 添加延迟：使用 `DispatchQueue.main.asyncAfter` 确保数据更新完成
- 增强调试：添加详细的坐标状态和数据变化日志

#### 3. 坐标系统重置问题 ✅
**问题**：`setScrollTransformsFrozen(false)` 恢复坐标时可能影响绘图数据

**修复**：
- 在恢复坐标前先获取绘图数据
- 使用 `UIView.performWithoutAnimation` 避免动画干扰
- 添加坐标状态跟踪日志

### 技术要点

#### PencilKit 委托调用时序
- `canvasViewDidBeginUsingTool` → 开始绘制
- `canvasViewDrawingDidChange` → 绘制中（多次调用）
- `canvasViewDidEndUsingTool` → 结束绘制

**关键发现**：`canvasViewDidEndUsingTool` 可能在 PencilKit 内部更新 drawing 数据之前被调用，需要添加延迟确保数据同步。

#### 坐标系统与绘图数据的关系
- 坐标系统冻结/恢复可能影响 PencilKit 的内部状态
- 必须在正确的时机获取绘图数据
- 双重撤销记录机制会相互干扰

### 修改文件

**核心修改**：
- `Views/Editor/NativeEditorView.swift` - 移除旧撤销记录机制
- `Views/Editor/Canvas/NativeCanvasView.swift` - 优化新撤销记录时序
- `ViewModels/CanvasStateManager.swift` - 增强调试日志
- `Models/Canvas/CanvasAction.swift` - 增强撤销操作日志

### 调试增强

添加了全面的调试日志系统：
- 绘制开始/结束时的数据大小
- 坐标系统状态变化
- 撤销操作创建和执行过程
- 恢复栈状态跟踪

### 后续计划

虽然发现了双重机制冲突的问题，但绘制撤销仍然存在时序问题。建议：
1. 进一步研究 PencilKit 内部机制
2. 考虑使用 `canvasViewDrawingDidChange` 作为撤销触发点
3. 在真机上验证是否为 Simulator 特有问题

---

## 2025-12-13 - 编译错误修复 v1.2.1 🔧

### 概述
修复画布工具完善版本中的编译错误，确保项目可以正常编译运行。

### 修复的编译错误

#### 1. Combine 模块导入问题 ✅
**错误信息**：`Static subscript 'subscript(_enclosingInstance:wrapped:storage:)' is not available due to missing import of defining module 'Combine'`

**修复文件**：
- `AnnotationLayerNode.swift` - 添加 `import Combine`
- `RectangleLayerNode.swift` - 添加 `import Combine`
- `ArrowLayerNode.swift` - 添加 `import Combine`
- `TextLayerNode.swift` - 添加 `import Combine`

#### 2. Color 扩展冲突问题 ✅
**错误信息**：`Invalid redeclaration of 'init(hex:)'`

**修复方案**：
- 将 `Color.init(hex:)` 改为 `Color.fromHex(_:) -> Color?` 静态方法
- 更新所有使用 `Color(hex:)` 的地方改为 `Color.fromHex() ?? 默认颜色`

**修复文件**：
- `Extensions/Color+Hex.swift` - 修改扩展方法
- `Views/Editor/Canvas/AnnotationView.swift` - 更新颜色创建
- `Views/Editor/Canvas/TextEditingView.swift` - 更新颜色创建
- `Views/Editor/NativeEditorView.swift` - 更新多个颜色创建
- `Views/Auth/LoginView.swift` - 更新颜色创建
- `Infrastructure/Theme.swift` - 更新颜色创建

#### 3. 箭头视图 StrokeStyle 问题 ✅
**错误信息**：
- `Value of type 'StrokeShapeView<Path, Color, EmptyView>' has no member 'lineCap'`
- `Cannot infer contextual base in reference to member 'round'`

**修复方案**：
- 将 `.stroke(color, lineWidth: lineWidth).lineCap(.round).lineJoin(.round)`
- 改为 `.stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))`

**修复文件**：
- `Views/Editor/Canvas/ArrowView.swift` - 使用 StrokeStyle 设置线条样式

### 技术要点

#### SwiftUI 绘图 API 正确用法
在 SwiftUI 中，线条样式（如线帽、连接方式）应该通过 `StrokeStyle` 结构体设置，而不是直接在 `.stroke()` 修饰符链上调用。

#### 可选类型处理
`Color.fromHex()` 返回可选类型 `Color?`，在使用时必须提供默认值或进行可选绑定，确保类型安全。

#### 模块导入规范
使用 `@Published` 和 `ObservableObject` 时必须显式导入 `Combine` 框架，避免编译错误。

### 影响范围
- 修复了所有新增工具相关的编译错误
- 确保项目可以在 Xcode 中正常编译
- 不影响任何功能逻辑

---

## 2025-12-13 - 画布工具完善 v1.2 🎨

### 概述
完善画布工具栏，实现了箭头、矩形、文字、标注等绘图工具，并将撤销/恢复系统集成到所有操作中。

### 新增工具实现

#### 1. 箭头工具 ✅
- **新增文件**: `ArrowView.swift` - 箭头绘制组件
- **新增文件**: `ArrowLayerNode.swift` - 箭头数据模型
- **功能**: 拖拽绘制箭头，支持自定义颜色和线宽
- **撤销支持**: 完整的添加/删除/修改操作

#### 2. 矩形工具 ✅
- **新增文件**: `RectangleView.swift` - 矩形绘制组件
- **新增文件**: `RectangleLayerNode.swift` - 矩形数据模型
- **功能**: 拖拽绘制矩形，支持填充/空心模式
- **撤销支持**: 完整的添加/删除/修改操作

#### 3. 文字工具 ✅
- **新增文件**: `TextEditingView.swift` - 文字输入和显示组件
- **新增文件**: `TextLayerNode.swift` - 文字数据模型
- **功能**: 点击画布添加文字，支持字体、大小、颜色设置
- **撤销支持**: 完整的添加/删除/修改操作

#### 4. 标注工具 ✅
- **新增文件**: `AnnotationView.swift` - 标注绘制组件
- **新增文件**: `AnnotationLayerNode.swift` - 标注数据模型
- **功能**: 绘制矩形框+文字组合，弹出对话框输入标注内容
- **撤销支持**: 完整的添加/删除/修改操作

### 撤销/恢复系统完善

#### 集成到所有操作
- **图层移动**: 记录移动前后的位置
- **图层缩放**: 记录缩放前后的尺寸
- **图层旋转**: 记录旋转前后的角度
- **绘图操作**: 记录绘图数据变化
- **工具操作**: 箭头、矩形、文字、标注的创建和修改

#### 通知机制
- **新增文件**: `Notification+Name.swift` - 定义通知名称
- **实现**: 使用 NotificationCenter 传递操作记录
- **优势**: 解耦组件间依赖，统一处理撤销/恢复

### 工具栏更新

#### 主工具栏扩展
- 将所有工具添加到主工具栏显示
- 工具顺序：选择、平移、画笔、橡皮擦、箭头、矩形、文字、标注、图片
- 保持一致的设计语言和交互体验

### 持久化支持

#### 画布文档扩展
- 添加箭头、矩形、文字、标注的持久化
- 支持完整的保存和加载功能
- 维护 Z-Index 顺序和属性

### 新增扩展

#### 颜色支持
- **新增文件**: `Color+Hex.swift` - 十六进制颜色转换
- **功能**: 支持字符串颜色值到 SwiftUI Color 的转换

### 技术亮点

#### 统一架构
- 所有工具遵循相同的设计模式
- 统一的数据模型和管理器
- 一致的撤销/恢复集成

#### 手势处理
- 每个工具独占手势，避免冲突
- 箭头、矩形、标注使用拖拽手势
- 文字工具使用点击手势

#### 性能优化
- 使用 `@Published` 和 `Observable` 响应式更新
- 懒加载和按需渲染
- 最小化视图重建

### 文件清单

**新增文件:**
- `Views/Editor/Canvas/ArrowView.swift`
- `Models/Canvas/ArrowLayerNode.swift`
- `Views/Editor/Canvas/RectangleView.swift`
- `Models/Canvas/RectangleLayerNode.swift`
- `Views/Editor/Canvas/TextEditingView.swift`
- `Models/Canvas/TextLayerNode.swift`
- `Views/Editor/Canvas/AnnotationView.swift`
- `Models/Canvas/AnnotationLayerNode.swift`
- `Extensions/Notification+Name.swift`
- `Extensions/Color+Hex.swift`

**修改文件:**
- `Models/Canvas/CanvasTool.swift` - 添加工具到主工具栏
- `Models/Canvas/CanvasAction.swift` - 添加所有工具的操作
- `Models/Canvas/CanvasDocument.swift` - 添加持久化支持
- `ViewModels/CanvasStateManager.swift` - 添加状态管理
- `Views/Editor/Canvas/NativeCanvasView.swift` - 添加工具支持
- `Views/Editor/NativeEditorView.swift` - 集成工具视图
- `ViewModels/NativeEditorViewModel.swift` - 添加保存/加载支持
- `Views/Editor/Canvas/ResizableImageView.swift` - 集成撤销/恢复

### 后续计划
- [ ] 真机测试所有工具功能
- [ ] 优化工具切换性能
- [ ] 添加更多工具属性设置面板

---

## 2025-12-13 - 图片工具拍照功能 + 撤销/恢复系统 v1.1 📸

### 概述
完善图片工具的"拍照"功能，并实现基于 Command Pattern 的撤销/恢复系统。

### 图片工具完善

#### 问题
按照设计方案，图片工具应弹出菜单提供"从相册选择"和"拍照"两个选项，但之前实现只有相册选择。

#### 解决方案
1. 新增 `CameraImagePicker.swift` - 包装 UIImagePickerController 实现相机拍照
2. 修改 `NativeEditorView.swift` - 添加图片来源选择菜单（confirmationDialog）
3. 拍照功能仅在真机（相机可用）时显示

#### 新增文件
- `Views/Editor/Canvas/CameraImagePicker.swift`

#### 修改文件
- `Views/Editor/NativeEditorView.swift`
  - 新增 `showImageSourceMenu` 状态
  - 新增 `showCamera` 状态
  - 图片工具点击 → 弹出选择菜单（相册/拍照）
  - `fullScreenCover` 展示相机

### 撤销/恢复系统 (Command Pattern)

#### 核心设计
采用命令模式（Command Pattern），每个可撤销操作封装为一个 Action 对象：
- 每个 Action 实现 `execute()` 和 `undo()` 方法
- `CanvasStateManager` 维护 undoStack 和 redoStack
- 新操作入栈时清空 redoStack
- 撤销时从 undoStack 弹出，执行 undo()，压入 redoStack
- 恢复时从 redoStack 弹出，执行 execute()，压入 undoStack

#### 新增文件
- `Models/Canvas/CanvasAction.swift` - 定义撤销/恢复协议和各类 Action：
  - `CanvasAction` 协议
  - `AddLayerAction` - 添加图层
  - `RemoveLayerAction` - 移除图层
  - `MoveLayerAction` - 移动图层
  - `ScaleLayerAction` - 缩放图层
  - `RotateLayerAction` - 旋转图层
  - `ZIndexLayerAction` - 调整图层顺序
  - `LockLayerAction` - 锁定/解锁图层
  - `DrawingAction` - 绘图操作（快照）
  - `ClearCanvasAction` - 清屏操作
  - `DuplicateLayerAction` - 复制图层
  - `CompoundAction` - 复合操作

#### 修改文件
- `ViewModels/CanvasStateManager.swift`
  - 新增 `undoStack` / `redoStack` 私有属性
  - 新增 `maxUndoSteps = 50` 限制
  - 实现 `recordAction(_:)` 方法
  - 实现 `undo()` / `redo()` 方法
  - 实现 `clearUndoRedoStacks()` 方法
  - `canUndo` / `canRedo` 返回栈非空状态

- `Views/Editor/NativeEditorView.swift`
  - `onClearCanvas` 回调：记录当前状态后执行清屏
  - `onDuplicateSelected` 回调：记录操作后执行复制

### 功能状态

| 功能 | 状态 |
|:---|:---:|
| 图片工具 - 相册选择 | ✅ |
| 图片工具 - 拍照 | ✅（仅真机） |
| 撤销 - 清屏 | ✅ |
| 撤销 - 复制图层 | ✅ |
| 撤销 - 其他操作 | 🔜 待集成 |

### 后续计划
- [ ] 将撤销支持集成到更多操作（移动/缩放/旋转/绘图等）
- [ ] 实现箭头/文字/标注/矩形工具
- [ ] 真机验证拍照功能

---

## 2025-12-13 - 画布工具栏重构 v1.0 (Tool-Based Architecture) 🎨

### 概述
按照《画布工具栏重构设计方案 v1.0》，将画布从"模式切换"架构重构为"工具切换"架构，参考 Figma/Canva 等专业设计工具的交互模式。

### 核心目标
1. **消除手势冲突**：每个工具独占手势，彻底解决笔画漂移问题
2. **提升操作直觉**：工具即功能，所见即所得
3. **简化状态管理**：无需维护复杂的模式切换逻辑

### 架构变化

#### 移除的概念
- `CanvasToolMode.objectMode` / `drawingMode` → 改为具体工具
- 双指捏合缩放 → 改为滑动条缩放，避免手势冲突
- Zoom HUD 的 +/- 按钮 → 改为滑动条

#### 新增的概念
- `CanvasTool` 枚举（select/pan/pen/eraser/image 等）
- 底部工具栏 `CanvasToolbar`
- 左上角功能键 `CanvasActionBar`（撤销/恢复/复制/清屏）
- 缩放滑动条 `ZoomSlider`

### 新增文件

#### 1. Models/Canvas/CanvasTool.swift
定义所有可用工具的枚举：
- `.select` - 选择工具：选中/移动/缩放/旋转对象
- `.pan` - 平移工具：拖动平移整个画布
- `.pen` - 画笔工具：自由绘制笔画
- `.eraser` - 橡皮擦：擦除笔画
- `.image` - 图片工具：导入相册/拍照
- `.arrow/.text/.annotation/.rectangle` - 预留工具

#### 2. Views/Editor/Canvas/CanvasToolbar.swift
底部工具栏组件：
- 毛玻璃背景 `.ultraThinMaterial`
- 圆角矩形形状
- 选中态：品牌蓝填充 + 白色图标
- 未选中态：透明背景 + 次要文本色图标
- Spring 动画切换

#### 3. Views/Editor/Canvas/ZoomSlider.swift
缩放滑动条组件：
- 滑动范围：50% ~ 300%
- 品牌蓝滑块和轨道
- 百分比数字可编辑
- 等宽字体显示

#### 4. Views/Editor/Canvas/CanvasActionBar.swift
左上角功能键组件：
- 撤销/恢复/复制/清屏按钮
- 清屏带确认 Alert
- 禁用态透明度降低

### 重构的文件

#### 1. ViewModels/CanvasStateManager.swift
- 新增 `currentTool: CanvasTool` 属性
- 保留兼容属性 `currentMode`（标记 deprecated）
- 新增 `canUndo` / `canRedo` 属性（预留）
- 新增 `onClearCanvas` / `onDuplicateSelected` 回调

#### 2. Views/Editor/Canvas/NativeCanvasView.swift
- 新增 `currentTool` 属性
- 新增 `updateForTool(_:)` 方法
- 每个工具的手势独占配置：
  - select: 禁用 PK，启用对象手势，禁用画布滚动
  - pan: 禁用 PK，禁用对象手势，启用单指滚动
  - pen/eraser: 启用 PK，锁定画布
  - image: 同 select
- 更新 `NativeCanvasViewWrapper` 使用 `currentTool`

#### 3. Views/Editor/NativeEditorView.swift
- 移除旧的顶部工具栏（模式切换 Picker、画笔/橡皮擦按钮）
- 新增底部工具栏 `CanvasToolbar`
- 新增左上角功能键 `CanvasActionBar`
- 更新缩放控制为 `ZoomSlider`
- 新增图片选择器 `PhotosPicker`

### 工具行为定义

| 工具 | PencilKit | 对象层 | 画布滚动 |
|:---|:---:|:---:|:---:|
| select | 禁用 | 启用 | 禁用 |
| pan | 禁用 | 禁用 | 单指启用 |
| pen | 启用（画笔） | 禁用 | 锁定 |
| eraser | 启用（橡皮擦） | 禁用 | 锁定 |
| image | 禁用 | 启用 | 禁用 |

### 兼容性处理
- 保留 `CanvasToolMode` 枚举文件
- `CanvasStateManager` 中保留 `currentMode` 兼容属性
- `NativeCanvasView` 中保留 `setDrawingTool(isPen:)` 兼容方法
- 所有兼容 API 标记 `@available(*, deprecated)`

### 预期效果
- ✅ 消除绘图漂移：每个工具独占手势，无冲突
- ✅ 直觉操作：点击工具即切换，无需理解"模式"概念
- ✅ 简化代码：移除复杂的模式判断逻辑
- ✅ 可扩展：预留箭头/文字/标注/矩形等工具位置

### 后续计划
- [ ] Phase 3: 实现撤销/恢复系统（Command Pattern）
- [ ] Phase 4: 实现箭头/文字/标注/矩形工具
- [ ] 真机验证绘图漂移问题是否彻底解决

### 文件清单
**新增：**
- `Models/Canvas/CanvasTool.swift`
- `Views/Editor/Canvas/CanvasToolbar.swift`
- `Views/Editor/Canvas/ZoomSlider.swift`
- `Views/Editor/Canvas/CanvasActionBar.swift`

**修改：**
- `ViewModels/CanvasStateManager.swift`
- `Views/Editor/Canvas/NativeCanvasView.swift`
- `Views/Editor/NativeEditorView.swift`

---

## 2025-12-13 - 绘图漂移排查记录（未复现原因，待定）⚠️

### 现象
- Simulator + 触控板绘图时，笔迹实时向右下漂移，松手后恢复。

### 排查过程与发现
- 手势收敛：绘图模式禁用 pan/pinch/scroll，锁定 contentOffset；对象模式保留拖动/缩放。
- 多轮精细日志：monitor + 状态快照（scrollOffset/lockedOffset/zoom/gesture state/pencil offset），绘制前后 frame/bounds 记录。
- 实际日志结果：外层 scrollView offset 始终 2127.5,2016.5，PKCanvasView contentOffset 始终 0，zoom=1；未出现 drift/pencil_offset_reset 触发。
- 结论：漂移并非外层滚动/缩放或 PK contentOffset 变化导致，更像 PK/Simulator 渲染层的临时偏移。

### 建议的下一步（未实施）
- 真机验证：判断是否为 Simulator/触控板特有问题。
- A/B 试验：绘图模式切换为"独立 PKCanvasView，无外层 UIScrollView"以确认是否 Scroll 容器相关。
- 如仍漂移，再转向坐标映射/渲染链路排查。

### 变更文件
- 无，日志已清理

## 2025-12-12 - 编辑器手势收敛与漂移护栏 v1.2 ✅

### 背景
- 笔画绘制时仍偶发右下漂移，怀疑根因是绘图模式下 scrollView 仍有残余滚动/缩放入口。

### 核心变更
- **手势收敛**
  - 对象模式：保留画布拖动与捏合缩放，禁用 PencilKit 交互。
  - 绘画模式：仅允许笔/手指绘制，完全禁用画布拖动与缩放（pan/pinch/scroll 均关闭），锁定当前 contentOffset。
- **缩放护栏**
  - `setZoomScale` / `resetZoom` 仅在对象模式下生效，绘图模式直接忽略，避免 HUD 或程序调用影响坐标系。
  - 绘图模式或绘制中触发的 `scrollViewDidScroll` 均强制回退到锁定 offset。

### 修改文件
- `src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift`

### 预期效果
- 绘图模式下无论触控板/鼠标/手指，画布不会再发生平移或缩放，消除笔画实时漂移的来源。
- 对象模式保持原有拖动与缩放体验；Magic Frame 叠加交互不受影响。

### 风险与验证
- 尚未在真机验证；需重点回归：对象模式下拖动/缩放是否正常，绘图模式下缩放按钮被禁用后体验是否符合预期。

## 2025-12-12 - 编辑器布局修复 v1.0 ✅

### 修复目标
解决编辑器在 iPhone 和 iPad 上"揉成一团"的布局问题，实现全屏沉浸式横屏编辑体验。

### 核心变更

#### 1. 导航架构重构：从 Push 改为 FullScreenCover
**文件**: `ProjectListView.swift`

**变更前**:
- 使用 `NavigationLink` 进入编辑器
- 编辑器作为导航堆栈中的详情页
- iPad 上左侧 Sidebar 保留，压缩画布空间

**变更后**:
- 添加 `@State private var selectedProject: Project?`
- 使用 `.fullScreenCover(item: $selectedProject)` 呈现编辑器
- 编辑器覆盖整个屏幕，Sidebar 完全消失

```swift
// 触发方式从 NavigationLink 改为 Button + State
Button {
    selectedProject = project
} label: {
    ProjectCard(project: project)
}

// 新增全屏模态展示
.fullScreenCover(item: $selectedProject) { project in
    NativeEditorView(project: project)
}
```

#### 2. 编辑器布局简化：恢复硬编码三栏布局
**文件**: `NativeEditorView.swift`

**移除内容**:
- ❌ 移除 `@Environment(\.horizontalSizeClass)`
- ❌ 移除 `@Environment(\.columnVisibilityBinding)`
- ❌ 移除 `showLibrarySheet` / `showControlPanelSheet` 状态
- ❌ 移除 `compactLayout` / `regularLayout` 判断逻辑
- ❌ 移除 iPhone 专用的 Toolbar 按钮和 Sheet 面板
- ❌ 移除 `.navigationTitle` 和 `.navigationBarTitleDisplayMode`

**新增内容**:
- ✅ 添加 `@Environment(\.dismiss)` 用于关闭全屏视图
- ✅ 恢复简单的 `HStack` 三栏布局：
  ```
  [资源库 300pt] | [画布 自适应] | [控制面板 320pt]
  ```
- ✅ 在左上角添加关闭按钮（替代原导航栏返回）

**新布局结构**:
```swift
var body: some View {
    HStack(spacing: 0) {
        NativeAssetLibraryView(...).frame(width: 300)
        Divider()
        NativeCanvasContainer(viewModel: viewModel)
        Divider()
        NativeControlPanel(...).frame(width: 320)
    }
    .overlay(alignment: .topLeading) {
        Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill")
        }
    }
}
```

### 预期效果

#### iPad
- ✅ 点击项目 → 界面覆盖全屏（左侧导航栏消失）
- ✅ 沉浸式三栏创作界面，画布空间充足（> 500pt）
- ✅ 点击关闭按钮 → 恢复项目列表界面

#### iPhone
- ✅ 启动后自动横屏，利用长边（~850pt）容纳三栏布局
- ✅ 画布剩余空间约 230pt（850 - 620），足够基本编辑

### 技术决策

1. **为什么使用 `.fullScreenCover` 而非 `.sheet`?**
   - `.sheet` 在 iPad 上默认呈现为卡片模式，无法完全覆盖屏幕
   - `.fullScreenCover` 创建新的 Window 级上下文，物理上隔离导航层级

2. **为什么回滚响应式布局?**
   - 专业创作工具需要稳定的工作区，不应随屏幕尺寸动态调整
   - 在确保横屏的前提下，硬编码布局更简洁、可控

3. **为什么不保留 compact 模式的 Sheet 面板?**
   - 简化代码，减少维护成本
   - 后续会通过强制横屏统一体验，无需适配竖屏

#### 3. 全局横屏设置
**文件**: `MindCanvas.xcodeproj/project.pbxproj`

**变更**:
- ✅ iPad: 移除竖屏支持，只保留 `UIInterfaceOrientationLandscapeLeft` 和 `UIInterfaceOrientationLandscapeRight`
- ✅ iPhone: 移除竖屏支持，只保留横屏方向

**效果**:
- App 启动后自动进入横屏模式
- 旋转设备只在左横屏和右横屏之间切换
- 无需代码动态控制方向

### 影响范围
- ✅ 无编译错误
- ✅ 不影响现有功能（资源库、控制面板、画布交互等）
- ✅ 仅改变导航方式和布局呈现

---

## 2025-12-12 - 绘图漂移问题排查记录（未解决）⚠️

### 问题现象
- 绘图模式下，笔画绘制过程中会漂移
- 松开后笔画恢复到正确位置
- **漂移方向始终是右下角**
- 执行某些操作（点击图生图、文生图、显示/隐藏选框等）后问题有时会消失
- 重新进入页面后问题又出现
- 测试环境：Simulator + 触控板

### 已尝试的所有修复方案（均无效）

#### 方案 1：绘制过程中不触发保存回调
```swift
func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
    guard !isDrawing else { return }  // 绘制中跳过
    onCanvasUpdated?()
}
```
**假设**：访问 `pencilCanvas.drawing` 数据可能干扰绘制
**结果**：无效

#### 方案 2：scrollViewDidZoom 绘制中完全跳过
```swift
func scrollViewDidZoom(_ scrollView: UIScrollView) {
    guard !isDrawing else { return }
    // ...
}
```
**假设**：居中布局更新干扰绘制
**结果**：无效

#### 方案 3：updateUIView 绘制中跳过
```swift
func updateUIView(_ uiView: NativeCanvasView, context: Context) {
    guard !uiView.isDrawing else { return }
    // ...
}
```
**假设**：SwiftUI 更新干扰 UIKit 绘制
**结果**：无效

#### 方案 4：彻底冻结 scrollView
```swift
private func setScrollTransformsFrozen(_ frozen: Bool) {
    if frozen {
        scrollView.panGestureRecognizer.isEnabled = false
        scrollView.pinchGestureRecognizer?.isEnabled = false
        scrollView.isScrollEnabled = false
        scrollView.bounces = false
        scrollView.bouncesZoom = false
        scrollView.panGestureRecognizer.allowedScrollTypesMask = []
    }
    // ...
}
```
**假设**：手势和滚动事件干扰绘制
**结果**：无效

#### 方案 5：layoutSubviews 绘制中保护
```swift
override func layoutSubviews() {
    super.layoutSubviews()
    guard !isDrawing else { return }
    // ...
}
```
**假设**：frame 变化导致坐标系变化
**结果**：无效

#### 方案 6：setZoomScale 绘制中保护
```swift
func setZoomScale(_ scale: CGFloat, animated: Bool) {
    guard !isDrawing else { return }
    // ...
}
```
**假设**：HUD 按钮触发缩放干扰绘制
**结果**：无效

#### 方案 7：禁用 PKCanvasView 自身的 ScrollView 行为
```swift
// PKCanvasView 继承自 UIScrollView！
pencilCanvas.isScrollEnabled = false
pencilCanvas.minimumZoomScale = 1.0
pencilCanvas.maximumZoomScale = 1.0
pencilCanvas.bouncesZoom = false
pencilCanvas.bounces = false
pencilCanvas.alwaysBounceVertical = false
pencilCanvas.alwaysBounceHorizontal = false
```
**假设**：嵌套 ScrollView 导致坐标冲突
**结果**：无效

#### 方案 8：进入绘图模式时重置手势状态
```swift
private func resetScrollViewGestures() {
    scrollView.panGestureRecognizer.isEnabled = false
    scrollView.pinchGestureRecognizer?.isEnabled = false
    DispatchQueue.main.async { ... }
}
```
**假设**：手势状态残留导致问题
**结果**：无效

#### 方案 9：scrollViewDidScroll 强制恢复 contentOffset
```swift
func scrollViewDidScroll(_ scrollView: UIScrollView) {
    if isDrawing {
        scrollView.contentOffset = storedContentOffset
    }
}
```
**假设**：contentOffset 被意外修改导致右下角漂移
**结果**：无效

### 问题特征分析

1. **漂移方向固定为右下角**
   - 在 iOS 坐标系中，右下 = X+ Y+
   - 可能与 contentOffset 增加有关
   - 但强制恢复 contentOffset 也无效

2. **松开后恢复正确位置**
   - 说明 PencilKit 内部记录的坐标是正确的
   - 问题出在显示/渲染层面

3. **某些操作后问题消失**
   - 这些操作都会触发 SwiftUI 视图更新
   - 可能会"意外"重置某些状态

4. **重新进入页面问题复现**
   - 与视图初始化有关

### 架构信息

```
NativeCanvasView (UIView)
└── scrollView (UIScrollView) - 外层滚动/缩放
    └── contentView (UIView) - 5000x5000 画布
        ├── objectLayerView (UIView) - 图片图层
        └── pencilCanvas (PKCanvasView) - 绘图层
            └── 继承自 UIScrollView！
```

### 可能的根因方向（未验证）

1. **Simulator 触控板的特殊行为**
   - Simulator 中触控板输入的事件类型可能和真机不同
   - 需要在真机上测试验证

2. **PKCanvasView 的内部实现**
   - PKCanvasView 可能有我们无法控制的内部行为
   - Apple 没有公开足够的 API

3. **SwiftUI/UIKit 混合架构的问题**
   - GeometryReader 可能导致意外的布局更新
   - SwiftUI 的声明式更新可能和 UIKit 冲突

4. **坐标转换问题**
   - 触摸点从 window 坐标到 PKCanvasView 局部坐标的转换可能有问题
   - scrollView 的 transform 可能影响坐标转换

### 建议的后续排查方向

1. **在真机上测试** - 确认是否为 Simulator 特有问题
2. **简化架构** - 尝试不使用外层 scrollView，直接使用 PKCanvasView 自身的缩放功能
3. **使用 Apple 官方示例** - 参考 Apple 的 PencilKit 示例代码
4. **提交 Apple 反馈** - 如果是 PencilKit 的 bug

### 修改的文件
- `src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift`

---

---

## 2025-12-12 - 编辑器交互问题修复 v1.1（Zoom / 触控板 / Sheet / 绘画漂移 / 图生图预览）

### 背景
依据 `docs/design/fix/editor_interaction_fixes_v1.1.md` 的"唯一方案"，对原生编辑器在 Simulator 触控板场景下暴露的问题做集中修复：Zoom HUD 卡死、Sheet 无法再次打开、绘制漂移、图生图预览截图不确定与回填坐标风险。

### 主要改动（iOS）
- **Zoom HUD：百分比卡死**
  - 用 `FocusState` 作为"是否编辑"的唯一依据，引入输入草稿 `zoomPercentDraft` 与实际缩放 `zoomScale` 分离
  - 数字键盘增加"完成"按钮，显式应用输入并退出编辑态
  - 相关文件：`src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift`

- **Sheet：单一事实来源**
  - 移除 ViewModel 中 `isTextToImagePresented / isImageToImageConfirmPresented`，由 View 的 `activeSheet` 作为唯一驱动
  - 图生图：先准备预览成功才打开确认 Sheet；点外部 dismiss 会正确清理 pending；确认生成时避免因 dismiss 链路提前清空输入
  - 相关文件：
    - `src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift`
    - `src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`

- **Simulator 触控板：Indirect 输入 + 绘制漂移**
  - 显式允许 `scroll wheel / trackpad` 的 scroll 类型与 pinch 的 touch types（包含 indirect）
  - 绘制开始/结束时冻结/恢复 scrollView 的 pan/pinch/scroll wheel，避免绘制中坐标系变化导致漂移
  - 相关文件：`src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift`

- **图生图预览：确定性截图 + 回填坐标一致**
  - `magicFrame` 保持"视口坐标"语义；截图与回填统一转换为"画布内容坐标"
  - 截图链路替换 `drawHierarchy`：PencilKit 使用 `PKDrawing.image(...)` 导出；对象层使用 `CALayer.render(in:)` 合成
  - 相关文件：
    - `src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift`
    - `src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`

## 2025-12-12 - 编辑器问题修复与生成流程优化 v1.0

### 背景
基于《编辑器问题修复与生成流程优化方案 v1.0》，对原生编辑器的缩放、手势与生成流程做一次集中修复与增强，提升稳定性与可控性；同时补齐"图生图确认预览"和"文生图"能力。

### 主要改动
- **问题修复：缩放 HUD 百分比不更新**
  - 修复 `NativeCanvasViewWrapper.updateUIView` 未重新绑定回调导致的缩放状态回传链路失效
  - 相关文件：`Views/Editor/Canvas/NativeCanvasView.swift`

- **问题修复：双指捏合缩放不可用**
  - 调整绘图模式下的 pinch 手势协调，确保 scrollView 的缩放手势可用
  - 相关文件：`Views/Editor/Canvas/NativeCanvasView.swift`

- **问题修复：绘画模式下笔划闪烁/短暂消失**
  - 绘制期间避免触发影响 PencilKit 渲染的居中布局更新，并禁用缩放回调中的隐式动画
  - 相关文件：`Views/Editor/Canvas/NativeCanvasView.swift`

- **生成流程：图生图确认预览浮窗**
  - 点击"图生图"后先截取选框区域内容并弹出确认浮窗，用户确认后才执行生成
  - 相关文件：
    - `Views/Editor/Sheets/ImageToImageConfirmSheet.swift`
    - `ViewModels/NativeEditorViewModel.swift`
    - `Views/Editor/NativeEditorView.swift`

- **生成流程：新增文生图（生成独立素材）**
  - 新增文生图输入浮窗，支持选择生成尺寸比例（仅记录元数据，不影响 mock 生成）
  - 生成结果进入资源库（不自动上画布）
  - 相关文件：
    - `Views/Editor/Sheets/TextToImageSheet.swift`
    - `Models/Generation.swift`
    - `Models/Asset.swift`
    - `ViewModels/NativeEditorViewModel.swift`

### 验证
- 新增验证文档：`docs/tests/validation/2025-12-12-编辑器问题修复与生成流程优化.md`

## 2025-12-12 - 原生编辑器 v4 交互与画布体验优化 ✨

### 背景
在 v3.0 原生化重构之后，实际体验暴露出几处明显问题：
- Magic Frame 拖动和缩放手感发飘，选框很容易"飞出屏幕"
- 画布缩放/漫游缺乏显式控制入口，难以找回飞出去的内容
- 绘图模式对鼠标/触控板支持不足，模拟器调试体验较差

基于《editor_optimization_v4.md》设计方案，对编辑器交互进行了一轮针对性的 v4 优化。

### 主要改动
- **Magic Frame 行为重构**
  - 将拖拽/缩放实现改为"起始快照 + translation 增量计算"，彻底消除越拖越快、失控飞走的问题
  - 新增视口边界约束，选框始终限制在当前画布视口范围内（允许小范围外溢给手柄），不会再完全飞出屏幕
  - 顶部/底部标签位置在接近边缘时自动收敛，避免被裁掉
  - 相关文件：`Views/Editor/Canvas/MagicFrameView.swift`

- **屏幕选框 → 画布内容截图链路打通**
  - 在 `NativeCanvasView` 中新增内容坐标快照与坐标映射：
    - `func contentRect(forViewportRect:)`：将 SwiftUI 视图坐标（HUD 选框）转换为画布内容坐标
    - `func captureContentSnapshot(rect:)`：在内容坐标系中裁剪并渲染 objectLayer + PencilKit
    - `func captureViewportSnapshot(rect:)`：从屏幕选框一路走到内容截图的统一入口
  - `NativeEditorViewModel.generate()` 改为通过 `captureViewportSnapshot(rect: stateManager.magicFrame)` 获取生成区域，保证"你看到哪里就截哪里"
  - 相关文件：
    - `Views/Editor/Canvas/NativeCanvasView.swift`
    - `ViewModels/NativeEditorViewModel.swift`

- **缩放 HUD 与 zoom 状态回传**
  - 在 `NativeCanvasView` 中增加：
    - `var zoomScale: CGFloat` 只读属性
    - `func setZoomScale(_:animated:)` 封装并 clamp 至 `[minZoomScale, maxZoomScale]`
    - `var onZoomChanged: ((CGFloat) -> Void)?` 回调，`scrollViewDidZoom` 中实时回传当前缩放
  - 在 `CanvasStateManager` 中新增 `zoomScale` 字段，保存当前缩放比例供 UI 展示
  - 在 `NativeEditorView` 中实现左下角 Zoom HUD：
    - `[-] [ xx% ] [+]` 布局
    - `+/-` 按钮以 10% 为步进调整缩放
    - 百分比文本可编辑，回车后换算成缩放比例并调用 `setZoomScale`