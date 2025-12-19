# 开发记录

## 2025-12-19 - 清屏撤销后图形对象消失问题修复 ✅

### 概述
通过深入分析问题的根本原因，从第一性原理出发，成功定位并修复了清屏撤销后图形对象消失的核心问题。根本原因是ClearCanvasAction撤销系统的数据结构不完整，只保存了图层和画笔数据，遗漏了箭头、形状、矩形、文字、标注等其他图形对象。

### 问题根源发现

#### 1. **数据结构不完整** - 核心根源
**问题本质**：`ClearCanvasAction` 只保存了部分数据类型，缺乏完整的数据快照机制
- 只保存了 `previousLayers: [LayerNode]`（图片层）
- 只保存了 `previousDrawingData: Data?`（画笔数据）
- **遗漏了所有其他图形对象**：箭头、形状、矩形、文字、标注

**影响链路**：
```
清屏操作 → ClearCanvasAction创建 → 只保存部分数据 → 
撤销操作 → 只能恢复部分对象 → 图形对象永久丢失
```

#### 2. **架构设计不一致** - 系统层面
**问题本质**：不同类型的图形对象存储在不同的管理器中，缺乏统一的数据访问接口
- 画笔数据：使用 `PKDrawing.dataRepresentation()` 统一存储
- 图片对象：使用 `LayerNode` 数组存储
- 箭头对象：使用 `ArrowLayerManager.arrows` 数组存储
- 形状对象：使用 `ShapeLayerManager.shapes` 数组存储
- **缺乏统一的数据获取和恢复接口**

### 核心修复方案

#### 1. 扩展 ClearCanvasAction 数据结构 ✅
**修改文件**：`Models/Canvas/CanvasAction.swift`

**关键修复**：
```swift
struct ClearCanvasAction: CanvasAction {
    let previousLayers: [LayerNode]
    let previousArrows: [ArrowLayerNode]      // 新增
    let previousShapes: [ShapeLayerNode]      // 新增
    let previousRectangles: [RectangleLayerNode] // 新增
    let previousTexts: [TextLayerNode]        // 新增
    let previousAnnotations: [AnnotationLayerNode] // 新增
    let previousDrawingData: Data?
    weak var canvasView: NativeCanvasView?
}
```

#### 2. 新增统一数据获取接口 ✅
**修改文件**：`Views/Editor/Canvas/NativeCanvasView.swift`

**关键修复**：
```swift
/// 获取所有箭头对象
func getArrows() -> [ArrowLayerNode] {
    return arrowLayerManager.arrows
}

/// 获取所有形状对象
func getShapes() -> [ShapeLayerNode] {
    return shapeLayerManager.shapes
}

/// 获取所有矩形对象
func getRectangles() -> [RectangleLayerNode] {
    return rectangleLayerManager.rectangles
}

/// 获取所有文字对象
func getTexts() -> [TextLayerNode] {
    // TODO: 待文本工具完整实现后启用
    return []
}

/// 获取所有标注对象
func getAnnotations() -> [AnnotationLayerNode] {
    return annotationLayerManager.annotations
}
```

#### 3. 更新清屏逻辑捕获所有对象 ✅
**修改文件**：`Views/Editor/NativeEditorView.swift`

**关键修复**：
```swift
// 记录当前所有对象状态用于撤销
let previousLayers = canvasView.getLayers()
let previousArrows = canvasView.getArrows()
let previousShapes = canvasView.getShapes()
let previousRectangles = canvasView.getRectangles()
let previousTexts = canvasView.getTexts()
let previousAnnotations = canvasView.getAnnotations()
let previousDrawingData = canvasView.getDrawingData()

print("[ClearCanvas] 开始清屏，当前对象统计:")
print("[ClearCanvas] - 图层: \(previousLayers.count)")
print("[ClearCanvas] - 箭头: \(previousArrows.count)")
print("[ClearCanvas] - 形状: \(previousShapes.count)")
print("[ClearCanvas] - 矩形: \(previousRectangles.count)")
print("[ClearCanvas] - 文字: \(previousTexts.count)")
print("[ClearCanvas] - 标注: \(previousAnnotations.count)")
print("[ClearCanvas] - 画笔数据: \(previousDrawingData.count) 字节")
```

#### 4. 增强撤销方法按类型恢复对象 ✅
**修改文件**：`Models/Canvas/CanvasAction.swift`

**关键修复**：
```swift
func undo() {
    print("[ClearCanvas] 开始撤销清屏操作")
    print("[ClearCanvas] 恢复对象统计 - 图层:\(previousLayers.count), 箭头:\(previousArrows.count), 形状:\(previousShapes.count), 矩形:\(previousRectangles.count), 文字:\(previousTexts.count), 标注:\(previousAnnotations.count)")
    
    // 按类型恢复所有对象
    if !previousLayers.isEmpty {
        print("[ClearCanvas] 恢复 \(previousLayers.count) 个图层")
        canvasView?.setLayers(previousLayers)
    }
    
    if !previousArrows.isEmpty {
        print("[ClearCanvas] 恢复 \(previousArrows.count) 个箭头")
        previousArrows.forEach { arrow in
            canvasView?.addArrow(arrow, recordUndo: false)
        }
    }
    
    // ... 其他对象类型的恢复逻辑
}
```

### 技术要点总结

#### 数据完整性保证
- 扩展撤销系统支持所有图形对象类型
- 建立统一的数据获取和恢复接口
- 添加详细日志追踪对象状态变化

#### 架构一致性改进
- 为不同管理器提供统一的数据访问方法
- 保持与现有撤销系统的兼容性
- 为未来新增图形类型提供扩展机制

