import Foundation

/// 形状类型枚举
enum ShapeType: String, CaseIterable, Identifiable, Codable {
    case rectangle = "rectangle"
    case roundedRectangle = "roundedRectangle"
    case circle = "circle"
    case triangle = "triangle"
    case pentagon = "pentagon"
    case diamond = "diamond"
    case star = "star"
    case hexagon = "hexagon"
    case line = "line"
    case arrow = "arrow"

    var id: String { rawValue }

    /// SF Symbol 图标名
    var iconName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .roundedRectangle: return "rectangle.inset.filled"
        case .circle: return "circle"
        case .triangle: return "triangle"
        case .pentagon: return "pentagon"
        case .diamond: return "diamond"
        case .star: return "star"
        case .hexagon: return "hexagon"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.right"
        }
    }

    /// 显示名称
    var displayName: String {
        switch self {
        case .rectangle: return "矩形"
        case .roundedRectangle: return "圆角矩形"
        case .circle: return "圆形"
        case .triangle: return "三角形"
        case .pentagon: return "五边形"
        case .diamond: return "菱形"
        case .star: return "五角星"
        case .hexagon: return "六边形"
        case .line: return "直线"
        case .arrow: return "箭头"
        }
    }

    /// 是否为线条类型
    var isLineType: Bool {
        self == .line || self == .arrow
    }

    /// 弹出菜单显示的所有形状
    static var popoverShapes: [ShapeType] {
        [.line, .arrow, .rectangle, .roundedRectangle, .circle, .triangle, .diamond, .star, .hexagon]
    }

    /// 主选择器显示的形状
    static var primaryShapes: [ShapeType] {
        [.rectangle, .circle, .triangle]
    }

    /// 所有可用形状
    static var allShapes: [ShapeType] {
        allCases
    }
}