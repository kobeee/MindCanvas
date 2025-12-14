import SwiftUI
import UIKit
import PencilKit

/// 原生画布视图 (UIKit 实现)
/// 重构版本：直接使用 PKCanvasView 的内置缩放功能，不再嵌套 UIScrollView
/// 参考：https://github.com/simonbs/InfiniteCanvas
class NativeCanvasView: UIView {
    // MARK: - Properties

    /// Layer 1: 对象图层容器 (图片节点) - 放在 PKCanvasView 下面
    private let objectLayerView = UIView()

    /// Layer 2: PencilKit 绘图层 - PKCanvasView 本身就是 UIScrollView 的子类
    var pencilCanvas = PKCanvasView()

    /// 画布尺寸 (超大虚拟画布)
    private let canvasSize = CGSize(width: 5000, height: 5000)

    /// 缩放范围
    private let minZoomScale: CGFloat = 0.5
    private let maxZoomScale: CGFloat = 3.0
    
    /// 撤销后加载方案：true=重建PKCanvasView实例，false=使用append方法
    private let shouldRecreateCanvasViewOnLoad = true

    /// 当前工具（新架构）
    var currentTool: CanvasTool = .select {
        didSet {
            updateForTool(currentTool)
        }
    }

    /// 当前工具模式（兼容旧代码，将被移除）
    @available(*, deprecated, message: "使用 currentTool 代替")
    var currentMode: CanvasToolMode = .objectMode {
        didSet {
            switch currentMode {
            case .objectMode:
                if currentTool != .select && currentTool != .pan && currentTool != .image {
                    currentTool = .select
                }
            case .drawingMode:
                if currentTool != .pen && currentTool != .eraser {
                    currentTool = .pen
                }
            }
        }
    }

    /// 绘图工具 (画笔)
    private let inkingTool = PKInkingTool(.pen, color: .black, width: 2)

    /// 橡皮擦工具
    private let eraserTool = PKEraserTool(.vector)

    /// 图层节点数组
    private var layers: [LayerNode] = []

    /// 图片视图字典 (nodeID -> ResizableImageView)
    var imageViews: [UUID: ResizableImageView] = [:]

    /// 箭头视图字典 (nodeID -> SelectableArrowView)
    var arrowViews: [UUID: SelectableArrowView] = [:]

    /// 箭头图层管理器
    private let arrowLayerManager = ArrowLayerManager()

    /// 矩形图层管理器
    private let rectangleLayerManager = RectangleLayerManager()

    /// 文字图层管理器
    private let textLayerManager = TextLayerManager()

    /// 标注图层管理器
    private let annotationLayerManager = AnnotationLayerManager()

    /// 当前选中的节点 ID
    private var selectedNodeID: UUID? {
        didSet {
            updateSelectionStates()
        }
    }

    // MARK: - 回调闭包

    /// 画布更新回调
    var onCanvasUpdated: (() -> Void)?

    /// 选区变化回调
    var onSelectionChanged: ((Bool) -> Void)?

    /// 图层更新回调
    var onLayersUpdated: (([LayerNode]) -> Void)?

    /// 缩放变化回调
    var onZoomChanged: ((CGFloat) -> Void)?

    /// 绘制中标记
    private(set) var isDrawing = false

    /// 上一次的绘图数据（用于撤销/恢复）
    private var previousDrawingData: Data?

    /// 当前笔画开始前的绘图数据（用于撤销/恢复）
    private var strokeStartDrawingData: Data?

    /// 是否有待处理的笔画撤销操作
    private var hasPendingStrokeUndo = false

    /// 是否正在加载绘图数据（用于区分用户绘制和程序加载）
    private var isLoadingDrawing = false

    // MARK: - 箭头绘制回调
    var onArrowCreated: ((ArrowLayerNode) -> Void)?
    var onRectangleCreated: ((RectangleLayerNode) -> Void)?
    var onTextCreated: ((TextLayerNode) -> Void)?
    var onAnnotationCreated: ((AnnotationLayerNode) -> Void)?

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = .systemGray6