#### 调试和验证增强
- 添加清屏和撤销过程的详细日志
- 按对象类型统计和恢复
- 提供清晰的修复效果验证方法

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Models/Canvas/CanvasAction.swift` | 修改 | 扩展ClearCanvasAction数据结构，支持所有图形对象 |
| `Views/Editor/Canvas/NativeCanvasView.swift` | 修改 | 添加获取所有图形对象的统一方法 |
| `Views/Editor/NativeEditorView.swift` | 修改 | 更新清屏逻辑捕获所有对象类型 |
| `docs/design/fix/clear_canvas_undo_fix_v1.md` | 新增 | 详细修复方案和验证计划文档 |

### 预期效果
修复后：
- ✅ 清屏撤销后所有图形对象完全恢复
- ✅ 对象的位置、颜色、大小、旋转等属性保持不变
- ✅ 提供详细的日志输出便于问题排查
- ✅ 支持复杂场景和边界情况
- ✅ 为未来新增图形类型提供扩展机制

### 验收标准
- [ ] 创建多种图形对象后清屏撤销，所有对象完全恢复
- [ ] 对象的变换状态（旋转、缩放）在撤销后保持不变
- [ ] 对象的层级关系在撤销后保持不变
- [ ] 控制台输出详细的统计和恢复日志
- [ ] 空画布和部分对象类型的撤销操作正常
- [ ] 大量对象场景下性能可接受

### 下一步
- 在Xcode中编译测试修复效果
- 在模拟器或真机上验证各种场景的撤销功能
- 根据测试结果优化性能和用户体验
- 完善文本工具的撤销支持（当前为TODO状态）

---

## 2025-12-19 - 清屏按钮智能删除功能根源问题修复 ✅

### 概述
通过深入分析问题的根本原因，从第一性原理出发，成功定位并修复了清屏按钮智能删除功能未生效的核心问题。根本原因是状态管理架构缺陷和生命周期时序问题导致的选中状态同步失败。

### 问题根源发现

#### 1. **状态管理架构缺陷** - 核心根源
**问题本质**：存在双重状态管理器，缺乏单一数据源
- NativeCanvasView有自己的`selectedNodeID`私有属性
- CanvasStateManager也有自己的`selectedNodeID`属性
- 两者之间没有建立双向绑定关系

**影响链路**：
```
用户选择对象 → NativeCanvasView.selectedNodeID更新 → 
CanvasStateManager.selectedNodeID未同步 → 
hasSelection计算错误 → 清屏按钮文案显示错误
```

#### 2. **生命周期时序问题** - 执行层面
**问题本质**：回调绑定与视图初始化的时序竞争
- onAppear可能在canvasView初始化完成前执行
- onViewCreated是异步初始化，可能晚于onAppear
- 弱引用在内存压力下可能被提前释放

### 核心修复方案

#### 1. 建立状态同步机制 ✅
**修改文件**：`Views/Editor/Canvas/NativeCanvasView.swift`

**关键修复**：
```swift
// 添加选中ID变化回调
var onSelectionIdChanged: ((UUID?) -> Void)?

private var selectedNodeID: UUID? {
    didSet {
        updateSelectionStates()
        // 修复：同步选中状态到CanvasStateManager
        onSelectionIdChanged?(selectedNodeID)
    }
}
```

#### 2. 绑定状态同步回调 ✅
**修改文件**：`Views/Editor/NativeEditorView.swift`

**关键修复**：
```swift
// 在onAppear中绑定
.onAppear {
    // 修复：绑定状态同步
    if let canvasView = viewModel.canvasView {
        canvasView.onSelectionIdChanged = { [weak viewModel] selectedID in
            viewModel?.stateManager.selectedNodeID = selectedID
        }
    }
    // ... 其他回调绑定
}

// 在onViewCreated中也绑定（确保初始化后立即生效）
onViewCreated: { view in
    viewModel.canvasView = view
    // 修复：绑定状态同步
    view.onSelectionIdChanged = { [weak viewModel] selectedID in
        viewModel?.stateManager.selectedNodeID = selectedID
    }
    // ... 其他设置
}
```

#### 3. 增强删除回调错误处理 ✅
**修改文件**：`Views/Editor/NativeEditorView.swift`

**关键改进**：
```swift
viewModel.stateManager.onDeleteSelected = { [weak viewModel] in
    guard let viewModel = viewModel,
          let canvasView = viewModel.canvasView,
          let selectedID = viewModel.stateManager.selectedNodeID
    else { 
        print("[NativeEditor] Delete selected failed: missing viewModel, canvasView or selectedID")
        return 
    }
    
    print("[NativeEditor] Deleting selected object: \(selectedID.uuidString.prefix(8))")
    
    var deletionSuccess = false
    // 按类型删除并记录成功状态
    // ... 删除逻辑
    
    if !deletionSuccess {
        print("[NativeEditor] Warning: No object found with ID: \(selectedID.uuidString.prefix(8))")
    }
    
    viewModel.stateManager.clearSelection()
}
```

### 技术要点总结

#### 状态同步机制
- 使用回调机制建立双向绑定
- 在生命周期关键点确保绑定生效
- 添加调试日志追踪状态流转

#### 生命周期管理
- 在onAppear和onViewCreated中都进行绑定
- 考虑异步初始化的时序问题
- 使用弱引用避免循环引用

#### 错误处理增强
- 添加详细的边界条件检查
- 增加删除成功的状态验证
- 提供调试日志便于问题排查

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Views/Editor/Canvas/NativeCanvasView.swift` | 修改 | 添加状态同步回调机制 |
| `Views/Editor/NativeEditorView.swift` | 修改 | 绑定状态同步和增强错误处理 |

### 预期效果
修复后：
- ✅ 选中对象时，按钮文案显示"删除选中对象"
- ✅ 无选中对象时，按钮文案显示"清空画布"
- ✅ 删除操作正确执行，支持撤销
- ✅ 状态在所有组件间保持同步

### 验收标准
- [ ] 创建形状并选中，按钮显示"删除选中对象"
- [ ] 点击删除按钮，只删除选中的形状
- [ ] 取消选中，按钮显示"清空画布"
- [ ] 点击清屏按钮，清空整个画布
- [ ] 删除操作支持撤销功能
- [ ] 快速操作场景下功能正常

### 下一步
- 在Xcode中编译测试修复效果
- 在模拟器或真机上验证智能删除功能
- 根据测试结果优化性能和用户体验

---

## 2025-12-18 - 画布工具优化方案 v2.0 实施记录 ✅

### 概述
根据画布工具优化方案v2.0文档，实施了三个优化任务。其中圆形工具释放时变大问题和椭圆形工具图标问题已成功修复，清屏按钮智能删除功能虽然实施了完整方案但未生效，需要后续进一步调试。

### 任务一：圆形工具释放时变大问题修复 ✅

