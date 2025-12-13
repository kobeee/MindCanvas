import SwiftUI
import UIKit
import PencilKit

/// 原生画布视图 (UIKit 实现)
/// 承载所有图层的根容器
class NativeCanvasView: UIView {
    // MARK: - Properties
    
    /// Layer 0: 滚动容器
    private let scrollView = UIScrollView()
    
    /// 画布内容视图 (包含所有可见元素)
    private let contentView = UIView()
    
    /// Layer 1: 对象图层容器 (图片节点)
    private let objectLayerView = UIView()
    
    /// Layer 2: PencilKit 绘图层
    private let pencilCanvas = PKCanvasView()
    
    /// 画布尺寸 (超大虚拟画布)
    private let canvasSize = CGSize(width: 5000, height: 5000)
    
    /// 缩放范围
    private let minZoomScale: CGFloat = 0.5
    private let maxZoomScale: CGFloat = 3.0
    
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
            // 兼容层：将旧模式映射到新工具
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
    private var imageViews: [UUID: ResizableImageView] = [:]
    
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

    /// 绘制中标记（用于避免 PencilKit 渲染期间触发布局更新造成闪烁）
    private(set) var isDrawing = false
    
    // MARK: - 箭头绘制
    
    /// 箭头绘制回调
    var onArrowCreated: ((ArrowLayerNode) -> Void)?
    
    /// 矩形绘制回调
    var onRectangleCreated: ((RectangleLayerNode) -> Void)?
    
    /// 文字创建回调
    var onTextCreated: ((TextLayerNode) -> Void)?
    
    /// 标注创建回调
    var onAnnotationCreated: ((AnnotationLayerNode) -> Void)?

    // MARK: - Indirect input / drawing freeze

    private var storedPanEnabled: Bool = true
    private var storedPinchEnabled: Bool = true
    private var storedScrollEnabled: Bool = true
    private var storedBounces: Bool = true
    private var storedBouncesZoom: Bool = true
    private var storedScrollViewInteraction: Bool = true
    private var storedContentOffset: CGPoint = .zero
    private var storedZoomScale: CGFloat = 1.0
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
        setupConstraints()
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        backgroundColor = .systemGray6
        
        // 配置 ScrollView
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        scrollView.minimumZoomScale = minZoomScale
        scrollView.maximumZoomScale = maxZoomScale
        scrollView.contentSize = canvasSize
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bounces = true
        scrollView.bouncesZoom = true

