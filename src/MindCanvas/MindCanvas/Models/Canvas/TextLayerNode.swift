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
        let font = UIFont(name: fontName, size: fontSize * scale)
            ?? UIFont.systemFont(ofSize: fontSize * scale)

        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let nsString = text as NSString
        let size = nsString.boundingRect(
            with: CGSize(width: CGFloat.infinity, height: CGFloat.infinity),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        ).size

        return CGRect(
            x: position.x - size.width / 2,
            y: position.y - size.height / 2,
            width: size.width,
            height: size.height
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
@Observable
@MainActor
final class TextLayerManager {
    // MARK: - Properties
    
    /// 文字图层数组，按zIndex排序
    private(set) var texts: [TextLayerNode] = []
    
    /// 用于线程安全的私有队列
    private let accessQueue = DispatchQueue(label: "com.mindcanvas.textlayermanager", qos: .userInitiated)
    
    // MARK: - Initialization
    
    /// 初始化文字图层管理器
    init() {
        // 初始化时为空
    }
    
    // MARK: - CRUD Operations
    
    /// 添加文字图层
    /// - Parameter text: 要添加的文字图层
    /// - Note: 内部自动处理zIndex排序，线程安全
    func addText(_ text: TextLayerNode) {
        accessQueue.async { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.texts.append(text)
                self.sortByZIndex()
            }
        }
    }
    
    /// 移除指定ID的文字图层
    /// - Parameter id: 要移除的文字图层ID
    /// - Returns: 是否成功移除
    /// - Note: 线程安全操作
    func removeText(id: UUID) -> Bool {
        return accessQueue.sync {
            let initialCount = texts.count
            texts.removeAll { $0.id == id }
            let removed = texts.count < initialCount
            
            if removed {
                Task { @MainActor in
                    self.sortByZIndex()
                }
            }
            
            return removed
        }
    }
    
    /// 更新文字图层
    /// - Parameter text: 更新后的文字图层
    /// - Returns: 是否成功更新
    /// - Note: 如果图层不存在则返回false，线程安全操作
    func updateText(_ text: TextLayerNode) -> Bool {
        return accessQueue.sync {
            guard let index = texts.firstIndex(where: { $0.id == text.id }) else {
                return false
            }
            
            texts[index] = text
            
            Task { @MainActor in
                self.sortByZIndex()
            }
            
            return true
        }
    }
    
    /// 获取指定ID的文字图层
    /// - Parameter id: 文字图层ID
    /// - Returns: 对应的文字图层，如果不存在则返回nil
    /// - Note: 线程安全读取操作
    func getText(id: UUID) -> TextLayerNode? {
        return accessQueue.sync {
            return texts.first { $0.id == id }
        }
    }
    
    /// 获取所有文字图层
    /// - Returns: 文字图层数组的副本（按zIndex排序）
    /// - Note: 返回副本以避免外部修改，线程安全操作
    func getAllTexts() -> [TextLayerNode] {
        return accessQueue.sync {
            return texts.sorted { $0.zIndex < $1.zIndex }
        }
    }
    
    /// 检查指定ID的文字图层是否存在
    /// - Parameter id: 文字图层ID
    /// - Returns: 是否存在
    /// - Note: 线程安全操作
    func containsText(id: UUID) -> Bool {
        return accessQueue.sync {
            return texts.contains { $0.id == id }
        }
    }
    
    // MARK: - Z-Index Management
    
    /// 获取下一个可用的zIndex值
    /// - Returns: 下一个可用的zIndex
    /// - Note: 线程安全操作
    func getNextZIndex() -> Int {
        return accessQueue.sync {
            return (texts.map(\.zIndex).max() ?? 0) + 1
        }
    }
    
    /// 将指定文字图层移动到最前面
    /// - Parameter id: 文字图层ID
    /// - Returns: 是否成功移动
    /// - Note: 线程安全操作
    func bringToFront(id: UUID) -> Bool {
        return accessQueue.sync {
            guard let index = texts.firstIndex(where: { $0.id == id }) else {
                return false
            }
            
            let maxZIndex = getNextZIndex()
            texts[index] = texts[index].updated(zIndex: maxZIndex)
            
            Task { @MainActor in
                self.sortByZIndex()
            }
            
            return true
        }
    }
    
    /// 将指定文字图层移动到最后面
    /// - Parameter id: 文字图层ID
    /// - Returns: 是否成功移动
    /// - Note: 线程安全操作
    func sendToBack(id: UUID) -> Bool {
        return accessQueue.sync {
            guard let index = texts.firstIndex(where: { $0.id == id }) else {
                return false
            }
            
            let minZIndex = (texts.map(\.zIndex).min() ?? 0) - 1
            texts[index] = texts[index].updated(zIndex: minZIndex)
            
            Task { @MainActor in
                self.sortByZIndex()
            }
            
            return true
        }
    }
    
    // MARK: - Batch Operations
    
    /// 清空所有文字图层
    /// - Note: 线程安全操作，不可逆
    func clearAll() {
        accessQueue.async { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.texts.removeAll()
            }
        }
    }
    
    /// 批量添加文字图层
    /// - Parameter texts: 要添加的文字图层数组
    /// - Note: 原子操作，要么全部成功要么全部失败，线程安全
    func addTexts(_ texts: [TextLayerNode]) {
        accessQueue.async { [weak self] in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.texts.append(contentsOf: texts)
                self.sortByZIndex()
            }
        }
    }
    
    /// 批量移除文字图层
    /// - Parameter ids: 要移除的文字图层ID数组
    /// - Returns: 成功移除的数量
    /// - Note: 线程安全操作
    func removeTexts(ids: [UUID]) -> Int {
        return accessQueue.sync {
            let initialCount = texts.count
            texts.removeAll { ids.contains($0.id) }
            let removedCount = initialCount - texts.count
            
            if removedCount > 0 {
                Task { @MainActor in
                    self.sortByZIndex()
                }
            }
            
            return removedCount
        }
    }
    
    // MARK: - Search and Filter
    
    /// 根据文本内容搜索文字图层
    /// - Parameter searchText: 搜索文本
    /// - Parameter caseSensitive: 是否区分大小写，默认为false
    /// - Returns: 匹配的文字图层数组
    /// - Note: 线程安全操作
    func searchTexts(containing searchText: String, caseSensitive: Bool = false) -> [TextLayerNode] {
        return accessQueue.sync {
            let comparator = caseSensitive 
                ? { (text: TextLayerNode, search: String) in text.text.contains(search) }
                : { (text: TextLayerNode, search: String) in text.text.localizedCaseInsensitiveContains(search) }
            
            return texts.filter { comparator($0, searchText) }
        }
    }
    
    /// 获取指定矩形区域内的文字图层
    /// - Parameter rect: 搜索区域
    /// - Returns: 在区域内的文字图层数组
    /// - Note: 线程安全操作
    func getTexts(in rect: CGRect) -> [TextLayerNode] {
        return accessQueue.sync {
            return texts.filter { $0.bounds.intersects(rect) }
        }
    }
    
    // MARK: - Statistics
    
    /// 获取文字图层数量
    /// - Returns: 文字图层的总数
    /// - Note: 线程安全操作
    func getCount() -> Int {
        return accessQueue.sync {
            return texts.count
        }
    }
    
    /// 检查是否为空
    /// - Returns: 是否没有文字图层
    /// - Note: 线程安全操作
    func isEmpty() -> Bool {
        return accessQueue.sync {
            return texts.isEmpty
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// 按zIndex排序文字图层
    /// - Note: 仅在主线程调用
    private func sortByZIndex() {
        texts.sort { $0.zIndex < $1.zIndex }
    }
    
    /// 验证文字图层数据完整性
    /// - Parameter text: 要验证的文字图层
    /// - Returns: 是否有效
    /// - Note: 检查必要字段的有效性
    private func validateTextLayer(_ text: TextLayerNode) -> Bool {
        return !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               text.fontSize > 0 &&
               text.scale > 0
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