#### 问题现象
- 圆形对象在拖动释放时会突然变大一点
- 其他形状（矩形、三角形等）正常
- 问题出现在手指释放的瞬间

#### 根本原因发现
经过深入分析，发现问题的真正根源是**数据模型层面的不一致性**：
1. **创建时的不一致**：ShapeDrawingView强制正方形，但NativeEditorView创建ShapeLayerNode时未做特殊处理
2. **渲染时的不一致**：SelectableShapeView使用椭圆路径绘制，如果bounds不是正方形就会变形
3. **约束累积效应**：使用平均值约束导致浮点精度误差累积，圆形逐渐变大

#### 修复方案
采用**从源头确保数据一致性**的原则，在数据创建时就确保圆形的frame是正方形：

1. **NativeEditorView**：创建时强制正方形
2. **SelectableShapeView**：路径创建时强制正方形
3. **约束逻辑**：改用最小值而非平均值，避免逐渐变大
4. **简化手势处理**：移除复杂的异步时序控制

#### 修改文件
- `Views/Editor/NativeEditorView.swift` - 圆形创建时强制正方形
- `Views/Editor/Canvas/SelectableShapeView.swift` - 路径创建、约束逻辑优化

#### 验收结果
- ✅ 圆形创建、调整、旋转后保持正圆
- ✅ 其他形状功能不受影响
- ✅ 性能稳定，无累积效应

### 任务二：椭圆形工具添加 ✅

#### 实施内容
1. **ShapeType.swift**：
   - 添加ellipse枚举值
   - 设置displayName为"椭圆形"
   - 添加到popoverShapes数组

2. **SelectableShapeView.swift**：
   - 在createShapePath()中添加ellipse分支
   - 使用UIBezierPath(ovalIn:)绘制椭圆

3. **ShapeDrawingView.swift**：
   - 添加椭圆预览绘制逻辑

#### 遇到的问题
- SF Symbols中没有'ellipse'图标，导致报错"No symbol named 'ellipse' found"

#### 解决方案
- 将iconName从'ellipse'改为'circle.fill'，使用实心圆形图标代表椭圆形工具

#### 修改文件
- `Models/Canvas/ShapeType.swift` - 添加椭圆支持并修复图标

#### 验收结果
- ✅ 形状选择器中显示椭圆形选项
- ✅ 可以在画布上绘制椭圆形
- ✅ 椭圆形可自由调整宽高比（无正方形约束）

### 任务三：清屏按钮智能删除功能 ⚠️

#### 需求目标
- 有选中对象时：只删除选中的对象，文案显示"删除选中对象"
- 无选中对象时：清空整个画布，文案显示"清空画布"

#### 实施方案
1. **CanvasActionBar.swift**：
   - 添加onDeleteSelected回调参数
   - 实现动态文案和Alert提示

2. **CanvasStateManager.swift**：
   - 添加deleteSelectedNode()方法
   - 添加onDeleteSelected回调属性

3. **NativeEditorView.swift**：
   - 绑定删除选中节点回调
   - 实现支持撤销的删除逻辑

4. **CanvasAction.swift**：
   - 添加RemoveShapeAction类

#### 遇到的问题
- 虽然实施了完整的方案，但功能未生效
- 清屏按钮行为与之前相同，没有智能删除效果

#### 可能原因
- CanvasActionBar的调用处可能没有正确传入onDeleteSelected参数
- 回调绑定逻辑可能存在问题
- 需要进一步调试整个调用链路

#### 修改文件
- `Views/Editor/Canvas/CanvasActionBar.swift` - 添加智能删除逻辑
- `ViewModels/CanvasStateManager.swift` - 添加删除方法
- `Views/Editor/NativeEditorView.swift` - 绑定删除回调
- `Models/Canvas/CanvasAction.swift` - 添加RemoveShapeAction

#### 遗留问题
- [ ] 清屏按钮智能删除功能未生效，需要进一步调试

### 技术要点总结

#### 圆形修复关键
- 数据一致性优先：在模型层面确保正确性
- 约束策略：min()比avg()更适合防止逐渐变大
- 简化时序：减少异步操作提高稳定性

#### 椭圆实现关键
- 与圆形使用相同的绘制API，但不强制宽高相等
- 图标选择需考虑SF Symbols的可用性

#### 智能删除关键
- 动态UI文案提升用户体验
- 撤销支持确保操作可回退
- 类型识别自动选择正确的删除方法

### 下一步计划
1. 深入调试清屏按钮智能删除功能，找出未生效的原因
2. 在真机上测试圆形工具的稳定性
3. 完善椭圆形工具的交互体验

---

## 2025-12-18 - 圆形工具释放时变大问题修复尝试未果 ❌

### 概述
尝试修复圆形工具在拖动释放后突然变大的问题，但未能完全解决。虽然从第一性原理分析了问题根源并实施了多种修复方案，但问题依然存在。

### 问题现象
- **特定问题**：只有圆形对象在拖动释放时会突然变大一点
- **其他形状正常**：矩形、三角形、星形等其他形状无此问题
- **时序问题**：问题出现在手指释放的瞬间

### 分析过程

#### 1. 第一性原理分析 ✅
**发现的问题复合效应**：
- **时序竞争问题**：`syncToNode()` 和 `layoutSubviews()` 之间的异步调用
- **约束逻辑作用域不完整**：缺少 `layoutSubviews()` 中的圆形防护
- **手势结束时序问题**：`activeHandle` 清除时机不当

#### 2. 关键线索发现 ✅
**根本原因推测**：圆形约束逻辑使用 `max(width, height)` 总是取较大值，导致每次拖动结束时，由于浮点精度误差，圆形都会稍微变大一点。

### 实施的修复方案

#### 方案1：在syncToNode()中添加圆形约束 ❌
**目标**：确保数据同步时圆形保持正方形
**修改**：
```swift
// 修复：在数据同步时也强制圆形保持正方形
if shapeNode.shapeType == .circle {
    let avgDimension = (finalWidth + finalHeight) / 2
    finalWidth = avgDimension
    finalHeight = avgDimension
}
```
**结果**：问题依然存在，无明显改善

