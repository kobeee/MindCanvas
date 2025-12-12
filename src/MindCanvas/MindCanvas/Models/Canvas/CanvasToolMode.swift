import Foundation

/// 画布工具模式
enum CanvasToolMode: String, CaseIterable, Identifiable {
    case objectMode     // 对象操作模式 (移动、缩放图片)
    case drawingMode    // 绘图模式 (Apple Pencil 绘图)
    
    var id: String { rawValue }
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .objectMode:
            return "对象模式"
        case .drawingMode:
            return "绘图模式"
        }
    }
    
    /// 图标名称
    var iconName: String {
        switch self {
        case .objectMode:
            return "hand.point.up.left.fill"
        case .drawingMode:
            return "pencil.tip"
        }
    }
    
    /// 简短描述
    var description: String {
        switch self {
        case .objectMode:
            return "拖拽和调整图片"
        case .drawingMode:
            return "使用 Apple Pencil 绘图"
        }
    }
}

