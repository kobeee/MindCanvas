import Foundation
import CoreGraphics
import UIKit

/// 文字图层节点
/// 表示画布上的一个文字对象
struct TextLayerNode: Codable, Identifiable {
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