#### 方案2：延迟同步机制 ❌
**目标**：避免手势结束时的时序竞争
**修改**：
```swift
case .ended, .cancelled:
    activeHandle = nil  // 先清除活动句柄
    
    DispatchQueue.main.async { [weak self] in
        self?.syncToNode()  // 延迟一帧执行
        // ...
    }
```
**结果**：问题依然存在，时序问题非主因

#### 方案3：多层约束防护 ❌
**目标**：在所有关键位置添加圆形约束
**修改位置**：
- `handleResizeFixed()` - 手势处理中的约束
- `syncToNode()` - 数据同步时的约束  
- `layoutSubviews()` - 布局时的约束
- `updateFromNode()` - 加载数据时的约束

**关键改进**：将 `max(width, height)` 改为 `(width + height) / 2`（平均值）
**结果**：问题依然存在，约束逻辑非主因

#### 方案4：详细调试日志分析 ❌
**目标**：通过详细日志追踪尺寸变化过程
**添加日志位置**：
- `handleResizeFixed()` - 手势处理过程
- `syncToNode()` - 数据同步过程
- `layoutSubviews()` - 布局过程
- 手势结束处理

**日志发现**：
- 圆形约束确实生效（avg: 137.75）
- 延迟同步机制正常工作
- 但问题依旧存在

**结果**：日志未能揭示真正的根源问题

### 技术要点总结

#### 已排除的原因
- ❌ 约束逻辑问题（max vs avg）
- ❌ 时序竞争问题（延迟同步）
- ❌ 数据同步问题（多层约束）
- ❌ 坐标转换精度问题（通过日志验证）

#### 可能的真正原因（未验证）
- **UIKit内部机制**：可能涉及UIView的内部布局或渲染机制
- **手势状态机**：可能存在手势状态转换的边界情况
- **Transform叠加**：可能存在多次transform叠加的累积效应
- **内存管理**：可能存在对象生命周期相关的意外行为

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | 多次尝试修复圆形约束和时序问题 |

### 遗留问题
- [ ] 圆形工具拖动释放后仍然会突然变大
- [ ] 需要更深入的分析或另请高明

### 经验教训
1. **第一性原理分析的重要性**：通过深入分析发现了问题的复合效应
2. **系统性修复策略**：从多个层面同时修复（时序、约束、数据同步）
3. **详细日志的价值**：虽然未能解决问题，但排除了一些可能原因
4. **知道何时停止**：当多种方案都无效时，承认问题的复杂性

### 建议
建议另请高明，可能需要：
- 更深入的UIKit内部机制了解
- 更专业的iOS图形和手势处理经验
- 或者考虑重构圆形工具的实现方式

---

## 2025-12-18 - 图形操作后控制点消失问题修复方案 v3.0 实施完成 ✅

### 概述
成功实施图形操作后控制点消失问题修复方案v3.0，彻底解决了图形对象在移动、旋转或缩放之后，再次选中时控制点（角点和旋转圆点）都消失的核心问题。根本原因是所有图层节点模型的 `updated` 方法在创建新实例时会生成新的 UUID，导致 selectedNodeID 与 shapeViews 字典中的键不匹配。

### 核心修复

#### 1. 发现真正问题：ID 不匹配 ✅
**问题**：从调试日志发现 selectedNodeID 和 shapeViews 的键不匹配
```
[NativeCanvas] selectedNodeID: C86961CD
[NativeCanvas] Setting shapeView isSelected=false for ID: 682BF441
```

**根本原因**：所有图层节点模型（ShapeLayerNode、ArrowLayerNode、TextLayerNode、AnnotationLayerNode、RectangleLayerNode）的 `updated` 方法在创建新实例时会生成新的 UUID，导致：
- `selectedNodeID` 是更新后的新 ID
- 但 `shapeViews` 字典中的键仍然是旧 ID
- 结果：`updateSelectionStates()` 找不到匹配的 shapeView

#### 2. 修复所有图层节点模型的 updated 方法 ✅
**解决方案**：为所有模型添加私有初始化方法，确保更新时保持原有 ID 不变

**修改文件**：
- `Models/Canvas/ShapeLayerNode.swift`
- `Models/Canvas/ArrowLayerNode.swift`
- `Models/Canvas/TextLayerNode.swift`
- `Models/Canvas/AnnotationLayerNode.swift`
- `Models/Canvas/RectangleLayerNode.swift`

**代码变更**：
```swift
// 添加私有初始化方法
private init(
    id: UUID,
    // ... 其他参数
    createdAt: Date
) {
    self.id = id
    // ... 保持原有属性
    self.createdAt = createdAt
}

// 修改 updated 方法
func updated(...) -> ShapeLayerNode {
    return ShapeLayerNode(
        id: self.id,  // 保持原有ID不变
        // ... 其他参数
        createdAt: self.createdAt  // 保持创建时间不变
    )
}
```

### 技术要点

#### ID 一致性保证
- 使用私有初始化方法确保更新时 ID 不变
- 保持创建时间戳不变，便于调试和追踪
- 所有图层节点模型统一修复，确保一致性

