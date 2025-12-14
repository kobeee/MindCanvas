import Foundation
import CoreGraphics
import Combine

/// 箭头图层节点
/// 表示画布上的一个箭头对象
struct ArrowLayerNode: Codable, Identifiable {
    let id: UUID
    let startPoint: CGPoint
    let endPoint: CGPoint
    let color: String // 十六进制颜色值
    let lineWidth: CGFloat
    let zIndex: Int
    let createdAt: Date
    
    /// 计算箭头的边界框
    /// 确保边界框有最小尺寸，避免视图大小为 0
    var bounds: CGRect {
        let minX = min(startPoint.x, endPoint.x)
        let minY = min(startPoint.y, endPoint.y)
        let maxX = max(startPoint.x, endPoint.x)
        let maxY = max(startPoint.y, endPoint.y)

        // 确保最小尺寸为 40x40，避免边界框太小无法点击或显示
        let width = max(maxX - minX, 40)
        let height = max(maxY - minY, 40)

        // 如果原始尺寸太小，需要调整原点使箭头居中
        let adjustedMinX = (maxX - minX < 40) ? minX - (40 - (maxX - minX)) / 2 : minX
        let adjustedMinY = (maxY - minY < 40) ? minY - (40 - (maxY - minY)) / 2 : minY

        return CGRect(
            x: adjustedMinX,
            y: adjustedMinY,
            width: width,
            height: height
        )
    }
    
    /// 创建箭头图层
    init(startPoint: CGPoint, endPoint: CGPoint, color: String = "#000000", lineWidth: CGFloat = 3, zIndex: Int = 0) {
        self.id = UUID()
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.color = color
        self.lineWidth = lineWidth
        self.zIndex = zIndex
        self.createdAt = Date()
    }
    
    /// 更新箭头位置
    func updated(startPoint: CGPoint? = nil, endPoint: CGPoint? = nil, color: String? = nil, lineWidth: CGFloat? = nil, zIndex: Int? = nil) -> ArrowLayerNode {
        ArrowLayerNode(
            startPoint: startPoint ?? self.startPoint,
            endPoint: endPoint ?? self.endPoint,
            color: color ?? self.color,
            lineWidth: lineWidth ?? self.lineWidth,
            zIndex: zIndex ?? self.zIndex
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