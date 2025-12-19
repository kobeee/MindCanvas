import SwiftUI
import UIKit
import PencilKit

/// 自定义手势识别器，用于追踪完整生命周期
class DebugTapGestureRecognizer: UITapGestureRecognizer {
    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
    }
    
    override func reset() {
        super.reset()
    }
}

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
    
    /// 文字视图字典 (nodeID -> SelectableTextView)
    var textViews: [UUID: SelectableTextView] = [:]
    
    /// 形状图层管理器
    private let shapeLayerManager = ShapeLayerManager()

    /// 矩形图层管理器
    private let rectangleLayerManager = RectangleLayerManager()

    /// 标注图层管理器
    private let annotationLayerManager = AnnotationLayerManager()
    
    /// 文字图层管理器
    private let textLayerManager = TextLayerManager()

    /// 空白区域点击手势识别器
    private lazy var canvasTapGesture: DebugTapGestureRecognizer = {
        let tap = DebugTapGestureRecognizer(target: self, action: #selector(handleCanvasTap(_:)))
        tap.delegate = self
        
        return tap
    }()
    
    /// 全局点击监听器（用于监听画布外的点击）
    private var globalTapObserver: NSObjectProtocol?

    /// 当前选中的节点 ID
    private var selectedNodeID: UUID? {
        didSet {
            updateSelectionStates()
            
            // 修复：同步选中状态到CanvasStateManager
            onSelectionIdChanged?(selectedNodeID)
        }
    }

    // MARK: - 回调闭包

    /// 画布更新回调
    var onCanvasUpdated: (() -> Void)?

    /// 选区变化回调
    var onSelectionChanged: ((Bool) -> Void)?
    
    /// 选中ID变化回调（用于同步到CanvasStateManager）
    var onSelectionIdChanged: ((UUID?) -> Void)?

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

        // 添加空白区域点击手势识别器
        addGestureRecognizer(canvasTapGesture)
        
        // 设置全局点击监听器
        setupGlobalTapObserver()
        
        // 设置选中状态同步监听器
        setupSelectionSyncObserver()

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

    /// 移除所有图层（包括图片、箭头、形状、文字）
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
        
        // 5. 清理文字视图
        textViews.values.forEach { $0.removeFromSuperview() }
        textViews.removeAll()
        textLayerManager.clearAll()

        // 6. 清空选中状态
        selectedNodeID = nil

        // 7. 通知更新
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
        let arrowView = SelectableArrowView(arrowNode: arrow)
        
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
    }

    /// 更新选中状态
    private func updateSelectionStates() {
        // 更新图片视图选中状态
        for (id, imageView) in imageViews {
            let shouldBeSelected = (id == selectedNodeID)
            imageView.isSelected = shouldBeSelected
        }
        
        // 更新箭头视图选中状态
        for (id, arrowView) in arrowViews {
            let shouldBeSelected = (id == selectedNodeID)
            arrowView.isSelected = shouldBeSelected
        }
        
        // 更新形状视图选中状态
        for (id, shapeView) in shapeViews {
            let shouldBeSelected = (id == selectedNodeID)
            shapeView.isSelected = shouldBeSelected
        }
        
        // 更新文字视图选中状态
        for (id, textView) in textViews {
            let shouldBeSelected = (id == selectedNodeID)
            textView.isSelected = shouldBeSelected
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

    // MARK: - 获取所有图形对象（用于清屏撤销）

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
        return textLayerManager.getAllTexts()
    }

    /// 获取所有标注对象
    func getAnnotations() -> [AnnotationLayerNode] {
        return annotationLayerManager.annotations
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

    // MARK: - Gesture Handling

    /// 处理画布点击事件（用于空白区域取消选中或创建文字）
    @objc private func handleCanvasTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: objectLayerView)
        
        // 检查点击是否在任何对象上
        let hitView = objectLayerView.hitTest(location, with: nil)
        
        // 如果是文字工具且点击在空白区域，创建新文字
        if currentTool == .text && (hitView == objectLayerView || !isSelectableObject(hitView)) {
            createTextAtLocation(location)
            return
        }
        
        // 如果点击的是objectLayerView本身（空白区域）或其直接子视图不是可选对象，取消选中
        if hitView == objectLayerView || (!isSelectableObject(hitView)) {
            selectedNodeID = nil
        }
    }
    
    /// 在指定位置创建文字
    private func createTextAtLocation(_ location: CGPoint) {
        // 将点击位置转换为画布内容坐标
        let contentLocation = convertToContentCoordinates(location)
        
        // 创建默认文字
        let text = TextLayerNode(
            position: contentLocation,
            text: "新文字",
            fontSize: 24,
            color: "#000000",
            fontName: ".SF Pro Display",
            rotation: 0,
            scale: 1.0,
            zIndex: textLayerManager.getNextZIndex()
        )
        
        // 添加文字
        addText(text)
        
        // 自动选中新创建的文字
        selectedNodeID = text.id
        
        print("✏️ [NativeCanvasView] 创建文字: \(text.id) at \(contentLocation)")
    }
    
    /// 将视图坐标转换为画布内容坐标
    private func convertToContentCoordinates(_ viewLocation: CGPoint) -> CGPoint {
        let scale = pencilCanvas.zoomScale
        let offset = pencilCanvas.contentOffset
        
        return CGPoint(
            x: (viewLocation.x + offset.x) / scale,
            y: (viewLocation.y + offset.y) / scale
        )
    }
    
    /// 检查视图是否为可选择对象
    private func isSelectableObject(_ view: UIView?) -> Bool {
        guard let view = view else { return false }
        
        return view is ResizableImageView ||
               view is SelectableArrowView ||
               view is SelectableShapeView ||
               view is SelectableTextView
    }

    // MARK: - Tool Management

    /// 根据工具更新手势处理
    func updateForTool(_ tool: CanvasTool) {
        print("🔧 [NativeCanvasView] updateForTool: \(tool.displayName) (\(tool.rawValue))")
        
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
            
            // 启用空白区域点击手势识别器
            canvasTapGesture.isEnabled = true

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
            
            // 确保所有文字的手势都能正常工作
            for textView in textViews.values {
                textView.enableTextGestures()
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
            
            // 启用空白区域点击手势识别器（在所有工具模式下都可用）
            canvasTapGesture.isEnabled = true

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
            
            // 启用空白区域点击手势识别器（在所有工具模式下都可用）
            canvasTapGesture.isEnabled = true

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
            
            // 启用空白区域点击手势识别器（在所有工具模式下都可用）
            canvasTapGesture.isEnabled = true

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
            
            // 启用空白区域点击手势识别器（在所有工具模式下都可用）
            canvasTapGesture.isEnabled = true

        case .arrow, .rectangle, .text, .annotation:
            print("🔧 [NativeCanvasView] 处理工具: \(tool.displayName)")
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.drawingGestureRecognizer.isEnabled = false
            pencilCanvas.drawingPolicy = .default
            pencilCanvas.isScrollEnabled = false
            pencilCanvas.panGestureRecognizer.isEnabled = false
            pencilCanvas.pinchGestureRecognizer?.isEnabled = false

            // 这些工具可能需要与覆盖层交互
            overlayContainerView.isUserInteractionEnabled = true
            
            // 启用空白区域点击手势识别器（在所有工具模式下都可用）
            canvasTapGesture.isEnabled = true
            objectLayerView.isUserInteractionEnabled = true
            
            // 特殊处理文字工具
            if tool == .text {
                print("🔧 [NativeCanvasView] 文字工具已激活，等待用户点击画布创建文字")
                // 确保所有文字的手势都能正常工作
                for textView in textViews.values {
                    textView.enableTextGestures()
                }
            }
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
        
        // 扩大边界容差（从+-10扩大到+-100）
        let expandedCanvas = CGRect(
            x: -100,
            y: -100,
            width: canvasSize.width + 200,
            height: canvasSize.height + 200
        )
        let bounded = contentRect.intersection(expandedCanvas)
        
        
        // 放宽最小尺寸检查（从1pt放宽到10pt）
        guard !bounded.isNull, bounded.width >= 10, bounded.height >= 10 else {
            if !bounded.isNull {
            }
            return nil
        }

        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        

        // PencilKit 导出
        let drawingImage = pencilCanvas.drawing.image(from: bounded, scale: scale)

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
            objectLayerView.layer.render(in: ctx)
            
            ctx.restoreGState()
            
            // 渲染 PencilKit 笔画
            drawingImage.draw(in: CGRect(origin: .zero, size: bounded.size))
        }
        
        return result
    }

    /// 将视口坐标映射到画布内容坐标
    func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
        
        // 从视口坐标转换到Canvas坐标
        let rectInCanvas = pencilCanvas.convert(viewportRect, from: self)
        
        // 获取缩放和偏移
        let scale = pencilCanvas.zoomScale
        let offset = pencilCanvas.contentOffset
        
        // 应用缩放和偏移
        let result = CGRect(
            x: (rectInCanvas.origin.x + offset.x) / scale,
            y: (rectInCanvas.origin.y + offset.y) / scale,
            width: rectInCanvas.width / scale,
            height: rectInCanvas.height / scale
        )
        
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

        guard viewportRect.width >= 10, viewportRect.height >= 10 else {
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

        return result
    }

    /// 截取指定视口区域的快照（推荐使用）
    /// - Parameter viewportRect: 视口坐标（相对于 NativeCanvasView）
    /// - Returns: 截取的图片，失败返回 nil
    func captureVisibleAreaSnapshot(viewportRect: CGRect) -> UIImage? {

        // 验证尺寸
        guard viewportRect.width >= 10, viewportRect.height >= 10 else {
            return nil
        }

        // 确保区域在视图范围内
        let clippedRect = viewportRect.intersection(bounds)
        guard !clippedRect.isEmpty else {
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

        let renderer = UIGraphicsImageRenderer(size: clippedRect.size, format: format)

        let result = renderer.image { context in
            let ctx = context.cgContext

            // 平移坐标系：使 clippedRect 的左上角对应图片的 (0, 0)
            ctx.translateBy(x: -clippedRect.origin.x, y: -clippedRect.origin.y)

            // 渲染整个视图层级
            // 这会自动包含 pencilCanvas 和 overlayContainerView 及其所有子视图
            self.layer.render(in: ctx)
        }


        return result
    }

    /// 备用方法：截取整个可见区域后裁剪
    /// - Parameter cropRect: 裁剪区域（相对于 NativeCanvasView）
    /// - Returns: 裁剪后的图片
    func captureAndCropSnapshot(cropRect: CGRect) -> UIImage? {

        // 验证
        guard cropRect.width >= 10, cropRect.height >= 10 else {
            return nil
        }

        let fullSize = bounds.size
        guard fullSize.width > 0, fullSize.height > 0 else {
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
            return nil
        }

        let croppedImage = UIImage(cgImage: croppedCGImage, scale: scale, orientation: .up)

        return croppedImage
    }

    // MARK: - 箭头管理

    func getArrowLayerManager() -> ArrowLayerManager { arrowLayerManager }

    func addArrow(_ arrow: ArrowLayerNode, recordUndo: Bool = true) {
        if recordUndo {
            let action = AddArrowAction(arrow: arrow, canvasView: self)
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
        arrowLayerManager.addArrow(arrow)
        createArrowView(for: arrow)
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

    /// 检查是否存在指定ID的箭头
    func hasArrow(id: UUID) -> Bool {
        return arrowViews[id] != nil
    }

    /// 检查是否存在指定ID的形状
    func hasShape(id: UUID) -> Bool {
        return shapeViews[id] != nil
    }

    func updateShape(_ shape: ShapeLayerNode) {
        shapeLayerManager.updateShape(shape)
        if let shapeView = shapeViews[shape.id] {
            shapeView.shapeNode = shape
            // 显式调用 updateFromNode() 确保视图同步
            shapeView.updateFromNode()
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
    
    // MARK: - 文字管理
    
    func getTextLayerManager() -> TextLayerManager { textLayerManager }

    func addText(_ text: TextLayerNode, recordUndo: Bool = true) {
        if recordUndo {
            let action = AddTextAction(text: text, canvasView: self)
            NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
        }
        textLayerManager.addText(text)
        createTextView(for: text)
        onTextCreated?(text)
        onCanvasUpdated?()
    }

    func removeText(id: UUID) {
        guard let text = textLayerManager.getText(id: id) else { return }
        textLayerManager.removeText(id: id)
        textViews[id]?.removeFromSuperview()
        textViews.removeValue(forKey: id)
        onCanvasUpdated?()
    }

    func updateText(_ text: TextLayerNode) {
        textLayerManager.updateText(text)
        if let textView = textViews[text.id] {
            textView.textNode = text
        }
        onCanvasUpdated?()
    }

    func clearTexts() {
        textLayerManager.clearAll()
        textViews.values.forEach { $0.removeFromSuperview() }
        textViews.removeAll()
        onCanvasUpdated?()
    }
    
    /// 检查是否存在指定ID的文字
    func hasText(id: UUID) -> Bool {
        return textViews[id] != nil
    }
    
    /// 创建文字视图
    private func createTextView(for text: TextLayerNode) {
        let textView = SelectableTextView(textNode: text)
        
        var operationStartText: TextLayerNode?
        
        // 设置选中回调
        textView.onSelected = { [weak self] id in
            self?.selectedNodeID = id
        }
        
        // 设置节点更新回调
        textView.onNodeUpdated = { [weak self] updatedText in
            self?.textLayerManager.updateText(updatedText)
        }
        
        // 设置操作回调（用于撤销）
        textView.onOperationStart = { text in
            operationStartText = text
        }
        
        textView.onOperationEnd = { [weak self] _, endText in
            guard let self = self, let startText = operationStartText else { return }
            
            // 检查是否移动
            if startText.position != endText.position {
                let action = MoveTextAction(
                    textID: startText.id,
                    fromText: startText,
                    toText: endText,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            // 检查是否缩放
            else if abs(startText.scale - endText.scale) > 0.01 {
                let action = ScaleTextAction(
                    textID: startText.id,
                    fromText: startText,
                    toText: endText,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            // 检查是否旋转
            else if abs(startText.rotation - endText.rotation) > 0.001 {
                let action = RotateTextAction(
                    textID: startText.id,
                    fromText: startText,
                    toText: endText,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            // 检查是否修改了文字内容
            else if startText.text != endText.text {
                let action = ModifyTextAction(
                    textID: startText.id,
                    fromText: startText,
                    toText: endText,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            
            operationStartText = nil
        }
        
        // 设置编辑回调
        textView.onEditingStarted = { [weak self] startText in
            print("🔧 [NativeCanvasView] 文字编辑开始: \(startText.text)")
            // 编辑开始时可以选择性地禁用全局手势
        }
        
        textView.onEditingFinished = { [weak self] updatedText, newText in
            guard let self = self else { return }
            print("🔧 [NativeCanvasView] 文字编辑完成: '\(newText)'")
            
            // 更新文字节点
            self.textLayerManager.updateText(updatedText)
            
            // 记录撤销操作
            if let startText = operationStartText, startText.text != updatedText.text {
                let action = ModifyTextAction(
                    textID: startText.id,
                    fromText: startText,
                    toText: updatedText,
                    canvasView: self
                )
                NotificationCenter.default.post(name: .canvasActionRecorded, object: action)
            }
            
            operationStartText = nil
            self.onCanvasUpdated?()
        }
        
        textViews[text.id] = textView
        objectLayerView.addSubview(textView)
        
        // 根据当前工具状态设置手势
        if currentTool == .select || currentTool == .text {
            textView.enableTextGestures()
        }
        
        // 关键修复：强制立即布局，确保视图可见
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        objectLayerView.setNeedsLayout()
        objectLayerView.layoutIfNeeded()
    }
    
    /// 清理资源
    deinit {
        cleanupGlobalTapObserver()
        cleanupSelectionSyncObserver()
    }
    
    /// 清理选中状态同步监听器
    private func cleanupSelectionSyncObserver() {
        NotificationCenter.default.removeObserver(self, name: .selectionChangedInStateManager, object: nil)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension NativeCanvasView: UIGestureRecognizerDelegate {
    /// 处理手势识别器是否应该接收触摸事件
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        
        // 只处理空白点击手势的冲突
        guard gestureRecognizer == canvasTapGesture else {
            return true
        }
        
        let location = touch.location(in: objectLayerView)
        let hitView = objectLayerView.hitTest(location, with: nil)
        
        
        // 如果点击在可选择对象上，不让空白点击手势处理
        if isSelectableObject(hitView) {
            return false
        }
        
        return true
    }
    
    /// 处理手势识别器是否应该开始识别
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        
        if gestureRecognizer == canvasTapGesture {
        }
        
        return true
    }
    
    /// 处理手势识别器之间的同时识别
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        
        // 空白点击手势不与其他手势同时识别
        if gestureRecognizer == canvasTapGesture || otherGestureRecognizer == canvasTapGesture {
            return false
        }
        
        return true
    }
    
    /// 处理手势识别器是否应该接收按压事件
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive press: UIPress) -> Bool {
        return true
    }
    
    /// 处理手势识别器是否需要失败才能开始
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        
        if gestureRecognizer == canvasTapGesture {
        }
        
        return false
    }
    
    /// 处理手势识别器是否需要其他手势失败
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        
        if gestureRecognizer == canvasTapGesture {
        }
        
        return false
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

// MARK: - Global Tap Observer Extension

extension NativeCanvasView {
    
    /// 设置选中状态同步监听器
    private func setupSelectionSyncObserver() {
        
        NotificationCenter.default.addObserver(
            forName: .selectionChangedInStateManager,
            object: nil,
            queue: .main,
            using: { [weak self] notification in
                self?.handleSelectionChangedInStateManager(notification)
            }
        )
        
    }
    
    /// 处理CanvasStateManager中选中状态变化的通知
    @objc private func handleSelectionChangedInStateManager(_ notification: Notification) {
        guard let newSelectedID = notification.object as? UUID? else {
            return
        }
        
        
        // 同步选中状态到NativeCanvasView
        if selectedNodeID != newSelectedID {
            selectedNodeID = newSelectedID
        } else {
        }
    }
    
    /// 设置全局点击监听器
    private func setupGlobalTapObserver() {
        
        // 使用UITapGestureRecognizer监听整个窗口的点击
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let window = self.findWindow() else {
                return
            }
            
            
            // 检查是否已经有全局手势
            if let existingGesture = objc_getAssociatedObject(window, &AssociatedKeys.globalTapGesture) as? UITapGestureRecognizer {
                return
            }
            
            let globalTapGesture = UITapGestureRecognizer(target: self, action: #selector(self.handleGlobalTap(_:)))
            globalTapGesture.cancelsTouchesInView = false  // 不阻止其他手势
            globalTapGesture.delegate = self
            
            window.addGestureRecognizer(globalTapGesture)
            
            // 保存全局手势引用
            objc_setAssociatedObject(window, &AssociatedKeys.globalTapGesture, globalTapGesture, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
        }
    }
    
    /// 查找当前窗口
    private func findWindow() -> UIWindow? {
        // 优先使用自己的窗口
        if let window = self.window {
            return window
        }
        
        // 使用父视图的窗口
        if let parentWindow = self.superview?.window {
            return parentWindow
        }
        
        // 使用应用的第一个窗口
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            return window
        }
        
        // 备选方案：遍历所有窗口
        for window in UIApplication.shared.windows {
            if window.isKeyWindow {
                return window
            }
        }
        
        return UIApplication.shared.windows.first
    }
    
    /// 处理全局点击事件
    @objc private func handleGlobalTap(_ gesture: UITapGestureRecognizer) {
        
        // 如果没有选中对象，不需要处理
        guard selectedNodeID != nil else {
            return
        }
        
        guard let gestureView = gesture.view else {
            return
        }
        
        let location = gesture.location(in: gestureView)
        
        // 检查点击是否在当前画布视图内
        let locationInCanvas = gesture.location(in: self)
        let isTapInCanvas = bounds.contains(locationInCanvas)
        
        
        if isTapInCanvas {
            // 在画布内的点击，让画布自己的手势处理
            return
        }
        
        // 获取点击的视图层级信息
        let hitView = gestureView.hitTest(location, with: nil)
        
        // 检查点击的是否是工具栏或其他UI控件
        if isUIControl(hitView) {
        } else {
        }
        
        // 在画布外的点击，直接取消选中
        selectedNodeID = nil
    }
    
    /// 检查视图是否是UI控件（工具栏、按钮等）
    private func isUIControl(_ view: UIView?) -> Bool {
        guard let view = view else { return false }
        
        // 检查是否是常见的UI控件类型
        if view is UIButton || 
           view is UIToolbar || 
           view is UINavigationBar || 
           view is UITabBar ||
           view is UISlider ||
           view is UISwitch ||
           view is UIStepper ||
           view is UISegmentedControl {
            return true
        }
        
        // 检查视图类名是否包含常见的UI控件标识
        let className = String(describing: type(of: view))
        let uiControlKeywords = [
            "Button", "Toolbar", "Bar", "Control", "Slider", "Switch", "Stepper",
            "SegmentedControl", "TextField", "TextView", "Label", "ImageView",
            "CanvasToolbar", "ToolButton", "ShapeToolButton", "PenToolButton"
        ]
        
        for keyword in uiControlKeywords {
            if className.contains(keyword) {
                return true
            }
        }
        
        // 检查背景视图类型（通常表示UI容器）
        if className.contains("Background") || className.contains("Container") {
            return true
        }
        
        return false
    }
    
    /// 清理全局监听器
    private func cleanupGlobalTapObserver() {
        if let observer = globalTapObserver {
            NotificationCenter.default.removeObserver(observer)
            globalTapObserver = nil
        }
        
        // 清理全局手势
        if let window = self.window ?? self.superview?.window ?? UIApplication.shared.windows.first,
           let globalGesture = objc_getAssociatedObject(window, &AssociatedKeys.globalTapGesture) as? UITapGestureRecognizer {
            window.removeGestureRecognizer(globalGesture)
            objc_setAssociatedObject(window, &AssociatedKeys.globalTapGesture, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// MARK: - Associated Keys
private struct AssociatedKeys {
    static var globalTapGesture = "globalTapGesture"
}