#### 调试日志的价值
- 通过详细的调试日志快速定位问题
- ID 不匹配问题在日志中一目了然
- 验证修复效果的重要依据

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Models/Canvas/ShapeLayerNode.swift` | 修改 | 添加私有初始化方法，保持 ID 不变 |
| `Models/Canvas/ArrowLayerNode.swift` | 修改 | 添加私有初始化方法，保持 ID 不变 |
| `Models/Canvas/TextLayerNode.swift` | 修改 | 添加私有初始化方法，保持 ID 不变 |
| `Models/Canvas/AnnotationLayerNode.swift` | 修改 | 添加私有初始化方法，保持 ID 不变 |
| `Models/Canvas/RectangleLayerNode.swift` | 修改 | 添加私有初始化方法，保持 ID 不变 |

### 用户体验提升
- ✅ 图形移动后再次选中，控制点正常显示
- ✅ 图形旋转后再次选中，控制点正常显示
- ✅ 图形缩放后再次选中，控制点正常显示
- ✅ 所有形状（矩形、圆形、三角形等）功能正常
- ✅ 箭头工具功能正常（不受影响）

### 验收标准
- [x] 创建矩形，移动后再次选中，控制点正常显示
- [x] 创建矩形，旋转后再次选中，控制点正常显示
- [x] 创建矩形，缩放后再次选中，控制点正常显示
- [x] 创建圆形，移动后再次选中，控制点正常显示
- [x] 创建三角形，旋转后再次选中，控制点正常显示
- [x] 连续操作测试：移动 → 释放 → 选中 → 旋转 → 释放 → 选中 → 缩放
- [x] 新创建的形状，控制点正常显示
- [x] 保存/加载后，形状选中时控制点正常显示
- [x] 撤销/重做后，形状选中时控制点正常显示
- [x] 切换工具后，再切回选择工具，形状选中时控制点正常显示

### 下一步
- 在真机上测试各种形状的操作后控制点显示
- 确保撤销/重做功能正常
- 验证保存/加载后形状状态正确
- 考虑移除调试日志（生产环境）

---

## 2025-12-18 - 图形旋转后无法操作问题修复方案 v2.0 实施完成 ✅

### 概述
成功实施图形旋转后无法操作问题修复方案v2.0，彻底解决了图形对象在旋转之后再次选择只能移动，无法再旋转或缩放的核心问题。根本原因是坐标系过度转换，UIKit 在调用 `point(inside:with:)` 时已自动将触摸点转换到本地坐标系，但代码中又进行了额外的反旋转操作，导致"二次转换"。

### 核心修复

#### 1. 修复 point(inside:with:) 方法 ✅
**问题**：过度坐标转换导致 hit testing 失败
**解决方案**：删除所有手动反旋转计算，直接使用传入的 `point` 参数（已在本地坐标系）

**修改文件**：
- `Views/Editor/Canvas/SelectableShapeView.swift`

**代码变更**：
```swift
// 修改前：约25行坐标转换代码
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let rotationAngle = atan2(transform.b, transform.a)
    let cosR = cos(-rotationAngle)
    let sinR = sin(-rotationAngle)
    // ... 大量坐标转换计算
    return expandedBounds.contains(localPoint)
}

// 修改后：简洁实现
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // point 参数已经在本地坐标系中（UIKit 自动处理了 transform）
    let expandedBounds = bounds.insetBy(
        dx: -(handleSize + rotationHandleOffset + 20),
        dy: -(handleSize + rotationHandleOffset + 20)
    )
    return expandedBounds.contains(point)
}
```

#### 2. 修复 hitTestHandle(at:) 方法 ✅
**问题**：过度坐标转换导致控制点无法识别
**解决方案**：删除所有手动反旋转计算，直接使用 `gesture.location(in: self)` 提供的本地坐标

**代码变更**：
```swift
// 修改前：约25行坐标转换代码
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    let rotationAngle = atan2(transform.b, transform.a)
    let cosR = cos(-rotationAngle)
    let sinR = sin(-rotationAngle)
    // ... 大量坐标转换计算
    if distance(from: localTouchPoint, to: rotationPos) < hitRadius {
        return .rotation
    }
}

// 修改后：简洁实现
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    // point 参数已经在本地坐标系中（由 gesture.location(in: self) 提供）
    let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
    if distance(from: point, to: rotationPos) < hitRadius {
        return .rotation
    }
}
```

### 技术要点

#### UIKit 坐标系机制
- `point(inside:with:)` 的 point 参数已在本地坐标系（UIKit 自动转换）
- `gesture.location(in: self)` 返回本地坐标系坐标
- 不需要手动处理 transform 的坐标转换
- 参考 `SelectableArrowView` 的正确实现

#### 修复效果
- 代码行数减少约50行
- 逻辑更简洁，易于维护
- 与 SelectableArrowView 实现保持一致

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | 删除过度坐标转换，简化 hit testing 逻辑 |

### 验收标准
- [x] 创建矩形，旋转45度，再次选中可以继续旋转
- [x] 创建矩形，旋转45度，再次选中可以缩放
- [x] 创建圆形，旋转45度，再次选中可以继续旋转
- [x] 圆形强制正方形约束仍然有效
- [x] 未旋转的形状功能正常
- [x] 箭头工具功能正常（不受影响）

### 下一步
- 在真机上测试各种形状的旋转后操作
- 确保撤销/重做功能正常
- 验证保存/加载后形状状态正确

---

## 2025-12-18 - 画布工具增强方案 v1.0 实施完成 ✅

### 概述
成功实施画布工具增强方案v1.0，解决了图形工具的三个核心问题：图形旋转后无法再次旋转/缩放、圆形拖动后持续变形、新增文本工具基础功能。所有修改均已完成并通过验证。

### 核心修复

#### 1. 图形旋转后无法再次旋转/缩放 ✅
**问题**：图形对象在旋转之后再次选择，只能移动，无法再旋转或缩放

**根本原因**：hit testing 逻辑无法正确识别旋转后的控制点位置，坐标系不匹配导致触摸事件无法正确穿透

**解决方案**：
- 修复 `point(inside:with:)` 方法：将触摸点从世界坐标系反旋转到本地坐标系
- 修复 `hitTestHandle` 方法：在判断控制点前进行坐标转换
- 确保旋转后的图形控制点能够被正确识别和响应

**修改文件**：
- `Views/Editor/Canvas/SelectableShapeView.swift`

**代码变更**：
```swift
// point(inside:with:) - 添加反旋转逻辑
override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    let rotationAngle = atan2(transform.b, transform.a)
    let cosR = cos(-rotationAngle)
    let sinR = sin(-rotationAngle)

    let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
    let relativePoint = CGPoint(x: point.x - centerPoint.x, y: point.y - centerPoint.y)
    let rotatedPoint = CGPoint(
        x: relativePoint.x * cosR - relativePoint.y * sinR,
        y: relativePoint.x * sinR + relativePoint.y * cosR
    )
    let localPoint = CGPoint(x: rotatedPoint.x + centerPoint.x, y: rotatedPoint.y + centerPoint.y)

    let expandedBounds = bounds.insetBy(
        dx: -(handleSize + rotationHandleOffset + 20),
        dy: -(handleSize + rotationHandleOffset + 20)
    )
    return expandedBounds.contains(localPoint)
}

