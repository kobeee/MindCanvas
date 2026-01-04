import Foundation
import CoreGraphics
import UIKit
import Observation

/// 文字图层节点
/// 表示画布上的一个文字对象
struct TextLayerNode: Codable, Identifiable, Equatable {
    let id: UUID
    var position: CGPoint
    var text: String
    var fontSize: CGFloat
    var color: String
    var fontName: String
    var rotation: CGFloat
    var scale: CGFloat
    let zIndex: Int
    let createdAt: Date
    
    /// 计算精确的边界框
    var bounds: CGRect {
        // 使用占位符计算尺寸（确保空文字时也有有效尺寸）
        let displayText = text.isEmpty ? "输入文字" : text
        let nsString = displayText as NSString

        let font = UIFont(name: fontName, size: fontSize * scale)
            ?? UIFont.systemFont(ofSize: fontSize * scale)

        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        var size = nsString.boundingRect(
            with: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude), // 限制最大宽度
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).size

        // 添加padding
        size.width += 24
        size.height += 16

        // 确保最小尺寸
        let minWidth: CGFloat = 80
        let minHeight: CGFloat = 44
        let finalWidth = max(size.width, minWidth)
        let finalHeight = max(size.height, minHeight)

        return CGRect(
            x: position.x - finalWidth / 2,
            y: position.y - finalHeight / 2,
            width: finalWidth,
            height: finalHeight
        )
    }
    
    /// 创建文字图层
    init(
        position: CGPoint,
        text: String,
        fontSize: CGFloat = 24,
        color: String = "#000000",
        fontName: String = ".SF Pro Display",
        rotation: CGFloat = 0,
        scale: CGFloat = 1.0,
        zIndex: Int = 0
    ) {
        self.id = UUID()
        self.position = position
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.fontName = fontName
        self.rotation = rotation
        self.scale = scale
        self.zIndex = zIndex
        self.createdAt = Date()
    }
    
    /// 内部初始化方法（用于更新时保持ID）
    private init(
        id: UUID,
        position: CGPoint,
        text: String,
        fontSize: CGFloat,
        color: String,
        fontName: String,
        rotation: CGFloat,
        scale: CGFloat,
        zIndex: Int,
        createdAt: Date
    ) {
        self.id = id
        self.position = position
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.fontName = fontName
        self.rotation = rotation
        self.scale = scale
        self.zIndex = zIndex
        self.createdAt = createdAt
    }
    
    /// 更新文字属性
    func updated(
        position: CGPoint? = nil,
        text: String? = nil,
        fontSize: CGFloat? = nil,
        color: String? = nil,
        fontName: String? = nil,
        rotation: CGFloat? = nil,
        scale: CGFloat? = nil
    ) -> TextLayerNode {
        return TextLayerNode(
            id: self.id,  // 保持原有ID不变
            position: position ?? self.position,
            text: text ?? self.text,
            fontSize: fontSize ?? self.fontSize,
            color: color ?? self.color,
            fontName: fontName ?? self.fontName,
            rotation: rotation ?? self.rotation,
            scale: scale ?? self.scale,
            zIndex: self.zIndex,
            createdAt: self.createdAt  // 保持创建时间不变
        )
    }
}

// MARK: - TextLayerManager

/// 文字图层管理器
/// 管理画布上的所有文字图层，提供完整的CRUD操作和状态管理
/// 重构：移除异步操作，确保数据同步
@Observable
@MainActor
final class TextLayerManager {
    // MARK: - Properties
    
    /// 文字图层数组，按zIndex排序
    private(set) var texts: [TextLayerNode] = []
    
    // MARK: - Initialization
    
    /// 初始化文字图层管理器
    init() {
        // 初始化时为空
    }
    
    // MARK: - CRUD Operations
    
    /// 添加文字图层（同步操作）
    func addText(_ text: TextLayerNode) {
        texts.append(text)
        sortByZIndex()
    }
    
