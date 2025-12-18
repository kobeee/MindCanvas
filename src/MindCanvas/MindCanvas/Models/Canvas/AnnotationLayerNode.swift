import Foundation
import CoreGraphics
import Combine

/// 标注图层节点
/// 表示画布上的一个标注对象（包含矩形框和文字）
struct AnnotationLayerNode: Codable, Identifiable {
    let id: UUID
    let rect: CGRect
    let text: String
    let fontSize: CGFloat
    let color: String // 十六进制颜色值
    let lineWidth: CGFloat
    let zIndex: Int
    let createdAt: Date
    
    /// 创建标注图层
    init(
        rect: CGRect,
        text: String,
        fontSize: CGFloat = 14,
        color: String = "#007AFF",
        lineWidth: CGFloat = 2,
        zIndex: Int = 0
    ) {
        self.id = UUID()
        self.rect = rect
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.lineWidth = lineWidth
        self.zIndex = zIndex
        self.createdAt = Date()
    }
    
    /// 内部初始化方法（用于更新时保持ID）
    private init(
        id: UUID,
        rect: CGRect,
        text: String,
        fontSize: CGFloat,
        color: String,
        lineWidth: CGFloat,
        zIndex: Int,
        createdAt: Date
    ) {
        self.id = id
        self.rect = rect
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.lineWidth = lineWidth
        self.zIndex = zIndex
        self.createdAt = createdAt
    }
    
    /// 更新标注属性
    func updated(
        rect: CGRect? = nil,
        text: String? = nil,
        fontSize: CGFloat? = nil,
        color: String? = nil,
        lineWidth: CGFloat? = nil,
        zIndex: Int? = nil
    ) -> AnnotationLayerNode {
        return AnnotationLayerNode(
            id: self.id,  // 保持原有ID不变
            rect: rect ?? self.rect,
            text: text ?? self.text,
            fontSize: fontSize ?? self.fontSize,
            color: color ?? self.color,
            lineWidth: lineWidth ?? self.lineWidth,
            zIndex: zIndex ?? self.zIndex,
            createdAt: self.createdAt  // 保持创建时间不变
        )
    }
    
    /// 获取文字位置（在矩形框下方）
    var textPosition: CGPoint {
        CGPoint(
            x: rect.midX,
            y: rect.maxY + fontSize + 5
        )
    }
}

/// 标注图层管理器
/// 管理画布上的所有标注图层
class AnnotationLayerManager: ObservableObject {
    @Published var annotations: [AnnotationLayerNode] = []
    
    /// 添加标注
    func addAnnotation(_ annotation: AnnotationLayerNode) {
        annotations.append(annotation)
        sortByZIndex()
    }
    
    /// 移除标注
    func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
    }
    
    /// 更新标注
    func updateAnnotation(_ annotation: AnnotationLayerNode) {
        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[index] = annotation
            sortByZIndex()
        }
    }
    
    /// 按 Z-Index 排序
    private func sortByZIndex() {
        annotations.sort { $0.zIndex < $1.zIndex }
    }
    
    /// 获取下一个可用的 Z-Index
    func getNextZIndex() -> Int {
        return (annotations.map(\.zIndex).max() ?? 0) + 1
    }
    
    /// 清空所有标注
    func clearAll() {
        annotations.removeAll()
    }
}