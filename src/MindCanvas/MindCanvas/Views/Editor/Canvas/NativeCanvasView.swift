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

    /// Layer 1.5: 覆盖层容器视图（与 pencilCanvas 同级，用于承载箭头等对象）
    private let overlayContainerView = UIView()

    /// Layer 2: PencilKit 绘图层 - PKCanvasView 本身就是 UIScrollView 的子类
    var pencilCanvas = PKCanvasView()

    /// 画布尺寸 (超大虚拟画布)
    let canvasSize = CGSize(width: 5000, height: 5000)

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

    // 画笔颜色和线宽（支持动态设置）
    var penColor: UIColor = .black
    var penLineWidth: CGFloat = 4

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
    
    /// 形状视图字典 (nodeID -> SelectableShapeView)
    var shapeViews: [UUID: SelectableShapeView] = [:]
    
    /// 形状图层管理器
    private let shapeLayerManager = ShapeLayerManager()

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
        pencilCanvas.tool = PKInkingTool(.pen, color: penColor, width: penLineWidth)
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

        // 配置覆盖层容器视图
        overlayContainerView.backgroundColor = .clear
        overlayContainerView.isUserInteractionEnabled = true
        overlayContainerView.clipsToBounds = false  // 修改为 false，确保截图时对象层完整渲染

        // 配置对象图层 - 作为 overlayContainerView 的子视图
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

    override func layoutSubviews() {
        super.layoutSubviews()
        // 对象图层始终保持画布大小
        objectLayerView.frame = CGRect(origin: .zero, size: canvasSize)
        // 同步覆盖层变换
        syncOverlayTransform()
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
    
    /// 更新画笔设置
    func updatePenSettings(color: UIColor, width: CGFloat) {
        penColor = color
        penLineWidth = width

        // 如果当前是画笔工具，立即更新
        if currentTool == .pen {
            pencilCanvas.tool = PKInkingTool(.pen, color: color, width: width)
        }
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

    /// 移除所有图层（包括图片、箭头、形状）
    func removeAllLayers() {
        // 1. 清空图层数据
        layers.removeAll()

        // 2. 清理图片视图
        imageViews.values.forEach { $0.removeFromSuperview() }
        imageViews.removeAll()

        // 3. 清理箭头视图
        arrowViews.values.forEach { $0.removeFromSuperview() }
        arrowViews.removeAll()

        // 4. 清理形状视图
        shapeViews.values.forEach { $0.removeFromSuperview() }
        shapeViews.removeAll()

        // 5. 清空选中状态
        selectedNodeID = nil

        // 6. 通知更新
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
            
            // 检查是否移动
            if startArrow.startPoint != endArrow.startPoint || startArrow.endPoint != endArrow.endPoint {
                let action = MoveArrowAction(
                    arrowID: startArrow.id,
                    fromArrow: startArrow,
                    toArrow: endArrow,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            // 检查是否缩放
            else if abs(startArrow.scale - endArrow.scale) > 0.01 {
                let action = ScaleArrowAction(
                    arrowID: startArrow.id,
                    fromArrow: startArrow,
                    toArrow: endArrow,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            // 检查是否旋转
            else if abs(startArrow.rotation - endArrow.rotation) > 0.001 {
                let action = RotateArrowAction(
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
        
        // 更新形状视图选中状态
        for (id, shapeView) in shapeViews {
            shapeView.isSelected = (id == selectedNodeID)
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
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.drawingGestureRecognizer.isEnabled = false
            pencilCanvas.drawingPolicy = .default
            pencilCanvas.isScrollEnabled = false
            pencilCanvas.panGestureRecognizer.isEnabled = false
            pencilCanvas.pinchGestureRecognizer?.isEnabled = false

            // 关键：启用覆盖层交互
            overlayContainerView.isUserInteractionEnabled = true
            objectLayerView.isUserInteractionEnabled = true

            // 确保所有对象的手势都能正常工作
            for imageView in imageViews.values {
                imageView.enableObjectGestures()
            }

            // 确保所有箭头的手势都能正常工作
            for arrowView in arrowViews.values {
                arrowView.enableArrowGestures()
            }
            
            // 确保所有形状的手势都能正常工作
            for shapeView in shapeViews.values {
                shapeView.enableShapeGestures()
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

        case .pen:
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.tool = PKInkingTool(.pen, color: penColor, width: penLineWidth)
            pencilCanvas.drawingPolicy = .anyInput
            pencilCanvas.drawingGestureRecognizer.isEnabled = true
            pencilCanvas.isScrollEnabled = false
            pencilCanvas.panGestureRecognizer.isEnabled = false
            pencilCanvas.pinchGestureRecognizer?.isEnabled = false

            // 关键：禁用覆盖层交互
            overlayContainerView.isUserInteractionEnabled = false

        case .eraser:
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.tool = eraserTool
            pencilCanvas.drawingPolicy = .anyInput
            pencilCanvas.drawingGestureRecognizer.isEnabled = true
            pencilCanvas.isScrollEnabled = false
            pencilCanvas.panGestureRecognizer.isEnabled = false
            pencilCanvas.pinchGestureRecognizer?.isEnabled = false

            // 关键：禁用覆盖层交互
            overlayContainerView.isUserInteractionEnabled = false

        case .image:
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.drawingGestureRecognizer.isEnabled = false
            pencilCanvas.drawingPolicy = .default
            pencilCanvas.isScrollEnabled = false
            pencilCanvas.panGestureRecognizer.isEnabled = false
            pencilCanvas.pinchGestureRecognizer?.isEnabled = false

            // 这些工具可能需要与覆盖层交互
            overlayContainerView.isUserInteractionEnabled = true
            objectLayerView.isUserInteractionEnabled = true

        case .arrow, .rectangle, .text, .annotation:
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.drawingGestureRecognizer.isEnabled = false
            pencilCanvas.drawingPolicy = .default
            pencilCanvas.isScrollEnabled = false
            pencilCanvas.panGestureRecognizer.isEnabled = false
            pencilCanvas.pinchGestureRecognizer?.isEnabled = false

            // 这些工具可能需要与覆盖层交互
            overlayContainerView.isUserInteractionEnabled = true
            objectLayerView.isUserInteractionEnabled = true
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
                // 静默处理错误，避免日志输出
            }
        }

        // 同步覆盖层位置
        syncOverlayTransform()

        // 同步更新撤销基准数据
        strokeStartDrawingData = getDrawingData()
    }
    
    /// 仅设置 PKCanvasView 的基本属性（不涉及 objectLayerView）
    private func setupPencilCanvasOnly() {
        pencilCanvas.backgroundColor = .white
        pencilCanvas.isOpaque = true
        pencilCanvas.tool = PKInkingTool(.pen, color: penColor, width: penLineWidth)
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

    /// 设置PKCanvasView的基本属性
    private func setupPencilCanvas() {
        pencilCanvas.backgroundColor = .white
        pencilCanvas.isOpaque = true
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
        print("[Snapshot] ===== Begin captureContentSnapshot =====")
        print("[Snapshot] Input contentRect: \(contentRect)")
        print("[Snapshot] Canvas size: \(canvasSize)")
        print("[Snapshot] objectLayerView.subviews.count: \(objectLayerView.subviews.count)")
        
        // 扩大边界容差（从+-10扩大到+-100）
        let expandedCanvas = CGRect(
            x: -100,
            y: -100,
            width: canvasSize.width + 200,
            height: canvasSize.height + 200
        )
        let bounded = contentRect.intersection(expandedCanvas)
        
        print("[Snapshot] Expanded canvas bounds: \(expandedCanvas)")
        print("[Snapshot] Bounded rect (intersection): \(bounded)")
        
        // 放宽最小尺寸检查（从1pt放宽到10pt）
        guard !bounded.isNull, bounded.width >= 10, bounded.height >= 10 else {
            print("[Snapshot] Error: Invalid or too small rect")
            print("[Snapshot] bounded.isNull: \(bounded.isNull)")
            if !bounded.isNull {
                print("[Snapshot] bounded size: \(bounded.width) x \(bounded.height)")
            }
            return nil
        }

        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        
        print("[Snapshot] Rendering with scale: \(scale)")
        print("[Snapshot] Final render size: \(bounded.size)")

        // PencilKit 导出
        let drawingImage = pencilCanvas.drawing.image(from: bounded, scale: scale)
        print("[Snapshot] Drawing image size: \(drawingImage.size)")

        // 对象层渲染
        let renderer = UIGraphicsImageRenderer(size: bounded.size, format: format)
        let result = renderer.image { rendererContext in
            let ctx = rendererContext.cgContext
            
            // 白色背景（确保可见性）
            ctx.setFillColor(UIColor.white.cgColor)
            ctx.fill(CGRect(origin: .zero, size: bounded.size))
            
            ctx.saveGState()
            ctx.translateBy(x: -bounded.origin.x, y: -bounded.origin.y)
            
            // 渲染对象层
            print("[Snapshot] Rendering objectLayerView at origin: \(-bounded.origin.x), \(-bounded.origin.y)")
            objectLayerView.layer.render(in: ctx)
            
            ctx.restoreGState()
            
            // 渲染 PencilKit 笔画
            drawingImage.draw(in: CGRect(origin: .zero, size: bounded.size))
        }
        
        print("[Snapshot] ===== End captureContentSnapshot (success) =====")
        print("[Snapshot] Result image size: \(result.size)")
        return result
    }

    /// 将视口坐标映射到画布内容坐标
    func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
        print("[Coordinate] ===== Begin contentRect conversion =====")
        print("[Coordinate] Input viewportRect: \(viewportRect)")
        
        // 从视口坐标转换到Canvas坐标
        let rectInCanvas = pencilCanvas.convert(viewportRect, from: self)
        print("[Coordinate] After convert (rectInCanvas): \(rectInCanvas)")
        
        // 获取缩放和偏移
        let scale = pencilCanvas.zoomScale
        let offset = pencilCanvas.contentOffset
        print("[Coordinate] zoomScale: \(scale), contentOffset: \(offset)")
        
        // 应用缩放和偏移
        let result = CGRect(
            x: (rectInCanvas.origin.x + offset.x) / scale,
            y: (rectInCanvas.origin.y + offset.y) / scale,
            width: rectInCanvas.width / scale,
            height: rectInCanvas.height / scale
        )
        
        print("[Coordinate] Result contentRect: \(result)")
        print("[Coordinate] ===== End contentRect conversion =====")
        return result
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

    /// 直接截取视口区域的快照（简化版）
    func captureViewportSnapshotSimple(rect viewportRect: CGRect) -> UIImage? {
        print("[Snapshot-Simple] ===== Begin =====")
        print("[Snapshot-Simple] viewportRect: \(viewportRect)")

        guard viewportRect.width >= 10, viewportRect.height >= 10 else {
            print("[Snapshot-Simple] Error: rect too small")
            return nil
        }

        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: viewportRect.size, format: format)

        let result = renderer.image { context in
            context.cgContext.translateBy(x: -viewportRect.origin.x, y: -viewportRect.origin.y)

            pencilCanvas.layer.render(in: context.cgContext)

            overlayContainerView.layer.render(in: context.cgContext)
        }

        print("[Snapshot-Simple] Result size: \(result.size)")
        print("[Snapshot-Simple] ===== End =====")
        return result
    }

    /// 截取指定视口区域的快照（推荐使用）
    /// - Parameter viewportRect: 视口坐标（相对于 NativeCanvasView）
    /// - Returns: 截取的图片，失败返回 nil
    func captureVisibleAreaSnapshot(viewportRect: CGRect) -> UIImage? {
        print("[Snapshot] ===== Begin captureVisibleAreaSnapshot =====")
        print("[Snapshot] Input viewportRect: \(viewportRect)")
        print("[Snapshot] NativeCanvasView bounds: \(bounds)")
        print("[Snapshot] pencilCanvas.bounds: \(pencilCanvas.bounds)")
        print("[Snapshot] pencilCanvas.contentOffset: \(pencilCanvas.contentOffset)")
        print("[Snapshot] pencilCanvas.zoomScale: \(pencilCanvas.zoomScale)")
        print("[Snapshot] objectLayerView.frame: \(objectLayerView.frame)")
        print("[Snapshot] objectLayerView.transform: \(objectLayerView.transform)")

        // 验证尺寸
        guard viewportRect.width >= 10, viewportRect.height >= 10 else {
            print("[Snapshot] Error: viewportRect too small (< 10pt)")
            return nil
        }

        // 确保区域在视图范围内
        let clippedRect = viewportRect.intersection(bounds)
        guard !clippedRect.isEmpty else {
            print("[Snapshot] Error: viewportRect does not intersect bounds")
            return nil
        }

        print("[Snapshot] Clipped rect: \(clippedRect)")

        // 确保布局完成
        layoutIfNeeded()
        syncOverlayTransform()

        // 配置渲染器
        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: clippedRect.size, format: format)

        let result = renderer.image { context in
            let ctx = context.cgContext

            // 平移坐标系：使 clippedRect 的左上角对应图片的 (0, 0)
            ctx.translateBy(x: -clippedRect.origin.x, y: -clippedRect.origin.y)

            // 渲染整个视图层级
            // 这会自动包含 pencilCanvas 和 overlayContainerView 及其所有子视图
            self.layer.render(in: ctx)
        }

        print("[Snapshot] Result image size: \(result.size)")
        print("[Snapshot] Result image scale: \(result.scale)")
        print("[Snapshot] ===== End captureVisibleAreaSnapshot (success) =====")

        return result
    }

    /// 备用方法：截取整个可见区域后裁剪
    /// - Parameter cropRect: 裁剪区域（相对于 NativeCanvasView）
    /// - Returns: 裁剪后的图片
    func captureAndCropSnapshot(cropRect: CGRect) -> UIImage? {
        print("[Snapshot-Crop] ===== Begin =====")
        print("[Snapshot-Crop] cropRect: \(cropRect)")

        // 验证
        guard cropRect.width >= 10, cropRect.height >= 10 else {
            print("[Snapshot-Crop] Error: cropRect too small")
            return nil
        }

        let fullSize = bounds.size
        guard fullSize.width > 0, fullSize.height > 0 else {
            print("[Snapshot-Crop] Error: bounds is empty")
            return nil
        }

        // 确保布局完成
        layoutIfNeeded()
        syncOverlayTransform()

        // 配置渲染器
        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        // 第一步：截取整个可见区域
        let renderer = UIGraphicsImageRenderer(size: fullSize, format: format)
        let fullImage = renderer.image { context in
            self.layer.render(in: context.cgContext)
        }

        print("[Snapshot-Crop] Full image captured: \(fullImage.size)")

        // 第二步：裁剪
        // 注意：CGImage 使用像素坐标，需要乘以 scale
        let pixelCropRect = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )

        guard let cgImage = fullImage.cgImage,
              let croppedCGImage = cgImage.cropping(to: pixelCropRect) else {
            print("[Snapshot-Crop] Error: Failed to crop")
            return nil
        }

        let croppedImage = UIImage(cgImage: croppedCGImage, scale: scale, orientation: .up)
        print("[Snapshot-Crop] Cropped image: \(croppedImage.size)")
        print("[Snapshot-Crop] ===== End =====")

        return croppedImage
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
        if let arrowView = arrowViews[arrow.id] {
            arrowView.arrowNode = arrow
        }
        onCanvasUpdated?()
    }

    func clearArrows() {
        arrowLayerManager.clearAll()
        onCanvasUpdated?()
    }

    // MARK: - 形状管理

    func getShapeLayerManager() -> ShapeLayerManager { shapeLayerManager }

    func addShape(_ shape: ShapeLayerNode, recordUndo: Bool = true) {
        if recordUndo {
            let action = AddShapeAction(shape: shape, canvasView: self)
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
        shapeLayerManager.addShape(shape)
        createShapeView(for: shape)
        onCanvasUpdated?()
    }

    func removeShape(id: UUID) {
        shapeLayerManager.removeShape(id: id)
        if let shapeView = shapeViews[id] {
            shapeView.removeFromSuperview()
            shapeViews.removeValue(forKey: id)
        }
        onCanvasUpdated?()
    }

    func updateShape(_ shape: ShapeLayerNode) {
        shapeLayerManager.updateShape(shape)
        if let shapeView = shapeViews[shape.id] {
            shapeView.shapeNode = shape
        }
        onCanvasUpdated?()
    }

    func clearShapes() {
        shapeLayerManager.clearAll()
        shapeViews.values.forEach { $0.removeFromSuperview() }
        shapeViews.removeAll()
        onCanvasUpdated?()
    }

    /// 创建形状视图
    private func createShapeView(for shape: ShapeLayerNode) {
        let shapeView = SelectableShapeView(shapeNode: shape)
        
        // 设置选中回调
        shapeView.onSelected = { [weak self] id in
            self?.selectedNodeID = id
        }
        
        // 设置节点更新回调
        shapeView.onNodeUpdated = { [weak self] updatedShape in
            self?.shapeLayerManager.updateShape(updatedShape)
        }
        
        // 设置操作回调（用于撤销）
        var operationStartShape: ShapeLayerNode?
        shapeView.onOperationStart = { shape in
            operationStartShape = shape
        }
        
        shapeView.onOperationEnd = { [weak self] _, endShape in
            guard let self = self, let startShape = operationStartShape else { return }
            
            // 检查是否移动
            if startShape.frame != endShape.frame {
                let action = MoveShapeAction(
                    shapeID: startShape.id,
                    fromShape: startShape,
                    toShape: endShape,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            // 检查是否缩放
            else if abs(startShape.frame.width - endShape.frame.width) > 1 || 
                    abs(startShape.frame.height - endShape.frame.height) > 1 {
                let action = ScaleShapeAction(
                    shapeID: startShape.id,
                    fromShape: startShape,
                    toShape: endShape,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            // 检查是否旋转
            else if abs(startShape.rotation - endShape.rotation) > 0.001 {
                let action = RotateShapeAction(
                    shapeID: startShape.id,
                    fromShape: startShape,
                    toShape: endShape,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            
            operationStartShape = nil
        }
        
        shapeViews[shape.id] = shapeView
        objectLayerView.addSubview(shapeView)
        
        // 根据当前工具状态设置手势
        if currentTool == .select {
            shapeView.enableShapeGestures()
        }
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

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 同步覆盖层的位置
        syncOverlayTransform()
    }

    // PKCanvasViewDelegate 继承自 UIScrollViewDelegate，所以可以监听缩放
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // 同步覆盖层的缩放
        syncOverlayTransform()

        // 回调缩放变化
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
