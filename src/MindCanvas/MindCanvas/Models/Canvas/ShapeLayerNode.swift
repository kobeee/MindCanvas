import Foundation
import CoreGraphics
import Combine

/// 通用形状图层节点
struct ShapeLayerNode: Codable, Identifiable {
    let id: UUID
    var frame: CGRect           // 位置和尺寸
    var rotation: Double        // 旋转角度（弧度）
    let shapeType: ShapeType    // 形状类型
    let color: String           // 填充/描边颜色
    let lineWidth: CGFloat      // 描边宽度
    let isFilled: Bool          // 是否填充
    let zIndex: Int
    let createdAt: Date

    /// 形状中心点
    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    /// 创建形状图层
    init(
        frame: CGRect,
        shapeType: ShapeType,
        color: String = "#000000",
        lineWidth: CGFloat = 2,
        isFilled: Bool = false,
        rotation: Double = 0,
        zIndex: Int = 0
    ) {
        self.id = UUID()
        self.frame = frame
        self.rotation = rotation
        self.shapeType = shapeType
        self.color = color
        self.lineWidth = lineWidth
        self.isFilled = isFilled
        self.zIndex = zIndex
        self.createdAt = Date()
    }

    /// 更新形状属性
    func updated(
        frame: CGRect? = nil,
        rotation: Double? = nil,
        color: String? = nil,
        lineWidth: CGFloat? = nil,
        isFilled: Bool? = nil,
        zIndex: Int? = nil
    ) -> ShapeLayerNode {
        var node = self
        if let frame = frame { node.frame = frame }
        if let rotation = rotation { node.rotation = rotation }
        // 其他属性由于是 let，需要创建新实例
        return ShapeLayerNode(
            frame: node.frame,
            shapeType: node.shapeType,
            color: color ?? node.color,
            lineWidth: lineWidth ?? node.lineWidth,
            isFilled: isFilled ?? node.isFilled,
            rotation: node.rotation,
            zIndex: zIndex ?? node.zIndex
        )
    }
}

/// 形状图层管理器
class ShapeLayerManager: ObservableObject {
    @Published var shapes: [ShapeLayerNode] = []

    func addShape(_ shape: ShapeLayerNode) {
        shapes.append(shape)
        sortByZIndex()
    }

    func removeShape(id: UUID) {
        shapes.removeAll { $0.id == id }
    }

    func updateShape(_ shape: ShapeLayerNode) {
        if let index = shapes.firstIndex(where: { $0.id == shape.id }) {
            shapes[index] = shape
            sortByZIndex()
        }
    }

    private func sortByZIndex() {
        shapes.sort { $0.zIndex < $1.zIndex }
    }

    func getNextZIndex() -> Int {
        (shapes.map(\.zIndex).max() ?? 0) + 1
    }

    func clearAll() {
        shapes.removeAll()
    }
}