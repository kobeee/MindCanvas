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
    
    /// 当前工具模式
    var currentMode: CanvasToolMode = .objectMode {
        didSet {
            updateGestureHandling()
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
        // drawingPolicy 由 currentMode 决定（在 updateGestureHandling 中统一设置）
        pencilCanvas.delegate = self
        
        // 图层堆叠
        contentView.addSubview(objectLayerView)
        contentView.addSubview(pencilCanvas)
        scrollView.addSubview(contentView)
        addSubview(scrollView)
        
        // 初始化画布居中
        DispatchQueue.main.async { [weak self] in
            self?.centerCanvas()
            self?.updateGestureHandling()
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
        
        // 内容视图和子图层的 frame 在 layoutSubviews 中设置
    }
    
    private func setupGestures() {
        // 对象图层的手势识别器将在添加图片节点时配置
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
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
    
    // MARK: - Tool Mode Management
    
    /// 更新手势处理 (根据当前模式)
    private func updateGestureHandling() {
        switch currentMode {
        case .objectMode:
            // 对象模式: 禁用 PencilKit，启用对象手势
            pencilCanvas.isUserInteractionEnabled = false
            objectLayerView.isUserInteractionEnabled = true
            // 单指拖动平移画布
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
            
        case .drawingMode:
            // 绘图模式: 启用 PencilKit（允许任何输入绘制），禁用对象手势
            pencilCanvas.isUserInteractionEnabled = true
            pencilCanvas.drawingPolicy = .anyInput
            objectLayerView.isUserInteractionEnabled = false
            // 绘图模式下：单指用于绘制；双指用于平移画布（更符合“any-input + 可漫游”）
            scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        }
    }
    
    /// 切换绘图工具
    func setDrawingTool(isPen: Bool) {
        pencilCanvas.tool = isPen ? inkingTool : eraserTool
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

        let renderer = UIGraphicsImageRenderer(size: bounded.size)
        return renderer.image { rendererContext in
            // 将要裁剪的区域移动到 (0,0)
            rendererContext.cgContext.translateBy(x: -bounded.origin.x, y: -bounded.origin.y)

            // 渲染 Layer 1: 对象图层
            objectLayerView.drawHierarchy(in: objectLayerView.bounds, afterScreenUpdates: true)

            // 渲染 Layer 2: PencilKit 绘图
            pencilCanvas.drawHierarchy(in: pencilCanvas.bounds, afterScreenUpdates: true)
        }
    }

    /// 将“视口（屏幕）坐标系”的 rect 映射到“画布内容坐标系”的 rect
    /// - Parameter viewportRect: 相对于 NativeCanvasView 自身 bounds 的屏幕坐标 rect（即 SwiftUI HUD 的坐标系）
    func contentRect(forViewportRect viewportRect: CGRect) -> CGRect {
        // 1) 先转换到 scrollView 坐标（scrollView 填满 self，但仍走 convert 以避免未来布局变化）
        let rectInScrollView = scrollView.convert(viewportRect, from: self)
        // 2) 再转换到 contentView 坐标（UIKit 会自动处理 zoom/center 等变换）
        return contentView.convert(rectInScrollView, from: scrollView)
    }

    /// 捕获“视口（屏幕）坐标系”的指定区域快照（用于 HUD 选框）
    func captureViewportSnapshot(rect viewportRect: CGRect) -> UIImage? {
        let contentRect = contentRect(forViewportRect: viewportRect)
        return captureContentSnapshot(rect: contentRect)
    }
    
    /// 捕获整个画布快照
    func captureFullSnapshot() -> UIImage? {
        captureContentSnapshot(rect: contentView.bounds)
    }
}

// MARK: - UIScrollViewDelegate

extension NativeCanvasView: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        contentView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // 缩放时保持画布居中
        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
        contentView.center = CGPoint(
            x: scrollView.contentSize.width * 0.5 + offsetX,
            y: scrollView.contentSize.height * 0.5 + offsetY
        )
        onZoomChanged?(scrollView.zoomScale)
    }
}

// MARK: - PKCanvasViewDelegate

extension NativeCanvasView: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        onCanvasUpdated?()
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI 包装器
struct NativeCanvasViewWrapper: UIViewRepresentable {
    @Binding var toolMode: CanvasToolMode
    var onCanvasUpdated: (() -> Void)?
    var onViewCreated: ((NativeCanvasView) -> Void)?
    var onZoomChanged: ((CGFloat) -> Void)? = nil
    
    func makeUIView(context: Context) -> NativeCanvasView {
        let view = NativeCanvasView()
        view.currentMode = toolMode
        view.onCanvasUpdated = onCanvasUpdated
        view.onZoomChanged = onZoomChanged
        
        // 通知外部视图已创建
        onViewCreated?(view)
        
        return view
    }
    
    func updateUIView(_ uiView: NativeCanvasView, context: Context) {
        if uiView.currentMode != toolMode {
            uiView.currentMode = toolMode
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        // 预留：用于处理更复杂的回调
    }
}
