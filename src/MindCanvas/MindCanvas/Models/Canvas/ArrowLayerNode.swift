import Foundation
import CoreGraphics
import Combine

/// 箭头图层节点
/// 表示画布上的一个箭头对象
struct ArrowLayerNode: Codable, Identifiable {
    let id: UUID
    var startPoint: CGPoint
    var endPoint: CGPoint
    let color: String // 十六进制颜色值
    let lineWidth: CGFloat
    let zIndex: Int
    let createdAt: Date
    
    // 旋转角度（弧度）
    var rotation: Double = 0.0
    
    // 缩放比例
    var scale: CGFloat = 1.0
    
    /// 计算箭头的边界框
    /// 确保边界框有最小尺寸，避免视图大小为 0
    var bounds: CGRect {
        let minX = min(startPoint.x, endPoint.x)
        let minY = min(startPoint.y, endPoint.y)
        let maxX = max(startPoint.x, endPoint.x)
        let maxY = max(startPoint.y, endPoint.y)

        // 确保最小尺寸为 40x40，避免边界框太小无法点击或显示
        let baseWidth = max(maxX - minX, 40)
        let baseHeight = max(maxY - minY, 40)

        // 应用缩放
        let scaledWidth = baseWidth * scale
        let scaledHeight = baseHeight * scale

        // 计算中心点
        let centerX = (startPoint.x + endPoint.x) / 2
        let centerY = (startPoint.y + endPoint.y) / 2

        return CGRect(
            x: centerX - scaledWidth / 2,
            y: centerY - scaledHeight / 2,
            width: scaledWidth,
            height: scaledHeight
        )
    }
    
    /// 获取箭头中心点
    var center: CGPoint {
        CGPoint(
            x: (startPoint.x + endPoint.x) / 2,
            y: (startPoint.y + endPoint.y) / 2
        )
    }
    
    /// 创建箭头图层
    init(startPoint: CGPoint, endPoint: CGPoint, color: String = "#000000", lineWidth: CGFloat = 3, zIndex: Int = 0, rotation: Double = 0.0, scale: CGFloat = 1.0) {
        self.id = UUID()
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.zIndex = zIndex
        self.rotation = rotation
        self.scale = scale
        self.createdAt = Date()
    }
    
    /// 更新箭头属性
    func updated(startPoint: CGPoint? = nil, endPoint: CGPoint? = nil, color: String? = nil, lineWidth: CGFloat? = nil, zIndex: Int? = nil, rotation: Double? = nil, scale: CGFloat? = nil) -> ArrowLayerNode {
        var node = self
        if let startPoint = startPoint { node.startPoint = startPoint }
        if let endPoint = endPoint { node.endPoint = endPoint }
        if let rotation = rotation { node.rotation = rotation }
        if let scale = scale { node.scale = scale }
        // 其他属性由于是 let，需要创建新实例
        return ArrowLayerNode(
            startPoint: node.startPoint,
            endPoint: node.endPoint,
            color: color ?? self.color,
            lineWidth: lineWidth ?? self.lineWidth,
            zIndex: zIndex ?? self.zIndex,
            rotation: node.rotation,
            scale: node.scale
        )
    }
}

/// 箭头图层管理器
/// 管理画布上的所有箭头图层
class ArrowLayerManager: ObservableObject {
    @Published var arrows: [ArrowLayerNode] = []
    
    /// 添加箭头
    func addArrow(_ arrow: ArrowLayerNode) {
        arrows.append(arrow)
        sortByZIndex()
    }
    
    /// 移除箭头
    func removeArrow(id: UUID) {
        arrows.removeAll { $0.id == id }
    }
    
    /// 更新箭头
    func updateArrow(_ arrow: ArrowLayerNode) {
        if let index = arrows.firstIndex(where: { $0.id == arrow.id }) {
            arrows[index] = arrow
            sortByZIndex()
        }
    }
    
    /// 按 Z-Index 排序
    private func sortByZIndex() {
        arrows.sort { $0.zIndex < $1.zIndex }
    }
    
    /// 获取下一个可用的 Z-Index
    func getNextZIndex() -> Int {
        return (arrows.map(\.zIndex).max() ?? 0) + 1
    }
    
    /// 清空所有箭头
    func clearAll() {
        arrows.removeAll()
    }
}