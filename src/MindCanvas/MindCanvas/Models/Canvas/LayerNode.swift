import Foundation
import CoreGraphics

/// 图层节点类型
enum NodeType: String, Codable {
    case userImage      // 用户上传的图片
    case aiGenerated    // AI 生成的图片
}

/// 图层节点模型 - 代表画布上的一个可操控图片对象
struct LayerNode: Identifiable, Codable {
    /// 唯一标识符
    let id: UUID
    
    /// 节点类型
    var type: NodeType
    
    /// 图片 URL (本地或远程)
    var url: String?
    
    /// 位置和尺寸 (相对于画布坐标系)
    var frame: CGRect
    
    /// 旋转角度 (弧度)
    var rotation: Double
    
    /// 是否锁定 (锁定后不可移动/缩放)
    var isLocked: Bool
    
    /// 渲染顺序 (Z-Index，数值越大越靠上)
    var zIndex: Int
    
    /// 透明度 (0.0 - 1.0)
    var opacity: Double
    
    /// 创建时间
    var createdAt: Date
    
    // MARK: - 初始化
    
    init(
        id: UUID = UUID(),
        type: NodeType,
        url: String? = nil,
        frame: CGRect = CGRect(x: 0, y: 0, width: 200, height: 200),
        rotation: Double = 0,
        isLocked: Bool = false,
        zIndex: Int = 0,
        opacity: Double = 1.0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.frame = frame
        self.rotation = rotation
        self.isLocked = isLocked
        self.zIndex = zIndex
        self.opacity = opacity
        self.createdAt = createdAt
    }
    
    // MARK: - 便捷方法
    
    /// 中心点
    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }
    
    /// 是否为 AI 生成的图片
    var isAIGenerated: Bool {
        type == .aiGenerated
    }
    
    /// 创建用户上传图片节点
    static func userImage(url: String, at position: CGPoint, size: CGSize) -> LayerNode {
        LayerNode(
            type: .userImage,
            url: url,
            frame: CGRect(origin: position, size: size)
        )
    }
    
    /// 创建 AI 生成图片节点
    static func aiGenerated(url: String, frame: CGRect, zIndex: Int) -> LayerNode {
        LayerNode(
            type: .aiGenerated,
            url: url,
            frame: frame,
            zIndex: zIndex
        )
    }
}

// MARK: - Hashable

extension LayerNode: Hashable {
    static func == (lhs: LayerNode, rhs: LayerNode) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - CGRect Codable Extension

extension CGRect: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        let width = try container.decode(CGFloat.self, forKey: .width)
        let height = try container.decode(CGFloat.self, forKey: .height)
        self.init(x: x, y: y, width: width, height: height)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin.x, forKey: .x)
        try container.encode(origin.y, forKey: .y)
        try container.encode(size.width, forKey: .width)
        try container.encode(size.height, forKey: .height)
    }
}

// MARK: - CGPoint Codable Extension

extension CGPoint: @retroactive Codable {
    enum CodingKeys: String, CodingKey {
        case x, y
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        self.init(x: x, y: y)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
    }
}