        // 配置 PKCanvasView - 关键：直接使用其内置的缩放功能
        pencilCanvas.backgroundColor = .white
        pencilCanvas.isOpaque = true
        pencilCanvas.tool = inkingTool
        pencilCanvas.delegate = self

        // 设置画布大小 - PKCanvasView 本身就是 UIScrollView
        pencilCanvas.contentSize = canvasSize

        // 启用缩放 - 这是 PKCanvasView 内置的功能！
        pencilCanvas.minimumZoomScale = minZoomScale
        pencilCanvas.maximumZoomScale = maxZoomScale

        // 滚动设置
        pencilCanvas.showsVerticalScrollIndicator = false
        pencilCanvas.showsHorizontalScrollIndicator = false
        pencilCanvas.bounces = true
        pencilCanvas.bouncesZoom = true

        // 配置对象图层 - 作为 PKCanvasView 的子视图
        objectLayerView.backgroundColor = .clear
        objectLayerView.isUserInteractionEnabled = true
        objectLayerView.frame = CGRect(origin: .zero, size: canvasSize)
        objectLayerView.clipsToBounds = false // 关键：允许子视图超出边界显示
        objectLayerView.isOpaque = false

        addSubview(pencilCanvas)

        // 关键修复：将 objectLayerView 添加到 pencilCanvas 内部
        // 参考 simonbs/InfiniteCanvas 和社区最佳实践
        // 使用 DispatchQueue 确保 pencilCanvas 布局完成后再添加
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 添加到 pencilCanvas 顶层（而不是索引 0）
            self.pencilCanvas.addSubview(self.objectLayerView)
            self.objectLayerView.frame = CGRect(origin: .zero, size: self.canvasSize)

