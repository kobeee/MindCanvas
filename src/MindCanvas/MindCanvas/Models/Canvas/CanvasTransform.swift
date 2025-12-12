import Foundation
import CoreGraphics

/// 画布变换状态 (缩放和偏移)
struct CanvasTransform: Codable, Equatable {
    /// 缩放比例 (1.0 = 100%)
    var scale: CGFloat
    
    /// 偏移量 (相对于初始位置)
    var offset: CGPoint
    
    // MARK: - 初始化
    
    init(scale: CGFloat = 1.0, offset: CGPoint = .zero) {
        self.scale = scale
        self.offset = offset
    }
    
    // MARK: - 预设
    
    /// 默认变换 (无缩放、无偏移)
    static let identity = CanvasTransform()
    
    /// 重置到初始状态
    mutating func reset() {
        scale = 1.0
        offset = .zero
    }
    
    /// 是否为初始状态
    var isIdentity: Bool {
        scale == 1.0 && offset == .zero
    }
}

