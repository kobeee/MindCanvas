# 画笔笔画被图片遮挡问题修复方案 v3.0

## 问题回顾

### 原始问题
用户在图片上使用画笔绘画时，笔画被图片遮挡，无法实时看到绘画效果。

### v2.0 方案的问题
按照 v2.0 方案实现后出现严重问题：
1. 画笔依旧无法在图片上绘画
2. 左侧资源栏消失
3. 图片和五角星等对象跑到画布外面，悬浮在右侧面板上

### 问题根因分析
v2.0 方案移除了 `overlayContainerView`，导致：
1. `objectLayerView` 和 `textOverlayView` 的 frame 是 5000x5000（画布大小）
2. 它们直接添加到 `NativeCanvasView`，没有被任何容器裁剪
3. 虽然设置了 `clipsToBounds = true`，但这只裁剪它们的子视图，不裁剪它们自己
4. 由于 `NativeCanvasView` 没有设置 `clipsToBounds = true`，对象超出了画布区域

---

## 正确的解决方案

### 核心思路

1. **使用两个容器视图**：一个在 `pencilCanvas` 下方，一个在上方
2. **容器视图与 NativeCanvasView 同样大小**：确保裁剪效果
3. **容器视图设置 clipsToBounds = true**：裁剪超出边界的内容
4. **PKCanvasView 设置透明背景**：让下方的对象可见

### 新的视图层级

```
NativeCanvasView
├── belowStrokeContainerView (与 NativeCanvasView 同样大小, clipsToBounds = true)
│   ├── canvasBackgroundView (5000x5000, 白色背景)
│   └── objectLayerView (5000x5000, 图片/箭头/形状)
├── pencilCanvas (PKCanvasView, 透明背景)
└── aboveStrokeContainerView (与 NativeCanvasView 同样大小, clipsToBounds = true)
    └── textOverlayView (5000x5000, 文字覆盖层)
```

### 层级说明

| 层级 | 视图 | 作用 | 裁剪 |
|------|------|------|------|
| 最底层 | belowStrokeContainerView | 容器，裁剪下方内容 | clipsToBounds = true |
| - | canvasBackgroundView | 白色背景 | - |
| - | objectLayerView | 图片/箭头/形状 | clipsToBounds = true |
| 中间层 | pencilCanvas | 透明绘图层 | - |
| 最顶层 | aboveStrokeContainerView | 容器，裁剪上方内容 | clipsToBounds = true |
| - | textOverlayView | 文字覆盖层 | clipsToBounds = true |

---

## 实现代码

### 步骤 1：添加两个容器视图

```swift
// NativeCanvasView.swift

// 新增属性
/// 笔画下方的容器视图（包含背景和对象层）
private let belowStrokeContainerView: UIView = {
    let view = UIView()
    view.backgroundColor = .clear
    view.clipsToBounds = true  // 关键：裁剪超出边界的内容
    return view
}()

/// 笔画上方的容器视图（包含文字覆盖层）
private let aboveStrokeContainerView: UIView = {
    let view = UIView()
    view.backgroundColor = .clear
    view.clipsToBounds = true  // 关键：裁剪超出边界的内容
    view.isUserInteractionEnabled = true
    return view
}()

/// 画布背景层（白色背景）
private let canvasBackgroundView: UIView = {
    let view = UIView()
    view.backgroundColor = .white
    return view
}()
```

### 步骤 2：修改 setupViews() 方法

```swift
private func setupViews() {
    backgroundColor = .systemGray6

    // 配置 PKCanvasView - 透明背景
    pencilCanvas.backgroundColor = .clear
    pencilCanvas.isOpaque = false
    pencilCanvas.tool = PKInkingTool(.pen, color: penColor, width: penLineWidth)
    pencilCanvas.delegate = self

    // 设置画布大小
    pencilCanvas.contentSize = canvasSize

    // 启用缩放
    pencilCanvas.minimumZoomScale = minZoomScale
    pencilCanvas.maximumZoomScale = maxZoomScale

    // 滚动设置
    pencilCanvas.showsVerticalScrollIndicator = false
    pencilCanvas.showsHorizontalScrollIndicator = false
    pencilCanvas.bounces = true
    pencilCanvas.bouncesZoom = true

    // 配置背景层
    canvasBackgroundView.frame = CGRect(origin: .zero, size: canvasSize)

    // 配置对象图层
    objectLayerView.backgroundColor = .clear
    objectLayerView.isUserInteractionEnabled = true
    objectLayerView.frame = CGRect(origin: .zero, size: canvasSize)
    objectLayerView.clipsToBounds = true
    objectLayerView.isOpaque = false

    // 配置文字覆盖层
    textOverlayView.backgroundColor = .clear
    textOverlayView.isUserInteractionEnabled = true
    textOverlayView.clipsToBounds = true
    textOverlayView.isOpaque = false
    textOverlayView.frame = CGRect(origin: .zero, size: canvasSize)

    // 构建视图层级
    // 1. 笔画下方的容器（包含背景和对象层）
    belowStrokeContainerView.addSubview(canvasBackgroundView)
    belowStrokeContainerView.addSubview(objectLayerView)

    // 2. 笔画上方的容器（包含文字覆盖层）
    aboveStrokeContainerView.addSubview(textOverlayView)

    // 3. 添加到主视图
    addSubview(belowStrokeContainerView)   // 最底层
    addSubview(pencilCanvas)                // 中间层（透明绘图）
    addSubview(aboveStrokeContainerView)   // 最顶层

    // 添加空白区域点击手势识别器
    addGestureRecognizer(canvasTapGesture)

    // 设置选中状态同步监听器
    setupSelectionSyncObserver()

    // 设置工具变化监听器
    setupToolObserver()

    // 初始化完成后设置状态
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.centerCanvas()
        self.onZoomChanged?(self.pencilCanvas.zoomScale)
    }
}
```

