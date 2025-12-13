import Foundation
import CoreGraphics
import Combine

/// 文字图层节点
/// 表示画布上的一个文字对象
struct TextLayerNode: Codable, Identifiable {
    let id: UUID
    let position: CGPoint
    let text: String
    let fontSize: CGFloat
    let color: String // 十六进制颜色值
    let fontName: String?
    let zIndex: Int
    let createdAt: Date
    
    /// 计算文字的边界框（估算）
    var bounds: CGRect {
        // 这里使用简单的估算，实际应用中可能需要使用 NSString 的 boundingRect
        let estimatedWidth = CGFloat(text.count) * fontSize * 0.6
        let estimatedHeight = fontSize * 1.2
        
        return CGRect(
            x: position.x - estimatedWidth / 2,
            y: position.y - estimatedHeight / 2,
            width: estimatedWidth,
            height: estimatedHeight
        )
    }
    
    /// 创建文字图层
    init(
        position: CGPoint,
        text: String,
        fontSize: CGFloat = 16,
        color: String = "#000000",
        fontName: String? = nil,
        zIndex: Int = 0
    ) {
        self.id = UUID()
        self.position = position
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.fontName = fontName
        self.zIndex = zIndex
        self.createdAt = Date()
    }
    
    /// 更新文字属性
    func updated(
        position: CGPoint? = nil,
        text: String? = nil,
        fontSize: CGFloat? = nil,
        color: String? = nil,
        fontName: String? = nil,
        zIndex: Int? = nil
    ) -> TextLayerNode {
        TextLayerNode(
            position: position ?? self.position,
            text: text ?? self.text,
            fontSize: fontSize ?? self.fontSize,
            color: color ?? self.color,
            fontName: fontName ?? self.fontName,
            zIndex: zIndex ?? self.zIndex
        )
    }
}

/// 文字图层管理器
/// 管理画布上的所有文字图层
class TextLayerManager: ObservableObject {
    @Published var textLayers: [TextLayerNode] = []
    
    /// 添加文字
    func addText(_ text: TextLayerNode) {
        textLayers.append(text)
        sortByZIndex()
    }
    
    /// 移除文字
    func removeText(id: UUID) {
        textLayers.removeAll { $0.id == id }
    }
    
    /// 更新文字
    func updateText(_ text: TextLayerNode) {
        if let index = textLayers.firstIndex(where: { $0.id == text.id }) {
            textLayers[index] = text
            sortByZIndex()
        }
    }
    
    /// 按 Z-Index 排序
    private func sortByZIndex() {
        textLayers.sort { $0.zIndex < $1.zIndex }
    }
    
    /// 获取下一个可用的 Z-Index
    func getNextZIndex() -> Int {
        return (textLayers.map(\.zIndex).max() ?? 0) + 1
    }
    
    /// 清空所有文字
    func clearAll() {
        textLayers.removeAll()
    }
}