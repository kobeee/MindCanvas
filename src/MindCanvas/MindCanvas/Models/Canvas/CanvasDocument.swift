import Foundation

/// 画布文档 - 代表一个完整的创作画布状态
struct CanvasDocument: Codable, Identifiable {
    /// 文档唯一标识符
    let id: UUID
    
    /// 所属项目 ID (关联 Project)
    var projectID: UUID
    
    /// 图层节点数组 (按 zIndex 排序)
    var layers: [LayerNode]
    
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
        drawingData: Data? = nil,
        canvasTransform: CanvasTransform = .identity,
        createdAt: Date = Date(),
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.projectID = projectID
        self.layers = layers
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
    
    /// 清空所有内容
    mutating func clear() {
        layers.removeAll()
        drawingData = nil
        canvasTransform = .identity
        updateModifiedDate()
    }
    
    /// 图层数量
    var layerCount: Int {
        layers.count
    }
    
    /// 是否为空画布
    var isEmpty: Bool {
        layers.isEmpty && drawingData == nil
    }
}