            self.centerCanvas()
            self.updateForTool(self.currentTool)
            // zoomScale 是非可选值 CGFloat，不需要可选绑定
            self.onZoomChanged?(self.pencilCanvas.zoomScale)
        }
    }

    private func setupConstraints() {
        pencilCanvas.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            pencilCanvas.topAnchor.constraint(equalTo: topAnchor),
            pencilCanvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            pencilCanvas.trailingAnchor.constraint(equalTo: trailingAnchor),
            pencilCanvas.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 对象图层始终保持画布大小
        objectLayerView.frame = CGRect(origin: .zero, size: canvasSize)
    }

    // MARK: - Canvas Control

    /// 居中画布
    private func centerCanvas() {
        let xOffset = max(0, (canvasSize.width - pencilCanvas.bounds.width) / 2)
        let yOffset = max(0, (canvasSize.height - pencilCanvas.bounds.height) / 2)
        pencilCanvas.setContentOffset(CGPoint(x: xOffset, y: yOffset), animated: false)
    }

    /// 重置缩放
    func resetZoom() {
        pencilCanvas.setZoomScale(1.0, animated: true)
    }

    /// 当前缩放比例
    var zoomScale: CGFloat {
        pencilCanvas.zoomScale
    }

    /// 设置缩放比例
    func setZoomScale(_ scale: CGFloat, animated: Bool) {
        let clamped = max(minZoomScale, min(maxZoomScale, scale))
        pencilCanvas.setZoomScale(clamped, animated: animated)
    }

    /// 清空画布
    func clearCanvas() {
        pencilCanvas.drawing = PKDrawing()
        removeAllLayers()
        onCanvasUpdated?()
    }

    // MARK: - Layer Management

    /// 添加图层
    func addLayer(_ layer: LayerNode, recordUndo: Bool = true) {
        layers.append(layer)
        sortLayers()
        createImageView(for: layer)
        onLayersUpdated?(layers)

        if recordUndo {
            let action = AddLayerAction(layer: layer, canvasView: self)
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
    }

    /// 移除图层
    func removeLayer(id: UUID, recordUndo: Bool = true) {
        let removedLayer = layers.first { $0.id == id }

        layers.removeAll { $0.id == id }
        imageViews[id]?.removeFromSuperview()
        imageViews.removeValue(forKey: id)
        onLayersUpdated?(layers)

        if recordUndo, let layer = removedLayer {
            let action = RemoveLayerAction(layer: layer, canvasView: self)
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
    }

    /// 更新图层
    func updateLayer(_ layer: LayerNode) {
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            layers[index] = layer
            imageViews[layer.id]?.node = layer
            sortLayers()
            onLayersUpdated?(layers)
        }
    }

    /// 移除所有图层
    func removeAllLayers() {
        layers.removeAll()
        imageViews.values.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()
        selectedNodeID = nil
        onLayersUpdated?(layers)
    }

    /// 按 zIndex 排序图层
    private func sortLayers() {
        layers.sort { $0.zIndex < $1.zIndex }

        for (index, layer) in layers.enumerated() {
            if let imageView = imageViews[layer.id] {
                objectLayerView.insertSubview(imageView, at: index)
            }
        }
    }

    /// 创建图片视图
    private func createImageView(for layer: LayerNode) {
        let imageView = ResizableImageView(node: layer)

        var operationStartNode: LayerNode?

        imageView.onNodeUpdated = { [weak self] updatedNode in
            self?.updateLayer(updatedNode)
        }

        imageView.onSelected = { [weak self] nodeID in
            self?.selectedNodeID = nodeID
        }

        imageView.onOperationStart = { node in
            operationStartNode = node
        }

        imageView.onOperationEnd = { [weak self] _, endNode in
            guard let self = self, let startNode = operationStartNode else { return }

            if startNode.frame != endNode.frame {
                if startNode.frame.size == endNode.frame.size {
                    let action = MoveLayerAction(
                        layerID: startNode.id,
                        fromFrame: startNode.frame,
                        toFrame: endNode.frame,
                        canvasView: self
                    )
                    NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
                } else {
                    let action = ScaleLayerAction(
                        layerID: startNode.id,
                        fromFrame: startNode.frame,
                        toFrame: endNode.frame,
                        canvasView: self
                    )
                    NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
                }
            } else if abs(startNode.rotation - endNode.rotation) > 0.001 {
                let action = RotateLayerAction(
                    layerID: startNode.id,
                    fromRotation: startNode.rotation,
                    toRotation: endNode.rotation,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }

            operationStartNode = nil
        }

        imageViews[layer.id] = imageView
        objectLayerView.addSubview(imageView)
        
        // 根据当前工具状态设置手势
        if currentTool == .select || currentTool == .image {
            imageView.enableObjectGestures()
        }
        
        sortLayers()
    }
    
    /// 创建箭头视图
    private func createArrowView(for arrow: ArrowLayerNode) {
        print("[Arrow] createArrowView: bounds=\(arrow.bounds), objectLayerView.frame=\(objectLayerView.frame)")
        let arrowView = SelectableArrowView(arrowNode: arrow)
        print("[Arrow] arrowView created: frame=\(arrowView.frame)")
        
        var operationStartArrow: ArrowLayerNode?
        
        arrowView.onNodeUpdated = { [weak self] updatedArrow in
            self?.arrowLayerManager.updateArrow(updatedArrow)
        }
        
        arrowView.onSelected = { [weak self] arrowID in
            self?.selectedNodeID = arrowID
        }
        
        arrowView.onOperationStart = { arrow in
            operationStartArrow = arrow
        }
        
        arrowView.onOperationEnd = { [weak self] _, endArrow in
            guard let self = self, let startArrow = operationStartArrow else { return }
            
            // 记录箭头移动操作
            if startArrow.startPoint != endArrow.startPoint || startArrow.endPoint != endArrow.endPoint {
                let action = MoveArrowAction(
                    arrowID: startArrow.id,
                    fromArrow: startArrow,
                    toArrow: endArrow,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            
            operationStartArrow = nil
        }
        
        arrowViews[arrow.id] = arrowView
        objectLayerView.addSubview(arrowView)

        // 根据当前工具状态设置手势
        if currentTool == .select || currentTool == .arrow {
            arrowView.enableArrowGestures()
        }

        // 关键修复：强制立即布局，确保视图可见
        arrowView.setNeedsLayout()
        arrowView.layoutIfNeeded()
        objectLayerView.setNeedsLayout()
        objectLayerView.layoutIfNeeded()

        print("[Arrow] arrowView added to superview: \(arrowView.superview != nil), frame=\(arrowView.frame)")
        print("[Arrow] objectLayerView subviews count: \(objectLayerView.subviews.count)")
    }

    /// 更新选中状态
    private func updateSelectionStates() {
        // 更新图片视图选中状态
        for (id, imageView) in imageViews {
            imageView.isSelected = (id == selectedNodeID)
        }
        
        // 更新箭头视图选中状态
        for (id, arrowView) in arrowViews {
            arrowView.isSelected = (id == selectedNodeID)
        }
        
        onSelectionChanged?(selectedNodeID != nil)
    }

    /// 获取所有图层
    func getLayers() -> [LayerNode] {
        layers
    }

    /// 设置图层数据 (批量加载)
    func setLayers(_ newLayers: [LayerNode]) {
        removeAllLayers()
        newLayers.forEach { addLayer($0, recordUndo: false) }
    }

    /// 图层操作：置顶
    func bringLayerToFront(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        let maxZ = layers.map(\.zIndex).max() ?? 0
        layers[index].zIndex = maxZ + 1
        sortLayers()
        onLayersUpdated?(layers)
    }

    /// 图层操作：置底
    func sendLayerToBack(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        let minZ = layers.map(\.zIndex).min() ?? 0
        layers[index].zIndex = minZ - 1
        sortLayers()
        onLayersUpdated?(layers)
    }

    /// 锁定/解锁图层
    func toggleLayerLock(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].isLocked.toggle()
        imageViews[id]?.node = layers[index]
        onLayersUpdated?(layers)
    }

    /// 获取当前选中的图层
    func getSelectedLayer() -> LayerNode? {
        guard let id = selectedNodeID else { return nil }
        return layers.first { $0.id == id }
    }

    // MARK: - Tool Management

    /// 根据工具更新手势处理
    func updateForTool(_ tool: CanvasTool) {
        switch tool {
        case .select:
            // 选择工具：禁用绘图手势，启用对象层手势
            // 注意：不能设置 pencilCanvas.isUserInteractionEnabled = false
            // 因为 objectLayerView 是 pencilCanvas 的子视图，父视图禁用交互会导致子视图也无法接收事件
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.drawingGestureRecognizer.isEnabled = false
            pencilCanvas.drawingPolicy = .default
            pencilCanvas.isScrollEnabled = false
            pencilCanvas.panGestureRecognizer.isEnabled = false
            pencilCanvas.pinchGestureRecognizer?.isEnabled = false
            objectLayerView.isUserInteractionEnabled = true

            // 确保所有对象的手势都能正常工作
            for imageView in imageViews.values {
                imageView.enableObjectGestures()
            }

            // 确保所有箭头的手势都能正常工作
            for arrowView in arrowViews.values {
                arrowView.enableArrowGestures()
            }

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

        case .pen:
            // 画笔工具：启用绘图，禁用对象手势，禁用画布滚动
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.tool = inkingTool
            pencilCanvas.drawingPolicy = .anyInput
            pencilCanvas.drawingGestureRecognizer.isEnabled = true
            objectLayerView.isUserInteractionEnabled = false
            pencilCanvas.isScrollEnabled = false
            pencilCanvas.panGestureRecognizer.isEnabled = false
            pencilCanvas.pinchGestureRecognizer?.isEnabled = false

        case .eraser:
            // 橡皮擦工具：启用擦除，禁用对象手势，禁用画布滚动
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.tool = eraserTool
            pencilCanvas.drawingPolicy = .anyInput
            pencilCanvas.drawingGestureRecognizer.isEnabled = true
            objectLayerView.isUserInteractionEnabled = false
            pencilCanvas.isScrollEnabled = false
            pencilCanvas.panGestureRecognizer.isEnabled = false
            pencilCanvas.pinchGestureRecognizer?.isEnabled = false

        case .image:
            // 图片工具：与选择工具类似，允许操作对象
            // 同样不能禁用 pencilCanvas 交互，否则子视图 objectLayerView 也无法接收事件
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.drawingGestureRecognizer.isEnabled = false
            pencilCanvas.drawingPolicy = .default
            pencilCanvas.isScrollEnabled = false
            pencilCanvas.panGestureRecognizer.isEnabled = false
            pencilCanvas.pinchGestureRecognizer?.isEnabled = false
            objectLayerView.isUserInteractionEnabled = true

        case .arrow, .rectangle, .text, .annotation:
            // 其他工具：禁用绘图，禁用对象手势，启用画布滚动
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.drawingGestureRecognizer.isEnabled = false
            pencilCanvas.drawingPolicy = .default  // 非绘图工具设置为default
            objectLayerView.isUserInteractionEnabled = false
            pencilCanvas.isScrollEnabled = true
            pencilCanvas.panGestureRecognizer.isEnabled = true
            pencilCanvas.pinchGestureRecognizer?.isEnabled = true
        }
    }

    /// 切换绘图工具（兼容旧代码）
    @available(*, deprecated, message: "使用 currentTool = .pen/.eraser 代替")
    func setDrawingTool(isPen: Bool) {
        currentTool = isPen ? .pen : .eraser
    }

    // MARK: - Drawing Operations

    /// 获取当前绘图数据
    func getDrawingData() -> Data {
        pencilCanvas.drawing.dataRepresentation()
    }

    /// 加载绘图数据
    func loadDrawing(from data: Data) {
        isLoadingDrawing = true

        // 根据配置选择加载方案
        if shouldRecreateCanvasViewOnLoad {
            // 方案1：重建PKCanvasView实例以彻底清除内部状态（推荐）
            recreateCanvasViewWithDrawing(data)
        } else {
            // 方案2：使用PKDrawing.append方法（备选方案）
            loadDrawingUsingAppend(data)
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isLoadingDrawing = false
        }
    }
    
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
                // 静默处理错误，避免日志输出
            }
        }
        
        // 同步更新撤销基准数据
        strokeStartDrawingData = getDrawingData()
    }
    
    /// 设置PKCanvasView的基本属性
    private func setupPencilCanvas() {
        pencilCanvas.backgroundColor = .white
        pencilCanvas.isOpaque = true
        pencilCanvas.tool = inkingTool
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
        
        // 重新插入到视图层次中
        pencilCanvas.insertSubview(objectLayerView, at: 0)
        addSubview(pencilCanvas)
        
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
    
    /// 方案2：使用PKDrawing.append方法（备选方案）
    private func loadDrawingUsingAppend(_ data: Data) {
        // 完全清空当前绘图
        pencilCanvas.drawing = PKDrawing()
        
        // 清空UndoManager
        pencilCanvas.undoManager?.removeAllActions()
        
        // 如果有数据，使用append方法添加
        if !data.isEmpty {
            do {
                let newDrawing = try PKDrawing(data: data)
                // 创建新的PKDrawing并append strokes，而不是直接替换
                var mutableDrawing = pencilCanvas.drawing
                
                // 逐个添加strokes，避免直接替换导致的状态问题
                for stroke in newDrawing.strokes {
                    mutableDrawing.strokes.append(stroke)
                }
                
                pencilCanvas.drawing = mutableDrawing
            } catch {
                // 静默处理错误，避免日志输出
            }
        }
        
        // 再次清空UndoManager
        pencilCanvas.undoManager?.removeAllActions()
        
        // 同步更新撤销基准数据
        strokeStartDrawingData = getDrawingData()
    }

    // MARK: - Snapshot

    /// 捕获内容坐标系中的指定区域快照
    func captureContentSnapshot(rect contentRect: CGRect) -> UIImage? {
        let bounded = contentRect.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !bounded.isNull, bounded.width > 1, bounded.height > 1 else { return nil }

        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        // PencilKit 导出
        let drawingImage = pencilCanvas.drawing.image(from: bounded, scale: scale)

        // 对象层渲染
        let renderer = UIGraphicsImageRenderer(size: bounded.size, format: format)
        return renderer.image { rendererContext in
            let ctx = rendererContext.cgContext
            ctx.saveGState()
            ctx.clip(to: CGRect(origin: .zero, size: bounded.size))
            ctx.translateBy(x: -bounded.origin.x, y: -bounded.origin.y)
            objectLayerView.layer.render(in: ctx)
            ctx.restoreGState()
            drawingImage.draw(in: CGRect(origin: .zero, size: bounded.size))
        }
    }

    /// 将视口坐标映射到画布内容坐标
    func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
        let rectInCanvas = pencilCanvas.convert(viewportRect, from: self)
        // 考虑缩放
        let scale = pencilCanvas.zoomScale
        let offset = pencilCanvas.contentOffset
        return CGRect(
            x: (rectInCanvas.origin.x + offset.x) / scale,
            y: (rectInCanvas.origin.y + offset.y) / scale,
            width: rectInCanvas.width / scale,
            height: rectInCanvas.height / scale
        )
    }

    /// 捕获视口坐标区域的快照
    func captureViewportSnapshot(rect viewportRect: CGRect) -> UIImage? {
        let contentRect = contentRect(forViewportRect: viewportRect)
        return captureContentSnapshot(rect: contentRect)
    }

    /// 捕获整个画布快照
    func captureFullSnapshot() -> UIImage? {
        captureContentSnapshot(rect: CGRect(origin: .zero, size: canvasSize))
    }

    // MARK: - 箭头管理

    func getArrowLayerManager() -> ArrowLayerManager { arrowLayerManager }

    func addArrow(_ arrow: ArrowLayerNode, recordUndo: Bool = true) {
        print("[Arrow] addArrow called: start=\(arrow.startPoint), end=\(arrow.endPoint), bounds=\(arrow.bounds)")
        if recordUndo {
            let action = AddArrowAction(arrow: arrow, canvasView: self)
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
        arrowLayerManager.addArrow(arrow)
        createArrowView(for: arrow)
        print("[Arrow] arrowViews count: \(arrowViews.count), objectLayerView subviews: \(objectLayerView.subviews.count)")
        onArrowCreated?(arrow)
        onCanvasUpdated?()
    }

    func removeArrow(id: UUID) {
        arrowLayerManager.removeArrow(id: id)
        arrowViews[id]?.removeFromSuperview()
        arrowViews.removeValue(forKey: id)
        onCanvasUpdated?()
    }

    func updateArrow(_ arrow: ArrowLayerNode) {
        arrowLayerManager.updateArrow(arrow)
        onCanvasUpdated?()
    }

    func clearArrows() {
        arrowLayerManager.clearAll()
        onCanvasUpdated?()
    }

    // MARK: - 矩形管理

    func getRectangleLayerManager() -> RectangleLayerManager { rectangleLayerManager }

    func addRectangle(_ rectangle: RectangleLayerNode, recordUndo: Bool = true) {
        if recordUndo {
            let action = AddRectangleAction(rectangle: rectangle, canvasView: self)
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
        rectangleLayerManager.addRectangle(rectangle)
        onRectangleCreated?(rectangle)
        onCanvasUpdated?()
    }

    func removeRectangle(id: UUID) {
        rectangleLayerManager.removeRectangle(id: id)
        onCanvasUpdated?()
    }

    func updateRectangle(_ rectangle: RectangleLayerNode) {
        rectangleLayerManager.updateRectangle(rectangle)
        onCanvasUpdated?()
    }

    func clearRectangles() {
        rectangleLayerManager.clearAll()
        onCanvasUpdated?()
    }

    // MARK: - 文字管理

    func getTextLayerManager() -> TextLayerManager { textLayerManager }

    func addText(_ text: TextLayerNode, recordUndo: Bool = true) {
        if recordUndo {
            let action = AddTextAction(text: text, canvasView: self)
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
        textLayerManager.addText(text)
        onTextCreated?(text)
        onCanvasUpdated?()
    }

    func removeText(id: UUID) {
        textLayerManager.removeText(id: id)
        onCanvasUpdated?()
    }

    func updateText(_ text: TextLayerNode) {
        textLayerManager.updateText(text)
        onCanvasUpdated?()
    }

    func clearTexts() {
        textLayerManager.clearAll()
        onCanvasUpdated?()
    }

    // MARK: - 标注管理

    func getAnnotationLayerManager() -> AnnotationLayerManager { annotationLayerManager }

    func addAnnotation(_ annotation: AnnotationLayerNode, recordUndo: Bool = true) {
        if recordUndo {
            let action = AddAnnotationAction(annotation: annotation, canvasView: self)
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
        annotationLayerManager.addAnnotation(annotation)
        onAnnotationCreated?(annotation)
        onCanvasUpdated?()
    }

    func removeAnnotation(id: UUID) {
        annotationLayerManager.removeAnnotation(id: id)
        onCanvasUpdated?()
    }

    func updateAnnotation(_ annotation: AnnotationLayerNode) {
        annotationLayerManager.updateAnnotation(annotation)
        onCanvasUpdated?()
    }

    func clearAnnotations() {
        annotationLayerManager.clearAll()
        onCanvasUpdated?()
    }
}

// MARK: - PKCanvasViewDelegate

extension NativeCanvasView: PKCanvasViewDelegate {
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        isDrawing = true
        strokeStartDrawingData = getDrawingData()
        hasPendingStrokeUndo = true
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        isDrawing = false

        // 延迟创建撤销操作，确保 PencilKit 数据已更新
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.tryCreateStrokeUndoAction()
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        if isLoadingDrawing {
            return
        }

        if !isDrawing && hasPendingStrokeUndo {
            tryCreateStrokeUndoAction()
        }

        if !isDrawing {
            onCanvasUpdated?()
        }
    }

    // PKCanvasViewDelegate 继承自 UIScrollViewDelegate，所以可以监听缩放
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        onZoomChanged?(scrollView.zoomScale)
    }

    private func tryCreateStrokeUndoAction() {
        guard hasPendingStrokeUndo else {
            return
        }

        guard let startData = strokeStartDrawingData else {
            hasPendingStrokeUndo = false
            return
        }

        let currentData = getDrawingData()

        if startData != currentData {
            let action = DrawingAction(
                fromDrawingData: startData,
                toDrawingData: currentData,
                canvasView: self
            )

            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)

            hasPendingStrokeUndo = false
            strokeStartDrawingData = nil
        }
    }
}

// MARK: - SwiftUI Wrapper

struct NativeCanvasViewWrapper: UIViewRepresentable {
    @Binding var currentTool: CanvasTool
    var onCanvasUpdated: (() -> Void)?
    var onViewCreated: ((NativeCanvasView) -> Void)?
    var onZoomChanged: ((CGFloat) -> Void)? = nil

    func makeUIView(context: Context) -> NativeCanvasView {
        let view = NativeCanvasView()
        view.currentTool = currentTool
        view.onCanvasUpdated = onCanvasUpdated
        view.onZoomChanged = onZoomChanged
        onViewCreated?(view)
        return view
    }

    func updateUIView(_ uiView: NativeCanvasView, context: Context) {
        if uiView.currentTool != currentTool {
            uiView.currentTool = currentTool
        }
        uiView.onCanvasUpdated = onCanvasUpdated
        uiView.onZoomChanged = onZoomChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {}
}