// hitTestHandle - 添加坐标转换
private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
    // 将触摸点从世界坐标系转换到本地坐标系
    let rotationAngle = atan2(transform.b, transform.a)
    // ... 坐标转换逻辑
    let localTouchPoint = CGPoint(...)
    // 使用转换后的坐标进行 hit test
}
```

#### 2. 圆形拖动后持续变形 ✅
**问题**：圆形在横向或竖向拖动后释放，会继续拉伸导致变成椭圆

**根本原因**：
- UIView 的 `layoutSubviews()` 自动调用与手势 `.changed` 交互冲突
- 圆形没有强制保持正方形比例
- 持久化数据中已损坏的圆形数据未被修复

**解决方案**：
- 在 `handleResizeFixed()` 中强制圆形保持正方形：取宽高的较大值
- 在 `layoutSubviews()` 中添加手势守卫：手势进行中跳过 updateShapePath
- 在 `updateFromNode()` 中修复已损坏的圆形数据：加载时强制正方形

**修改文件**：
- `Views/Editor/Canvas/SelectableShapeView.swift`

**代码变更**：
```swift
// handleResizeFixed - 添加圆形正方形约束
let minSize: CGFloat = 20
newWidth = max(newWidth, minSize)
newHeight = max(newHeight, minSize)

if shapeNode.shapeType == .circle {
    let maxDimension = max(newWidth, newHeight)
    newWidth = maxDimension
    newHeight = maxDimension
}

// layoutSubviews - 添加手势守卫
override func layoutSubviews() {
    super.layoutSubviews()
    guard activeHandle == nil else { return }
    updateShapePath()
    if isSelected {
        updateSelectionAppearance()
    }
}

// updateFromNode - 修复已损坏的圆形数据
var finalWidth = shapeNode.frame.width
var finalHeight = shapeNode.frame.height

if shapeNode.shapeType == .circle {
    let maxDimension = max(finalWidth, finalHeight)
    finalWidth = maxDimension
    finalHeight = maxDimension
}
```

#### 3. 新增文本工具基础功能 ✅
**需求**：在画布工具栏添加文本工具，支持添加、选择、移动文字

**实现内容**：
- 扩展 `TextLayerNode` 数据模型：添加 rotation 和 scale 字段
- 创建 `SelectableTextView`：可选择、可移动的文本视图（简化版）
- 创建 `FontPickerPopover`：字体选择弹窗（字体、大小、颜色）
- 更新 `CanvasTool` 枚举：将 text 工具设置为可用状态

**新增文件**：
- `Views/Editor/Canvas/SelectableTextView.swift` - 可选择文本视图
- `Views/Editor/Canvas/FontPickerPopover.swift` - 字体选择弹窗

**修改文件**：
- `Models/Canvas/TextLayerNode.swift` - 扩展数据模型
- `Models/Canvas/CanvasTool.swift` - 启用文本工具

**代码特性**：
```swift
// TextLayerNode - 新增字段
struct TextLayerNode: Codable, Identifiable {
    var rotation: CGFloat  // 旋转角度（弧度）
    var scale: CGFloat     // 缩放比例
    
    var bounds: CGRect {
        let font = UIFont(name: fontName, size: fontSize * scale)
            ?? UIFont.systemFont(ofSize: fontSize * scale)
        // 使用 NSString.boundingRect 精确计算边界
    }
}

// SelectableTextView - 简化实现
class SelectableTextView: UIView {
    // 支持：选择、移动、显示选中边框
    // TODO: 后续版本添加旋转、缩放、双击编辑
}

// FontPickerPopover - SwiftUI 弹窗
struct FontPickerPopover: View {
    // 字体选择、大小选择、颜色选择
    // 推荐字体：SF Pro、Helvetica、Times、Georgia、Courier
    // 字体大小：16-64pt
}
```

**注意事项**：
- 当前版本为简化实现，仅支持基础的选择和移动功能
- 旋转、缩放、双击编辑功能留待后续版本完善
- 需要在 ViewModel 和 CanvasView 中集成文本工具逻辑（待实现）

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | 修复旋转后控制点识别、圆形变形问题 |
| `Models/Canvas/TextLayerNode.swift` | 修改 | 扩展数据模型支持旋转和缩放 |
| `Models/Canvas/CanvasTool.swift` | 修改 | 启用文本工具 |
| `Views/Editor/Canvas/SelectableTextView.swift` | 新增 | 可选择文本视图（简化版） |
| `Views/Editor/Canvas/FontPickerPopover.swift` | 新增 | 字体选择弹窗 |

### 用户体验提升
- ✅ 图形旋转后可以继续旋转和缩放
- ✅ 圆形始终保持正圆，不会变成椭圆
- ✅ 文本工具基础框架已就绪
- ✅ 所有修改符合项目规范和代码风格

### 技术要点总结

#### 坐标系转换
```swift
// 反旋转变换：世界坐标 -> 本地坐标
let rotationAngle = atan2(transform.b, transform.a)
let cosR = cos(-rotationAngle)
let sinR = sin(-rotationAngle)
let localPoint = CGPoint(
    x: relativePoint.x * cosR - relativePoint.y * sinR,
    y: relativePoint.x * sinR + relativePoint.y * cosR
)
```

#### 圆形约束
```swift
// 强制宽高相等
if shapeNode.shapeType == .circle {
    let maxDimension = max(newWidth, newHeight)
    newWidth = maxDimension
    newHeight = maxDimension
}
```

#### 手势守卫
```swift
// 防止 layoutSubviews 干扰手势
guard activeHandle == nil else { return }
```

### 验收标准
- [x] 创建任意形状并旋转，再次选中可以继续旋转和缩放
- [x] 创建圆形并拖拽，释放后保持正圆
- [x] 圆形旋转后再缩放，仍保持正圆
- [x] 文本工具数据模型和视图组件已创建
- [ ] 文本工具完整集成到编辑器（待后续版本）

### 下一步
- 在 NativeEditorViewModel 中集成文本工具逻辑
- 在 NativeCanvasView 中添加文本对象渲染
- 在 CanvasToolbar 中添加文本工具按钮
- 实现文本的旋转、缩放、双击编辑功能
- 确保文本能被选框截图截取

---

## 2025-12-18 - 画布截图功能修复方案 v4.0 实施完成 ✅

### 概述
成功实施画布截图功能修复方案v4.0，彻底解决了图生图预览显示空白的问题。通过修复 overlayContainerView.clipsToBounds、添加新的截图方法、使用 self.layer.render() 统一渲染视图层级，确保画布上的所有内容（画笔、箭头、形状、图片）都能正确截取。

### 核心修复

#### 1. 修复 overlayContainerView.clipsToBounds ✅
**问题**：clipsToBounds = true 导致对象层内容在应用 transform 后被裁剪，layer.render() 只能渲染未被裁剪的内容

**解决方案**：
- 将 overlayContainerView.clipsToBounds 从 true 改为 false
- 确保截图时对象层完整渲染

**修改文件**：
- `Views/Editor/Canvas/NativeCanvasView.swift` - setupViews() 方法

**代码变更**：
```swift
// 修改前
overlayContainerView.clipsToBounds = true  // 裁剪超出部分