    /// 移除指定ID的文字图层（同步操作）
    @discardableResult
    func removeText(id: UUID) -> Bool {
        let initialCount = texts.count
        texts.removeAll { $0.id == id }
        return texts.count < initialCount
    }
    
    /// 更新文字图层（同步操作）
    @discardableResult
    func updateText(_ text: TextLayerNode) -> Bool {
        guard let index = texts.firstIndex(where: { $0.id == text.id }) else {
            return false
        }
        texts[index] = text
        sortByZIndex()
        return true
    }
    
    /// 获取指定ID的文字图层
    func getText(id: UUID) -> TextLayerNode? {
        return texts.first { $0.id == id }
    }
    
    /// 获取所有文字图层
    func getAllTexts() -> [TextLayerNode] {
        return texts.sorted { $0.zIndex < $1.zIndex }
    }
    
    /// 检查指定ID的文字图层是否存在
    func containsText(id: UUID) -> Bool {
        return texts.contains { $0.id == id }
    }
    
    // MARK: - Z-Index Management
    
    /// 获取下一个可用的zIndex值
    func getNextZIndex() -> Int {
        return (texts.map(\.zIndex).max() ?? 0) + 1
    }
    
    /// 将指定文字图层移动到最前面
    @discardableResult
    func bringToFront(id: UUID) -> Bool {
        guard let index = texts.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let maxZIndex = getNextZIndex()
        texts[index] = texts[index].updated(zIndex: maxZIndex)
        sortByZIndex()
        return true
    }
    
    /// 将指定文字图层移动到最后面
    @discardableResult
    func sendToBack(id: UUID) -> Bool {
        guard let index = texts.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let minZIndex = (texts.map(\.zIndex).min() ?? 0) - 1
        texts[index] = texts[index].updated(zIndex: minZIndex)
        sortByZIndex()
        return true
    }
    
    // MARK: - Batch Operations
    
    /// 清空所有文字图层（同步操作）
    func clearAll() {
        texts.removeAll()
    }
    
    /// 批量添加文字图层（同步操作）
    func addTexts(_ newTexts: [TextLayerNode]) {
        texts.append(contentsOf: newTexts)
        sortByZIndex()
    }
    
    /// 批量移除文字图层
    @discardableResult
    func removeTexts(ids: [UUID]) -> Int {
        let initialCount = texts.count
        texts.removeAll { ids.contains($0.id) }
        return initialCount - texts.count
    }
    
    // MARK: - Search and Filter
    
    /// 根据文本内容搜索文字图层
    func searchTexts(containing searchText: String, caseSensitive: Bool = false) -> [TextLayerNode] {
        if caseSensitive {
            return texts.filter { $0.text.contains(searchText) }
        } else {
            return texts.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    /// 获取指定矩形区域内的文字图层
    func getTexts(in rect: CGRect) -> [TextLayerNode] {
        return texts.filter { $0.bounds.intersects(rect) }
    }
    
    // MARK: - Statistics
    
    /// 获取文字图层数量
    func getCount() -> Int {
        return texts.count
    }
    
    /// 检查是否为空
    func isEmpty() -> Bool {
        return texts.isEmpty
    }
    
    // MARK: - Private Helper Methods
    
    /// 按zIndex排序文字图层
    private func sortByZIndex() {
        texts.sort { $0.zIndex < $1.zIndex }
    }
}

// MARK: - TextLayerNode Extension for Manager

extension TextLayerNode {
    /// 便捷方法：创建用于管理器更新的副本（仅更新zIndex）
    /// - Parameter zIndex: 新的zIndex值
    /// - Returns: 更新后的TextLayerNode
    internal func updated(zIndex: Int) -> TextLayerNode {
        return TextLayerNode(
            id: self.id,
            position: self.position,
            text: self.text,
            fontSize: self.fontSize,
            color: self.color,
            fontName: self.fontName,
            rotation: self.rotation,
            scale: self.scale,
            zIndex: zIndex,
            createdAt: self.createdAt
        )
    }
}