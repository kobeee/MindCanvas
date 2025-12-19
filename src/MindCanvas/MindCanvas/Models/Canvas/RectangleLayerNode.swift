import Foundation
import CoreGraphics
import Combine

/// 矩形图层节点
/// 表示画布上的一个矩形对象
struct RectangleLayerNode: Codable, Identifiable, Equatable {
    let id: UUID
    let rect: CGRect
    let color: String // 十六进制颜色值
    let lineWidth: CGFloat
    let isFilled: Bool
    let zIndex: Int
    let createdAt: Date
    
    /// 计算属性：frame（兼容性）
    var frame: CGRect {
        return rect
    }
    
    /// 创建矩形图层
    init(rect: CGRect, color: String = "#000000", lineWidth: CGFloat = 3, isFilled: Bool = false, zIndex: Int = 0) {
        self.id = UUID()
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
        self.isFilled = isFilled
        self.zIndex = zIndex
        self.createdAt = Date()
    }
    
    /// 内部初始化方法（用于更新时保持ID）
    private init(
        id: UUID,
        rect: CGRect,
        color: String,
        lineWidth: CGFloat,
        isFilled: Bool,
        zIndex: Int,
        createdAt: Date
    ) {
        self.id = id
        self.rect = rect
        self.color = color
        self.lineWidth = lineWidth
        self.isFilled = isFilled
        self.zIndex = zIndex
        self.createdAt = createdAt
    }
    
    /// 更新矩形属性
    func updated(rect: CGRect? = nil, color: String? = nil, lineWidth: CGFloat? = nil, isFilled: Bool? = nil, zIndex: Int? = nil) -> RectangleLayerNode {
        return RectangleLayerNode(
            id: self.id,  // 保持原有ID不变
            rect: rect ?? self.rect,
            color: color ?? self.color,
            lineWidth: lineWidth ?? self.lineWidth,
            isFilled: isFilled ?? self.isFilled,
            zIndex: zIndex ?? self.zIndex,
            createdAt: self.createdAt  // 保持创建时间不变
        )
    }
}

/// 矩形图层管理器
/// 管理画布上的所有矩形图层
class RectangleLayerManager: ObservableObject {
    @Published var rectangles: [RectangleLayerNode] = []
    
    /// 添加矩形
    func addRectangle(_ rectangle: RectangleLayerNode) {
        rectangles.append(rectangle)
        sortByZIndex()
    }
    
    /// 移除矩形
    func removeRectangle(id: UUID) {
        rectangles.removeAll { $0.id == id }
    }
    
    /// 更新矩形
    func updateRectangle(_ rectangle: RectangleLayerNode) {
        if let index = rectangles.firstIndex(where: { $0.id == rectangle.id }) {
            rectangles[index] = rectangle
            sortByZIndex()
        }
    }
    
    /// 按 Z-Index 排序
    private func sortByZIndex() {
        rectangles.sort { $0.zIndex < $1.zIndex }
    }
    
    /// 获取下一个可用的 Z-Index
    func getNextZIndex() -> Int {
        return (rectangles.map(\.zIndex).max() ?? 0) + 1
    }
    
    /// 清空所有矩形
    func clearAll() {
        rectangles.removeAll()
    }
}