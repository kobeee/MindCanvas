import Foundation

/// 画布文档 - 代表一个完整的创作画布状态
struct CanvasDocument: Codable, Identifiable {
    /// 文档唯一标识符
    let id: UUID
    
    /// 所属项目 ID (关联 Project)
    var projectID: UUID
    
    /// 图层节点数组 (按 zIndex 排序)
    var layers: [LayerNode]
    
    /// 箭头图层数组 (按 zIndex 排序)
    var arrows: [ArrowLayerNode]
    
    /// 矩形图层数组 (按 zIndex 排序)
    var rectangles: [RectangleLayerNode]
    
    /// 文字图层数组 (按 zIndex 排序)
    var texts: [TextLayerNode]
    
    /// 标注图层数组 (按 zIndex 排序)
    var annotations: [AnnotationLayerNode]
    
    /// PencilKit 绘图数据 (序列化后的 PKDrawing)
    var drawingData: Data?
    
    /// 画布变换状态 (缩放和平移)
    var canvasTransform: CanvasTransform
    
    /// 创建时间
    var createdAt: Date
    
    /// 最后修改时间
    var modifiedAt: Date
    
    // MARK: - 初始化
    
    init(
        id: UUID = UUID(),
        projectID: UUID,
        layers: [LayerNode] = [],
        arrows: [ArrowLayerNode] = [],
        rectangles: [RectangleLayerNode] = [],
        texts: [TextLayerNode] = [],
        annotations: [AnnotationLayerNode] = [],
        drawingData: Data? = nil,
        canvasTransform: CanvasTransform = .identity,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.layers = layers
        self.arrows = arrows
        self.rectangles = rectangles
        self.texts = texts
        self.annotations = annotations
        self.drawingData = drawingData
        self.canvasTransform = canvasTransform
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
    
    // MARK: - 图层管理
    
    /// 添加新图层
    mutating func addLayer(_ layer: LayerNode) {
        layers.append(layer)
        sortLayers()
        updateModifiedDate()
    }
    
    /// 删除图层
    mutating func removeLayer(id: UUID) {
        layers.removeAll { $0.id == id }
        updateModifiedDate()
    }
    
    /// 更新图层
    mutating func updateLayer(_ layer: LayerNode) {
        if let index = layers.firstIndex(where: { $0.id == layer.id }) {
            layers[index] = layer
            sortLayers()
            updateModifiedDate()
        }
    }
    
    /// 按 zIndex 排序图层 (升序，数值越大越靠上)
    mutating func sortLayers() {
        layers.sort { $0.zIndex < $1.zIndex }
    }
    
    /// 获取最大 zIndex
    var maxZIndex: Int {
        layers.map(\.zIndex).max() ?? 0
    }
    
    /// 置顶图层
    mutating func bringLayerToFront(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].zIndex = maxZIndex + 1
        sortLayers()
        updateModifiedDate()
    }
    
    /// 置底图层
    mutating func sendLayerToBack(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        let minZIndex = layers.map(\.zIndex).min() ?? 0
        layers[index].zIndex = minZIndex - 1
        sortLayers()
        updateModifiedDate()
    }
    
    /// 上移一层
    mutating func bringLayerForward(id: UUID) {
        guard let currentIndex = layers.firstIndex(where: { $0.id == id }),
              currentIndex < layers.count - 1 else { return }
        let targetZIndex = layers[currentIndex + 1].zIndex
        layers[currentIndex].zIndex = targetZIndex + 1
        sortLayers()
        updateModifiedDate()
    }
    
    /// 下移一层
    mutating func sendLayerBackward(id: UUID) {
        guard let currentIndex = layers.firstIndex(where: { $0.id == id }),
              currentIndex > 0 else { return }
        let targetZIndex = layers[currentIndex - 1].zIndex
        layers[currentIndex].zIndex = targetZIndex - 1
        sortLayers()
        updateModifiedDate()
    }
    
    // MARK: - 辅助方法
    
    /// 更新修改时间
    private mutating func updateModifiedDate() {
        modifiedAt = Date()
    }
    
    // MARK: - 箭头管理
    
    /// 添加箭头
    mutating func addArrow(_ arrow: ArrowLayerNode) {
        arrows.append(arrow)
        sortArrows()
        updateModifiedDate()
    }
    
    /// 删除箭头
    mutating func removeArrow(id: UUID) {
        arrows.removeAll { $0.id == id }
        updateModifiedDate()
    }
    