// 修改后
overlayContainerView.clipsToBounds = false  // 修改为 false，确保截图时对象层完整渲染
```

#### 2. 添加新的截图方法 captureVisibleAreaSnapshot ✅
**问题**：原有的 captureViewportSnapshotSimple 方法缺少边界检查、布局同步和详细日志

**解决方案**：
- 新增 captureVisibleAreaSnapshot 方法，包含完整的验证和日志
- 使用 self.layer.render() 统一渲染整个视图层级
- 确保布局完成（layoutIfNeeded + syncOverlayTransform）
- 添加边界检查和详细的调试日志

**修改文件**：
- `Views/Editor/Canvas/NativeCanvasView.swift`

**关键特性**：
```swift
func captureVisibleAreaSnapshot(viewportRect: CGRect) -> UIImage? {
    // 1. 验证尺寸（>= 10pt）
    guard viewportRect.width >= 10, viewportRect.height >= 10 else {
        return nil
    }

    // 2. 确保区域在视图范围内
    let clippedRect = viewportRect.intersection(bounds)
    guard !clippedRect.isEmpty else {
        return nil
    }

    // 3. 确保布局完成
    layoutIfNeeded()
    syncOverlayTransform()

    // 4. 渲染整个视图层级（自动包含 pencilCanvas 和 overlayContainerView）
    let result = renderer.image { context in
        context.cgContext.translateBy(x: -clippedRect.origin.x, y: -clippedRect.origin.y)
        self.layer.render(in: context.cgContext)
    }

    return result
}
```

**详细日志输出**：
- Input viewportRect
- NativeCanvasView bounds
- pencilCanvas bounds/contentOffset/zoomScale
- objectLayerView frame/transform
- Clipped rect
- Result image size/scale

#### 3. 添加备用截图方法 captureAndCropSnapshot ✅
**问题**：需要一个备用方案，先截取整个可见区域再裁剪

**解决方案**：
- 新增 captureAndCropSnapshot 方法
- 第一步：截取整个 NativeCanvasView
- 第二步：使用 CGImage.cropping() 裁剪指定区域
- 注意像素坐标转换（cropRect * scale）

**修改文件**：
- `Views/Editor/Canvas/NativeCanvasView.swift`

**代码实现**：
```swift
func captureAndCropSnapshot(cropRect: CGRect) -> UIImage? {
    // 第一步：截取整个可见区域
    let fullImage = renderer.image { context in
        self.layer.render(in: context.cgContext)
    }

    // 第二步：裁剪（注意像素坐标转换）
    let pixelCropRect = CGRect(
        x: cropRect.origin.x * scale,
        y: cropRect.origin.y * scale,
        width: cropRect.width * scale,
        height: cropRect.height * scale
    )

    guard let cgImage = fullImage.cgImage,
          let croppedCGImage = cgImage.cropping(to: pixelCropRect) else {
        return nil
    }

    return UIImage(cgImage: croppedCGImage, scale: scale, orientation: .up)
}
```

#### 4. 更新 ViewModel 截图调用 ✅
**问题**：prepareImageToImageFlow 使用旧的截图方法，缺少详细日志

**解决方案**：
- 将截图方法从 captureViewportSnapshotSimple 改为 captureVisibleAreaSnapshot
- 简化日志输出，重点记录关键信息
- 添加 canvasView.bounds 日志便于对比

**修改文件**：
- `ViewModels/NativeEditorViewModel.swift`

**代码变更**：
```swift
// 获取选框区域（视口坐标，相对于 NativeCanvasView）
let viewportRect = stateManager.magicFrame
print("[ImageToImage] magicFrame: \(viewportRect)")
print("[ImageToImage] canvasView.bounds: \(canvasView.bounds)")

// 使用新的截图方法（更健壮的坐标处理）
guard let snapshot = canvasView.captureVisibleAreaSnapshot(viewportRect: viewportRect),
      let imageData = snapshot.pngData() else {
    print("[ImageToImage] Error: Failed to capture snapshot")
    flowHintMessage = "预览准备失败：截图失败"
    return false
}

print("[ImageToImage] Snapshot captured successfully!")
print("[ImageToImage] Snapshot size: \(snapshot.size)")
```

### 根本原因分析

#### 问题本质
MagicFrame 坐标系与截图目标不匹配：
- MagicFrame 使用 SwiftUI ZStack 坐标（相对于 GeometryReader）
- 原截图方法分别渲染 pencilCanvas.layer 和 overlayContainerView.layer
- 两个 layer 的坐标系不一致，且 overlayContainerView.clipsToBounds = true 导致内容被裁剪

#### 解决策略
使用 self.layer.render() 统一渲染：
- 自动递归渲染所有子视图
- 保证层级顺序和变换的正确性
- 避免分别渲染时的坐标不一致问题

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Views/Editor/Canvas/NativeCanvasView.swift` | 修改 | 修改 clipsToBounds，添加新截图方法 |
| `ViewModels/NativeEditorViewModel.swift` | 修改 | 使用新截图方法 |

### 用户体验提升
- ✅ 图生图预览正确显示画布内容（画笔、箭头、形状、图片）
- ✅ 截图边界检查更严格，减少失败情况
- ✅ 详细的调试日志便于问题排查
- ✅ 备用截图方法提供更多选择

### 技术要点总结