        // 显式允许 Indirect 输入（Simulator 触控板 / 鼠标滚轮）
        if #available(iOS 13.4, *) {
            scrollView.panGestureRecognizer.allowedScrollTypesMask = [.continuous, .discrete]
        }
        if let pinch = scrollView.pinchGestureRecognizer {
            var types: [NSNumber] = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            if #available(iOS 13.4, *) {
                types.append(NSNumber(value: UITouch.TouchType.indirect.rawValue))
                types.append(NSNumber(value: UITouch.TouchType.indirectPointer.rawValue))
            }
            pinch.allowedTouchTypes = types
        }
        
        // 配置内容视图
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = 8
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOpacity = 0.1
        contentView.layer.shadowRadius = 10
        contentView.layer.shadowOffset = CGSize(width: 0, height: 2)
        
        // 配置对象图层
        objectLayerView.backgroundColor = .clear
        objectLayerView.isUserInteractionEnabled = true
        
        // 配置 PencilKit 画布
        pencilCanvas.backgroundColor = .clear
        pencilCanvas.isOpaque = false
        pencilCanvas.tool = inkingTool
        pencilCanvas.delegate = self
        
        // 关键：禁用 PKCanvasView 自身的滚动行为
        pencilCanvas.isScrollEnabled = false
        pencilCanvas.minimumZoomScale = 1.0
        pencilCanvas.maximumZoomScale = 1.0
        pencilCanvas.bouncesZoom = false
        pencilCanvas.bounces = false
        pencilCanvas.alwaysBounceVertical = false
        pencilCanvas.alwaysBounceHorizontal = false
        pencilCanvas.showsVerticalScrollIndicator = false
        pencilCanvas.showsHorizontalScrollIndicator = false
        
        // 图层堆叠
        contentView.addSubview(objectLayerView)
        contentView.addSubview(pencilCanvas)
        scrollView.addSubview(contentView)
        addSubview(scrollView)
        
        // 初始化画布居中
        DispatchQueue.main.async { [weak self] in
            self?.centerCanvas()
            self?.updateForTool(self?.currentTool ?? .select)
            if let zoomScale = self?.scrollView.zoomScale {
                self?.onZoomChanged?(zoomScale)
            }
        }
    }
    
    private func setupConstraints() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    private func setupGestures() {
        // 对象图层的手势识别器将在添加图片节点时配置
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // 绘制过程中不修改任何 frame，避免坐标系变化导致笔画漂移
        guard !isDrawing else { return }
        
        // 设置内容视图和图层尺寸
        contentView.frame = CGRect(origin: .zero, size: canvasSize)
        objectLayerView.frame = contentView.bounds
        pencilCanvas.frame = contentView.bounds
    }
    
    // MARK: - Canvas Control
    
    /// 居中画布
    private func centerCanvas() {
        let xOffset = max(0, (canvasSize.width - scrollView.bounds.width) / 2)
        let yOffset = max(0, (canvasSize.height - scrollView.bounds.height) / 2)
        scrollView.setContentOffset(CGPoint(x: xOffset, y: yOffset), animated: false)
    }
    
    /// 重置缩放
    func resetZoom() {
        scrollView.setZoomScale(1.0, animated: true)
    }

    /// 当前缩放比例
    var zoomScale: CGFloat {
        scrollView.zoomScale
    }

    /// 设置缩放比例（会自动限制在 min/max 范围内）
    func setZoomScale(_ scale: CGFloat, animated: Bool) {
        // 绘制过程中不允许缩放，避免坐标系变化
        guard !isDrawing else { return }
        let clamped = max(minZoomScale, min(maxZoomScale, scale))
        scrollView.setZoomScale(clamped, animated: animated)
    }
    
    /// 清空画布
    func clearCanvas() {
        // 清空绘图
        pencilCanvas.drawing = PKDrawing()
        
        // 移除所有图片节点
        removeAllLayers()
        
        onCanvasUpdated?()
    }
    
    // MARK: - Layer Management
    
    /// 添加图层
    func addLayer(_ layer: LayerNode) {
        layers.append(layer)
        sortLayers()
        createImageView(for: layer)
        onLayersUpdated?(layers)
    }
    
    /// 移除图层
    func removeLayer(id: UUID) {
        layers.removeAll { $0.id == id }
        imageViews[id]?.removeFromSuperview()
        imageViews.removeValue(forKey: id)
        onLayersUpdated?(layers)
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
        
        // 重新排列视图顺序
        for (index, layer) in layers.enumerated() {
            if let imageView = imageViews[layer.id] {
                objectLayerView.insertSubview(imageView, at: index)
            }
        }
    }
    
    /// 创建图片视图
    private func createImageView(for layer: LayerNode) {
        let imageView = ResizableImageView(node: layer)
        
        // 设置回调
        imageView.onNodeUpdated = { [weak self] updatedNode in
            self?.updateLayer(updatedNode)
        }
        
        imageView.onSelected = { [weak self] nodeID in
            self?.selectedNodeID = nodeID
        }
        
        imageViews[layer.id] = imageView
        objectLayerView.addSubview(imageView)

        // 画布缩放优先：scrollView 的 pinch 能工作时，对象 pinch 必须先失败
        if let scrollPinch = scrollView.pinchGestureRecognizer {
            imageView.requireObjectPinchToFail(scrollPinch)
        }
        
        // 确保正确的渲染顺序
        sortLayers()
    }
    
    /// 更新选中状态
    private func updateSelectionStates() {
        for (id, imageView) in imageViews {
            imageView.isSelected = (id == selectedNodeID)
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
        newLayers.forEach { addLayer($0) }
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
    
    // MARK: - Tool Management (新架构)
    
    /// 根据工具更新手势处理
    func updateForTool(_ tool: CanvasTool) {
        switch tool {
        case .select:
            // 选择工具：禁用 PencilKit，启用对象手势，禁用画布滚动
            pencilCanvas.isUserInteractionEnabled = false
            objectLayerView.isUserInteractionEnabled = true
            scrollView.isScrollEnabled = false
            scrollView.panGestureRecognizer.isEnabled = false
            scrollView.pinchGestureRecognizer?.isEnabled = false
            
        case .pan:
            // 平移工具：禁用 PencilKit，禁用对象手势，启用画布滚动
            pencilCanvas.isUserInteractionEnabled = false
            objectLayerView.isUserInteractionEnabled = false
            scrollView.isScrollEnabled = true
            scrollView.panGestureRecognizer.isEnabled = true
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
            scrollView.pinchGestureRecognizer?.isEnabled = false
            
        case .pen:
            // 画笔工具：启用 PencilKit，禁用对象手势，锁定画布
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.tool = inkingTool
            pencilCanvas.drawingPolicy = .anyInput
            objectLayerView.isUserInteractionEnabled = false
            scrollView.isScrollEnabled = false
            scrollView.panGestureRecognizer.isEnabled = false
            scrollView.pinchGestureRecognizer?.isEnabled = false
            lockContentOffset()
            
        case .eraser:
            // 橡皮擦工具：启用 PencilKit，禁用对象手势，锁定画布
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.tool = eraserTool
            pencilCanvas.drawingPolicy = .anyInput
            objectLayerView.isUserInteractionEnabled = false
            scrollView.isScrollEnabled = false
            scrollView.panGestureRecognizer.isEnabled = false
            scrollView.pinchGestureRecognizer?.isEnabled = false
            lockContentOffset()
            
        case .image:
            // 图片工具：与选择工具类似，但点击时会触发图片导入
            pencilCanvas.isUserInteractionEnabled = false
            objectLayerView.isUserInteractionEnabled = true
            scrollView.isScrollEnabled = false
            scrollView.panGestureRecognizer.isEnabled = false
            scrollView.pinchGestureRecognizer?.isEnabled = false
            
        case .arrow:
            // 箭头工具：禁用 PencilKit，禁用对象手势，启用画布滚动
            pencilCanvas.isUserInteractionEnabled = false
            objectLayerView.isUserInteractionEnabled = false
            scrollView.isScrollEnabled = true
            scrollView.panGestureRecognizer.isEnabled = true
            scrollView.pinchGestureRecognizer?.isEnabled = true
            
        case .rectangle:
            // 矩形工具：禁用 PencilKit，禁用对象手势，启用画布滚动
            pencilCanvas.isUserInteractionEnabled = false
            objectLayerView.isUserInteractionEnabled = false
            scrollView.isScrollEnabled = true
            scrollView.panGestureRecognizer.isEnabled = true
            scrollView.pinchGestureRecognizer?.isEnabled = true
            
        case .text:
            // 文字工具：禁用 PencilKit，禁用对象手势，启用画布滚动
            pencilCanvas.isUserInteractionEnabled = false
            objectLayerView.isUserInteractionEnabled = false
            scrollView.isScrollEnabled = true
            scrollView.panGestureRecognizer.isEnabled = true
            scrollView.pinchGestureRecognizer?.isEnabled = true
            
        case .annotation:
            // 标注工具：禁用 PencilKit，禁用对象手势，启用画布滚动
            pencilCanvas.isUserInteractionEnabled = false
            objectLayerView.isUserInteractionEnabled = false
            scrollView.isScrollEnabled = true
            scrollView.panGestureRecognizer.isEnabled = true
            scrollView.pinchGestureRecognizer?.isEnabled = true
        }
    }
    
    /// 锁定当前 contentOffset（用于绘图模式）
    private func lockContentOffset() {
        storedContentOffset = scrollView.contentOffset
    }
    
    /// 更新手势处理（兼容旧代码）
    @available(*, deprecated, message: "使用 updateForTool(_:) 代替")
    private func updateGestureHandling() {
        switch currentMode {
        case .objectMode:
            updateForTool(.select)
        case .drawingMode:
            updateForTool(currentTool == .eraser ? .eraser : .pen)
        }
    }

    private func setScrollTransformsFrozen(_ frozen: Bool) {
        if frozen {
            // 存储当前状态
            storedPanEnabled = scrollView.panGestureRecognizer.isEnabled
            storedPinchEnabled = scrollView.pinchGestureRecognizer?.isEnabled ?? true
            storedScrollEnabled = scrollView.isScrollEnabled
            storedBounces = scrollView.bounces
            storedBouncesZoom = scrollView.bouncesZoom
            storedScrollViewInteraction = scrollView.isUserInteractionEnabled
            storedContentOffset = scrollView.contentOffset
            storedZoomScale = scrollView.zoomScale
            
            // 完全冻结 scrollView
            scrollView.panGestureRecognizer.isEnabled = false
            scrollView.pinchGestureRecognizer?.isEnabled = false
            scrollView.isScrollEnabled = false
            scrollView.bounces = false
            scrollView.bouncesZoom = false
            if #available(iOS 13.4, *) {
                scrollView.panGestureRecognizer.allowedScrollTypesMask = []
            }
        } else {
            // 恢复状态
            scrollView.panGestureRecognizer.isEnabled = storedPanEnabled
            scrollView.pinchGestureRecognizer?.isEnabled = storedPinchEnabled
            scrollView.isScrollEnabled = storedScrollEnabled
            scrollView.bounces = storedBounces
            scrollView.bouncesZoom = storedBouncesZoom
            if #available(iOS 13.4, *) {
                scrollView.panGestureRecognizer.allowedScrollTypesMask = [.continuous, .discrete]
            }
        }
    }
    
    /// 切换绘图工具（兼容旧代码）
    @available(*, deprecated, message: "使用 currentTool = .pen/.eraser 代替")
    func setDrawingTool(isPen: Bool) {
        guard !isDrawing else { return }
        currentTool = isPen ? .pen : .eraser
    }
    
    // MARK: - Drawing Operations
    
    /// 获取当前绘图数据
    func getDrawingData() -> Data? {
        try? pencilCanvas.drawing.dataRepresentation()
    }
    
    /// 加载绘图数据
    func loadDrawing(from data: Data) {
        guard let drawing = try? PKDrawing(data: data) else { return }
        pencilCanvas.drawing = drawing
    }
    
    // MARK: - Snapshot
    
    /// 捕获内容坐标系中的指定区域快照（合并所有图层）
    func captureContentSnapshot(rect contentRect: CGRect) -> UIImage? {
        let bounded = contentRect.intersection(contentView.bounds)
        guard !bounded.isNull, bounded.width > 1, bounded.height > 1 else { return nil }

        let scale = UIScreen.main.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        // 1) PencilKit：用官方导出
        let drawingImage = pencilCanvas.drawing.image(from: bounded, scale: scale)

        // 2) 对象层：用 Core Animation 渲染
        let renderer = UIGraphicsImageRenderer(size: bounded.size, format: format)
        return renderer.image { rendererContext in
            let ctx = rendererContext.cgContext
            ctx.saveGState()
            ctx.clip(to: CGRect(origin: .zero, size: bounded.size))
            ctx.translateBy(x: -bounded.origin.x, y: -bounded.origin.y)
            objectLayerView.layer.render(in: ctx)
            ctx.restoreGState()

            // 叠加 PencilKit 层
            drawingImage.draw(in: CGRect(origin: .zero, size: bounded.size))
        }
    }

    /// 将"视口坐标系"的 rect 映射到"画布内容坐标系"的 rect
    func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
        let rectInScrollView = scrollView.convert(viewportRect, from: self)
        return contentView.convert(rectInScrollView, from: scrollView)
    }

    /// 捕获"视口坐标系"的指定区域快照
    func captureViewportSnapshot(rect viewportRect: CGRect) -> UIImage? {
        let contentRect = contentRect(forViewportRect: viewportRect)
        return captureContentSnapshot(rect: contentRect)
    }
    
    /// 捕获整个画布快照
    func captureFullSnapshot() -> UIImage? {
        captureContentSnapshot(rect: contentView.bounds)
    }
    
    // MARK: - 箭头管理
    
    /// 获取箭头图层管理器
    func getArrowLayerManager() -> ArrowLayerManager {
        return arrowLayerManager
    }
    
    /// 添加箭头
    func addArrow(_ arrow: ArrowLayerNode, recordUndo: Bool = true) {
        if recordUndo {
            // 记录操作用于撤销
            let action = AddArrowAction(
                arrow: arrow,
                canvasView: self
            )
            
            // 通过通知中心发送操作
            NotificationCenter.default.post(
                name: .canvasActionRecorded,
                object: action
            )
        }
        
        arrowLayerManager.addArrow(arrow)
        onArrowCreated?(arrow)
        onCanvasUpdated?()
    }
    
    /// 移除箭头
    func removeArrow(id: UUID) {
        arrowLayerManager.removeArrow(id: id)
        onCanvasUpdated?()
    }
    
    /// 更新箭头
    func updateArrow(_ arrow: ArrowLayerNode) {
        arrowLayerManager.updateArrow(arrow)
        onCanvasUpdated?()
    }
    
    /// 清空所有箭头
    func clearArrows() {
        arrowLayerManager.clearAll()
        onCanvasUpdated?()
    }
    
    // MARK: - 矩形管理
    
    /// 获取矩形图层管理器
    func getRectangleLayerManager() -> RectangleLayerManager {
        return rectangleLayerManager
    }
    
    /// 添加矩形
    func addRectangle(_ rectangle: RectangleLayerNode, recordUndo: Bool = true) {
        if recordUndo {
            // 记录操作用于撤销
            let action = AddRectangleAction(
                rectangle: rectangle,
                canvasView: self
            )
            
            // 通过通知中心发送操作
            NotificationCenter.default.post(
                name: .canvasActionRecorded,
                object: action
            )
        }
        
        rectangleLayerManager.addRectangle(rectangle)
        onRectangleCreated?(rectangle)
        onCanvasUpdated?()
    }
    
    /// 移除矩形
    func removeRectangle(id: UUID) {
        rectangleLayerManager.removeRectangle(id: id)
        onCanvasUpdated?()
    }
    
    /// 更新矩形
    func updateRectangle(_ rectangle: RectangleLayerNode) {
        rectangleLayerManager.updateRectangle(rectangle)
        onCanvasUpdated?()
    }
    
    /// 清空所有矩形
    func clearRectangles() {
        rectangleLayerManager.clearAll()
        onCanvasUpdated?()
    }
    
    // MARK: - 文字管理
    
    /// 获取文字图层管理器
    func getTextLayerManager() -> TextLayerManager {
        return textLayerManager
    }
    
    /// 添加文字
    func addText(_ text: TextLayerNode, recordUndo: Bool = true) {
        if recordUndo {
            // 记录操作用于撤销
            let action = AddTextAction(
                text: text,
                canvasView: self
            )
            
            // 通过通知中心发送操作
            NotificationCenter.default.post(
                name: .canvasActionRecorded,
                object: action
            )
        }
        
        textLayerManager.addText(text)
        onTextCreated?(text)
        onCanvasUpdated?()
    }
    
    /// 移除文字
    func removeText(id: UUID) {
        textLayerManager.removeText(id: id)
        onCanvasUpdated?()
    }
    
    /// 更新文字
    func updateText(_ text: TextLayerNode) {
        textLayerManager.updateText(text)
        onCanvasUpdated?()
    }
    
    /// 清空所有文字
    func clearTexts() {
        textLayerManager.clearAll()
        onCanvasUpdated?()
    }
    
    // MARK: - 标注管理
    
    /// 获取标注图层管理器
    func getAnnotationLayerManager() -> AnnotationLayerManager {
        return annotationLayerManager
    }
    
    /// 添加标注
    func addAnnotation(_ annotation: AnnotationLayerNode, recordUndo: Bool = true) {
        if recordUndo {
            // 记录操作用于撤销
            let action = AddAnnotationAction(
                annotation: annotation,
                canvasView: self
            )
            
            // 通过通知中心发送操作
            NotificationCenter.default.post(
                name: .canvasActionRecorded,
                object: action
            )
        }
        
        annotationLayerManager.addAnnotation(annotation)
        onAnnotationCreated?(annotation)
        onCanvasUpdated?()
    }
    
    /// 移除标注
    func removeAnnotation(id: UUID) {
        annotationLayerManager.removeAnnotation(id: id)
        onCanvasUpdated?()
    }
    
    /// 更新标注
    func updateAnnotation(_ annotation: AnnotationLayerNode) {
        annotationLayerManager.updateAnnotation(annotation)
        onCanvasUpdated?()
    }
    
    /// 清空所有标注
    func clearAnnotations() {
        annotationLayerManager.clearAll()
        onCanvasUpdated?()
    }
}

