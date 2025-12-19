import Foundation
import CoreGraphics

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
    
    /// 文档版本号（用于兼容性检查）
    var version: Int = 1
    
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
        modifiedAt: Date = Date(),
        version: Int = 1
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
        self.version = version
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
    
    // MARK: - 数据验证和完整性检查
    
    /// 验证文档数据的完整性和有效性
    func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        
        // 验证基本字段
        if projectID == UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
            errors.append(.invalidProjectID)
        }
        
        // 验证图层
        for layer in layers {
            if layer.frame.width <= 0 || layer.frame.height <= 0 {
                errors.append(.invalidLayerSize(id: layer.id))
            }
        }
        
        // 验证箭头
        for arrow in arrows {
            if arrow.startPoint == arrow.endPoint {
                errors.append(.invalidArrowGeometry(id: arrow.id))
            }
        }
        
        // 验证矩形
        for rectangle in rectangles {
            if rectangle.frame.width <= 0 || rectangle.frame.height <= 0 {
                errors.append(.invalidRectangleSize(id: rectangle.id))
            }
        }
        
        // 验证文字
        for text in texts {
            if text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyText(id: text.id))
            }
            if text.fontSize <= 0 || text.scale <= 0 {
                errors.append(.invalidTextProperties(id: text.id))
            }
        }
        
        // 验证标注
        for annotation in annotations {
            if annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errors.append(.emptyAnnotation(id: annotation.id))
            }
        }
        
        return errors
    }
    
    /// 修复可修复的数据问题
    mutating func repair() {
        // 修复无效的图层尺寸
        for i in layers.indices {
            if layers[i].frame.width <= 0 {
                layers[i].frame.size.width = 100
            }
            if layers[i].frame.height <= 0 {
                layers[i].frame.size.height = 100
            }
        }
        
        // 修复无效的矩形尺寸
        for i in rectangles.indices {
            if rectangles[i].rect.width <= 0 {
                rectangles[i] = rectangles[i].updated(rect: CGRect(
                    x: rectangles[i].rect.origin.x,
                    y: rectangles[i].rect.origin.y,
                    width: 100,
                    height: rectangles[i].rect.height
                ))
            }
            if rectangles[i].rect.height <= 0 {
                rectangles[i] = rectangles[i].updated(rect: CGRect(
                    x: rectangles[i].rect.origin.x,
                    y: rectangles[i].rect.origin.y,
                    width: rectangles[i].rect.width,
                    height: 100
                ))
            }
        }
        
        // 修复无效的文字属性
        for i in texts.indices {
            if texts[i].fontSize <= 0 {
                texts[i].fontSize = 16
            }
            if texts[i].scale <= 0 {
                texts[i].scale = 1.0
            }
        }
        
        // 移除空的文字和标注
        texts.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        annotations.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        // 移除重复的箭头（起点和终点相同）
        arrows.removeAll { $0.startPoint == $0.endPoint }
        
        updateModifiedDate()
    }
    
    /// 获取文档统计信息
    var statistics: DocumentStatistics {
        DocumentStatistics(
            layerCount: layers.count,
            arrowCount: arrows.count,
            rectangleCount: rectangles.count,
            textCount: texts.count,
            annotationCount: annotations.count,
            hasDrawingData: drawingData != nil,
            totalSize: estimateDataSize(),
            version: version
        )
    }
    
    /// 估算文档数据大小（字节）
    private func estimateDataSize() -> Int {
        var size = 0
        size += layers.count * 256 // 估算每个图层256字节
        size += arrows.count * 128 // 估算每个箭头128字节
        size += rectangles.count * 128
        size += texts.count * 512 // 文字数据较大
        size += annotations.count * 256
        size += drawingData?.count ?? 0
        return size
    }
    
    // MARK: - 增量保存支持
    
    /// 生成增量快照（用于优化保存性能）
    func generateIncrementalSnapshot(from previous: CanvasDocument) -> DocumentSnapshot {
        let changedLayers = layers.filter { layer in
            !previous.layers.contains { $0.id == layer.id && $0 == layer }
        }
        
        let changedArrows = arrows.filter { arrow in
            !previous.arrows.contains { $0.id == arrow.id && $0 == arrow }
        }
        
        let changedRectangles = rectangles.filter { rectangle in
            !previous.rectangles.contains { $0.id == rectangle.id && $0 == rectangle }
        }
        
        let changedTexts = texts.filter { text in
            !previous.texts.contains { $0.id == text.id && $0 == text }
        }
        
        let changedAnnotations = annotations.filter { annotation in
            !previous.annotations.contains { $0.id == annotation.id && $0 == annotation }
        }
        
        let drawingChanged = drawingData != previous.drawingData
        
        return DocumentSnapshot(
            changedLayers: changedLayers,
            changedArrows: changedArrows,
            changedRectangles: changedRectangles,
            changedTexts: changedTexts,
            changedAnnotations: changedAnnotations,
            drawingChanged: drawingChanged,
            drawingData: drawingChanged ? drawingData : nil,
            timestamp: Date()
        )
    }
}

// MARK: - 支持类型

/// 验证错误类型
enum ValidationError: Equatable {
    case invalidProjectID
    case invalidLayerSize(id: UUID)
    case invalidArrowGeometry(id: UUID)
    case invalidRectangleSize(id: UUID)
    case emptyText(id: UUID)
    case invalidTextProperties(id: UUID)
    case emptyAnnotation(id: UUID)
    
    var localizedDescription: String {
        switch self {
        case .invalidProjectID:
            return "无效的项目ID"
        case .invalidLayerSize(let id):
            return "图层尺寸无效 (ID: \(id.uuidString.prefix(8)))"
        case .invalidArrowGeometry(let id):
            return "箭头几何无效 (ID: \(id.uuidString.prefix(8)))"
        case .invalidRectangleSize(let id):
            return "矩形尺寸无效 (ID: \(id.uuidString.prefix(8)))"
        case .emptyText(let id):
            return "文字内容为空 (ID: \(id.uuidString.prefix(8)))"
        case .invalidTextProperties(let id):
            return "文字属性无效 (ID: \(id.uuidString.prefix(8)))"
        case .emptyAnnotation(let id):
            return "标注内容为空 (ID: \(id.uuidString.prefix(8)))"
        }
    }
}

/// 文档统计信息
struct DocumentStatistics {
    let layerCount: Int
    let arrowCount: Int
    let rectangleCount: Int
    let textCount: Int
    let annotationCount: Int
    let hasDrawingData: Bool
    let totalSize: Int
    let version: Int
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }
}

/// 文档增量快照
struct DocumentSnapshot: Codable {
    let changedLayers: [LayerNode]
    let changedArrows: [ArrowLayerNode]
    let changedRectangles: [RectangleLayerNode]
    let changedTexts: [TextLayerNode]
    let changedAnnotations: [AnnotationLayerNode]
    let drawingChanged: Bool
    let drawingData: Data?
    let timestamp: Date
}