    /// 更新箭头
    mutating func updateArrow(_ arrow: ArrowLayerNode) {
        if let index = arrows.firstIndex(where: { $0.id == arrow.id }) {
            arrows[index] = arrow
            sortArrows()
            updateModifiedDate()
        }
    }
    
    /// 按 zIndex 排序箭头 (升序，数值越大越靠上)
    mutating func sortArrows() {
        arrows.sort { $0.zIndex < $1.zIndex }
    }
    
    /// 获取箭头最大 zIndex
    var maxArrowZIndex: Int {
        arrows.map(\.zIndex).max() ?? 0
    }
    
    // MARK: - 矩形管理
    
    /// 添加矩形
    mutating func addRectangle(_ rectangle: RectangleLayerNode) {
        rectangles.append(rectangle)
        sortRectangles()
        updateModifiedDate()
    }
    
    /// 删除矩形
    mutating func removeRectangle(id: UUID) {
        rectangles.removeAll { $0.id == id }
        updateModifiedDate()
    }
    
    /// 更新矩形
    mutating func updateRectangle(_ rectangle: RectangleLayerNode) {
        if let index = rectangles.firstIndex(where: { $0.id == rectangle.id }) {
            rectangles[index] = rectangle
            sortRectangles()
            updateModifiedDate()
        }
    }
    
    /// 按 zIndex 排序矩形 (升序，数值越大越靠上)
    mutating func sortRectangles() {
        rectangles.sort { $0.zIndex < $1.zIndex }
    }
    
    /// 获取矩形最大 zIndex
    var maxRectangleZIndex: Int {
        rectangles.map(\.zIndex).max() ?? 0
    }
    
    // MARK: - 文字管理
    
    /// 添加文字
    mutating func addText(_ text: TextLayerNode) {
        texts.append(text)
        sortTexts()
        updateModifiedDate()
    }
    
    /// 删除文字
    mutating func removeText(id: UUID) {
        texts.removeAll { $0.id == id }
        updateModifiedDate()
    }
    
    /// 更新文字
    mutating func updateText(_ text: TextLayerNode) {
        if let index = texts.firstIndex(where: { $0.id == text.id }) {
            texts[index] = text
            sortTexts()
            updateModifiedDate()
        }
    }
    
    /// 按 zIndex 排序文字 (升序，数值越大越靠上)
    mutating func sortTexts() {
        texts.sort { $0.zIndex < $1.zIndex }
    }
    
    /// 获取文字最大 zIndex
    var maxTextZIndex: Int {
        texts.map(\.zIndex).max() ?? 0
    }
    
    // MARK: - 标注管理
    
    /// 添加标注
    mutating func addAnnotation(_ annotation: AnnotationLayerNode) {
        annotations.append(annotation)
        sortAnnotations()
        updateModifiedDate()
    }
    
    /// 删除标注
    mutating func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        updateModifiedDate()
    }
    
    /// 更新标注
    mutating func updateAnnotation(_ annotation: AnnotationLayerNode) {
        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[index] = annotation
            sortAnnotations()
            updateModifiedDate()
        }
    }
    
    /// 按 zIndex 排序标注 (升序，数值越大越靠上)
    mutating func sortAnnotations() {
        annotations.sort { $0.zIndex < $1.zIndex }
    }
    
    /// 获取标注最大 zIndex
    var maxAnnotationZIndex: Int {
        annotations.map(\.zIndex).max() ?? 0
    }
    
    /// 清空所有内容
    mutating func clear() {
        layers.removeAll()
        arrows.removeAll()
        rectangles.removeAll()
        texts.removeAll()
        annotations.removeAll()
        drawingData = nil
        canvasTransform = .identity
        updateModifiedDate()
    }
    
    /// 图层数量
    var layerCount: Int {
        layers.count
    }
    
    /// 箭头数量
    var arrowCount: Int {
        arrows.count
    }
    
    /// 矩形数量
    var rectangleCount: Int {
        rectangles.count
    }
    
    /// 文字数量
    var textCount: Int {
        texts.count
    }
    
    /// 标注数量
    var annotationCount: Int {
        annotations.count
    }
    
    /// 是否为空画布
    var isEmpty: Bool {
        layers.isEmpty && arrows.isEmpty && rectangles.isEmpty && texts.isEmpty && annotations.isEmpty && drawingData == nil
    }
}