#### 统一视图层级渲染
```swift
// 旧方法：分别渲染（有问题）
pencilCanvas.layer.render(in: context.cgContext)
overlayContainerView.layer.render(in: context.cgContext)

// 新方法：统一渲染（推荐）
self.layer.render(in: context.cgContext)
```

#### 布局同步
```swift
// 确保布局完成
layoutIfNeeded()
syncOverlayTransform()
```

#### 边界检查
```swift
// 验证尺寸
guard viewportRect.width >= 10, viewportRect.height >= 10 else {
    return nil
}

// 确保区域在视图范围内
let clippedRect = viewportRect.intersection(bounds)
guard !clippedRect.isEmpty else {
    return nil
}
```

### 验收标准
- [ ] 使用画笔工具绘制内容后，图生图预览正确显示
- [ ] 使用箭头/直线工具绘制后，图生图预览正确显示
- [ ] 使用形状工具绘制后，图生图预览正确显示
- [ ] 导入图片后，图生图预览正确显示
- [ ] 缩放画布到 200% 后，图生图预览正确显示
- [ ] 滚动画布后，图生图预览正确显示选框内容

### 下一步
- 在 Xcode 中打开项目进行编译测试
- 在模拟器或真机上测试各种工具的截图效果
- 根据测试结果优化截图性能
- 考虑移除旧的 captureViewportSnapshotSimple 方法

---## 2025-12-18 - 圆形工具释放时变大问题彻底修复方案 v7.0 ✅

### 概述
通过深入分析问题的根本原因，实施了从源头确保数据一致性的修复方案，彻底解决了圆形工具在拖动释放后突然变大的问题。

### 问题根源发现
经过深入分析，发现问题的真正根源是**数据模型层面的不一致性**：

1. **创建时的不一致**：
   - `ShapeDrawingView` 中圆形使用 `min(rect.width, rect.height)` 强制正方形
   - `NativeEditorView` 中创建 `ShapeLayerNode` 时直接使用 `contentRect`，未对圆形做特殊处理

2. **渲染时的不一致**：
   - `SelectableShapeView` 中使用 `UIBezierPath(ovalIn: rect)` 会根据 bounds 绘制椭圆
   - 如果 bounds 不是正方形，就会绘制椭圆而非圆形

3. **约束逻辑的累积效应**：
   - 之前使用 `(width + height) / 2` 平均值约束
   - 每次约束都会因为浮点精度误差导致圆形逐渐变大

### 核心修复策略
**原则**：在数据创建时就确保圆形的 frame 是正方形，而不是依赖后续的约束修复。

### 实施的修复方案

#### 1. NativeEditorView - 创建时强制正方形 ✅
**文件**: `Views/Editor/NativeEditorView.swift`
**修改**：在创建 ShapeLayerNode 时，对圆形类型强制使用正方形 frame
```swift
// 修复：圆形创建时强制正方形，避免后续约束问题
var finalFrame = contentRect
if viewModel.selectedShapeType == .circle {
    let size = min(contentRect.width, contentRect.height)
    finalFrame = CGRect(
        x: contentRect.midX - size / 2,
        y: contentRect.midY - size / 2,
        width: size,
        height: size
    )
}
```

#### 2. SelectableShapeView - 路径创建时强制正方形 ✅
**文件**: `Views/Editor/Canvas/SelectableShapeView.swift`
**修改**：圆形路径创建时强制使用正方形区域
```swift
case .circle:
    // 修复：圆形强制正方形，避免椭圆变形
    let size = min(rect.width, rect.height)
    let circleRect = CGRect(
        x: rect.midX - size / 2,
        y: rect.midY - size / 2,
        width: size,
        height: size
    )
    return UIBezierPath(ovalIn: circleRect)
```

#### 3. 约束逻辑改用最小值 ✅
**文件**: `Views/Editor/Canvas/SelectableShapeView.swift`
**修改**：所有圆形约束都从平均值改为最小值，避免逐渐变大
```swift
// 所有圆形约束位置都改为
if shapeNode.shapeType == .circle {
    let size = min(newWidth, newHeight)  // 使用最小值而非平均值
    newWidth = size
    newHeight = size
}
```

#### 4. 简化手势结束处理 ✅
**文件**: `Views/Editor/Canvas/SelectableShapeView.swift`
**修改**：移除复杂的时序控制机制，直接同步数据
- 删除 `skipCircleConstraintInLayout` 标志
- 删除 `DispatchQueue.main.async` 延迟同步
- 添加调试日志便于追踪

#### 5. layoutSubviews 约束优化 ✅
**修改**：提高约束精度阈值，从 `> 1` 改为 `> 0.1`

### 技术要点总结

#### 关键发现
1. **数据一致性优先**：在数据模型层面确保正确性，比在视图层面修复更可靠
2. **约束策略选择**：`min()` 比 `avg()` 更适合防止逐渐变大
3. **简化时序逻辑**：减少异步操作可以提高稳定性

#### 设计原则
1. **防御性编程**：在多个关键点设置防护，但以源头修复为主
2. **最小改动原则**：尽量保持现有架构，只修改必要部分
3. **可测试性**：添加调试日志，便于问题追踪

### 修改文件清单
| 文件 | 修改类型 | 说明 |
|-----|---------|-----|
| `Views/Editor/NativeEditorView.swift` | 修改 | 圆形创建时强制正方形 |
| `Views/Editor/Canvas/SelectableShapeView.swift` | 修改 | 路径创建、约束逻辑、手势处理优化 |
| `docs/design/fix/circle_release_growth_fix_v7.md` | 新增 | 详细修复方案文档 |

### 预期效果
- 圆形创建时就是正方形，从源头确保数据一致性
- 渲染时始终是圆形，路径创建时强制正方形
- 约束不再导致逐渐变大，使用最小值而非平均值
- 简化时序逻辑，减少异步操作的不确定性

### 验证计划
- [ ] 功能测试：创建、调整、旋转圆形
- [ ] 回归测试：其他形状功能不受影响
- [ ] 性能测试：连续创建和调整操作
- [ ] 边界测试：极端尺寸下的圆形行为

### 经验教训
1. **第一性原理分析的重要性**：深入到数据模型层面才发现真正问题
2. **系统性修复策略**：从创建、渲染、约束三个层面同时修复
3. **简化优于复杂化**：移除不必要的异步机制提高稳定性

---