### 步骤 3：修改 setupConstraints() 方法

```swift
private func setupConstraints() {
    belowStrokeContainerView.translatesAutoresizingMaskIntoConstraints = false
    pencilCanvas.translatesAutoresizingMaskIntoConstraints = false
    aboveStrokeContainerView.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
        // belowStrokeContainerView 填满整个视图
        belowStrokeContainerView.topAnchor.constraint(equalTo: topAnchor),
        belowStrokeContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
        belowStrokeContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        belowStrokeContainerView.bottomAnchor.constraint(equalTo: bottomAnchor),

        // pencilCanvas 填满整个视图
        pencilCanvas.topAnchor.constraint(equalTo: topAnchor),
        pencilCanvas.leadingAnchor.constraint(equalTo: leadingAnchor),
        pencilCanvas.trailingAnchor.constraint(equalTo: trailingAnchor),
        pencilCanvas.bottomAnchor.constraint(equalTo: bottomAnchor),

        // aboveStrokeContainerView 填满整个视图
        aboveStrokeContainerView.topAnchor.constraint(equalTo: topAnchor),
        aboveStrokeContainerView.leadingAnchor.constraint(equalTo: leadingAnchor),
        aboveStrokeContainerView.trailingAnchor.constraint(equalTo: trailingAnchor),
        aboveStrokeContainerView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
}
```

### 步骤 4：修改 layoutSubviews() 方法

```swift
override func layoutSubviews() {
    super.layoutSubviews()
    // 背景层始终保持画布大小
    canvasBackgroundView.frame = CGRect(origin: .zero, size: canvasSize)
    // 对象图层始终保持画布大小
    objectLayerView.frame = CGRect(origin: .zero, size: canvasSize)
    // 文字覆盖层始终保持画布大小
    textOverlayView.frame = CGRect(origin: .zero, size: canvasSize)
    // 同步覆盖层变换
    syncOverlayTransform()
}
```

### 步骤 5：修改 syncOverlayTransform() 方法

```swift
/// 同步覆盖层的变换（位置和缩放）
private func syncOverlayTransform() {
    let offset = pencilCanvas.contentOffset
    let scale = pencilCanvas.zoomScale

    // canvasBackgroundView 变换（与画布同步）
    canvasBackgroundView.transform = CGAffineTransform(scaleX: scale, y: scale)
    canvasBackgroundView.frame.origin = CGPoint(x: -offset.x, y: -offset.y)

    // objectLayerView 变换（与画布同步）
    objectLayerView.transform = CGAffineTransform(scaleX: scale, y: scale)
    objectLayerView.frame.origin = CGPoint(x: -offset.x, y: -offset.y)

    // textOverlayView 变换（与画布同步）
    textOverlayView.transform = CGAffineTransform(scaleX: scale, y: scale)
    textOverlayView.frame.origin = CGPoint(x: -offset.x, y: -offset.y)
}
```

### 步骤 6：修改 updateForTool() 方法

将所有 `overlayContainerView` 的引用替换为对应的容器视图：