// MARK: - UIScrollViewDelegate

extension NativeCanvasView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentView
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // 绘制过程中强制恢复 contentOffset
        if isDrawing {
            scrollView.contentOffset = storedContentOffset
        }
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        guard !isDrawing else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        contentView.center = CGPoint(
            x: scrollView.contentSize.width * 0.5 + offsetX,
            y: scrollView.contentSize.height * 0.5 + offsetY
        )
        CATransaction.commit()
        onZoomChanged?(scrollView.zoomScale)
    }
}

// MARK: - PKCanvasViewDelegate

extension NativeCanvasView: PKCanvasViewDelegate {
    func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
        isDrawing = true
        setScrollTransformsFrozen(true)
    }

    func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
        isDrawing = false
        setScrollTransformsFrozen(false)
        onCanvasUpdated?()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isDrawing else { return }
        onCanvasUpdated?()
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI 包装器
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
        guard !uiView.isDrawing else { return }
        
        if uiView.currentTool != currentTool {
            uiView.currentTool = currentTool
        }

        uiView.onCanvasUpdated = onCanvasUpdated
        uiView.onZoomChanged = onZoomChanged
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        // 预留
    }
}

// MARK: - 兼容旧的 ToolMode Wrapper（将被移除）

/// 兼容旧代码的包装器
@available(*, deprecated, message: "使用新的 NativeCanvasViewWrapper 代替")
struct LegacyNativeCanvasViewWrapper: UIViewRepresentable {
    @Binding var toolMode: CanvasToolMode
    var onCanvasUpdated: (() -> Void)?
    var onViewCreated: ((NativeCanvasView) -> Void)?
    var onZoomChanged: ((CGFloat) -> Void)? = nil
    
    func makeUIView(context: Context) -> NativeCanvasView {
        let view = NativeCanvasView()
        view.currentMode = toolMode
        view.onCanvasUpdated = onCanvasUpdated
        view.onZoomChanged = onZoomChanged
        
        onViewCreated?(view)
        
        return view
    }
    
    func updateUIView(_ uiView: NativeCanvasView, context: Context) {
        guard !uiView.isDrawing else { return }
        
        if uiView.currentMode != toolMode {
            uiView.currentMode = toolMode
        }

        uiView.onCanvasUpdated = onCanvasUpdated
        uiView.onZoomChanged = onZoomChanged
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        // 预留
    }
}