```swift
func updateForTool(_ tool: CanvasTool) {
    switch tool {
    case .select:
        // ...
        belowStrokeContainerView.isUserInteractionEnabled = true
        aboveStrokeContainerView.isUserInteractionEnabled = true
        objectLayerView.isUserInteractionEnabled = true
        textOverlayView.isUserInteractionEnabled = true
        // ...

    case .pan:
        // ...
        belowStrokeContainerView.isUserInteractionEnabled = false
        aboveStrokeContainerView.isUserInteractionEnabled = false
        // ...

    case .pen, .eraser:
        // ...
        belowStrokeContainerView.isUserInteractionEnabled = false
        aboveStrokeContainerView.isUserInteractionEnabled = false
        // ...

    case .image:
        // ...
        belowStrokeContainerView.isUserInteractionEnabled = true
        aboveStrokeContainerView.isUserInteractionEnabled = true
        objectLayerView.isUserInteractionEnabled = true
        // ...

    case .arrow, .rectangle, .text, .annotation:
        // ...
        belowStrokeContainerView.isUserInteractionEnabled = true
        aboveStrokeContainerView.isUserInteractionEnabled = true
        objectLayerView.isUserInteractionEnabled = false
        textOverlayView.isUserInteractionEnabled = true
        // ...
    }
}
```

---

## 关键点说明

### 1. 为什么需要两个容器视图？

- **belowStrokeContainerView**：包含背景和对象层，在笔画下方
- **aboveStrokeContainerView**：包含文字覆盖层，在笔画上方
- 两个容器都与 `NativeCanvasView` 同样大小，设置 `clipsToBounds = true`
- 这样可以裁剪超出画布区域的内容

### 2. 为什么 PKCanvasView 需要透明背景？

- 如果 PKCanvasView 是不透明的，下方的对象层会被完全遮挡
- 设置 `backgroundColor = .clear` 和 `isOpaque = false` 让下方内容可见
- 白色背景由 `canvasBackgroundView` 提供

### 3. 触摸事件如何传递？

- 当 `belowStrokeContainerView.isUserInteractionEnabled = false` 时，触摸事件穿透到 `pencilCanvas`
- 当 `belowStrokeContainerView.isUserInteractionEnabled = true` 时，触摸事件被 `objectLayerView` 中的对象处理
- `aboveStrokeContainerView` 使用 `TouchThroughView` 的 `textOverlayView`，空白区域的触摸会穿透

### 4. z-index 排序逻辑不变

- `sortAllSubviewsByZIndex()` 方法只调整 `objectLayerView` 内部的子视图顺序
- 不受视图层级调整影响

---

## 测试用例

### 基本功能测试

| 测试项 | 步骤 | 预期结果 |
|--------|------|----------|
| 在空白区域绘画 | 选择画笔，在空白区域绘画 | 笔画正常显示 |
| **在图片上绘画** | 选择画笔，在图片上绘画 | **笔画实时显示在图片上方** |
| 移动图片 | 绘画后，移动图片 | 笔画保持原位，图片移动后笔画可见 |
| 缩放画布 | 绘画后，缩放画布 | 笔画、图片、背景同步缩放 |
| 平移画布 | 绘画后，平移画布 | 笔画、图片、背景同步平移 |

### 边界裁剪测试

| 测试项 | 步骤 | 预期结果 |
|--------|------|----------|
| 对象不超出画布 | 将图片拖到画布边缘 | 图片被裁剪，不超出画布区域 |
| 资源栏正常显示 | 查看左侧资源栏 | 资源栏正常显示，不被对象遮挡 |
| 右侧面板正常显示 | 查看右侧面板 | 面板正常显示，不被对象遮挡 |

### 工具切换测试

| 测试项 | 步骤 | 预期结果 |
|--------|------|----------|
| 画笔 -> 选择 | 绘画后切换到选择工具 | 可以选中和移动图片 |
| 选择 -> 画笔 | 选中图片后切换到画笔 | 可以在图片上绘画 |

---

## 与 v2.0 方案的对比

| 方面 | v2.0 方案 | v3.0 方案 |
|------|----------|----------|
| 容器视图 | 移除 overlayContainerView | 使用两个容器视图 |
| 裁剪效果 | 无裁剪，对象超出边界 | 正确裁剪，对象限制在画布内 |
| 视图层级 | 4 层 | 5 层（多一个容器） |
| 复杂度 | 简单但有缺陷 | 稍复杂但正确 |

---

## 总结

v3.0 方案通过使用两个容器视图（`belowStrokeContainerView` 和 `aboveStrokeContainerView`），正确实现了：

1. **笔画显示在图片上方**：`objectLayerView` 在 `pencilCanvas` 下方
2. **文字显示在笔画上方**：`textOverlayView` 在 `pencilCanvas` 上方
3. **正确的边界裁剪**：两个容器都设置 `clipsToBounds = true`
4. **保持现有功能**：z-index 排序、触摸事件传递等不受影响

这是经过深入分析后的最优方案，解决了 v2.0 方案的所有问题。
