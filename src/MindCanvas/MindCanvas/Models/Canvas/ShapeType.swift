import Foundation

/// 形状类型枚举
enum ShapeType: String, CaseIterable, Identifiable, Codable {
    case rectangle = "rectangle"
    case circle = "circle"
    case triangle = "triangle"
    case diamond = "diamond"      // 菱形
    case star = "star"            // 五角星
    case hexagon = "hexagon"      // 六边形

    var id: String { rawValue }

    /// SF Symbol 图标名
    var iconName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .circle: return "circle"
        case .triangle: return "triangle"
        case .diamond: return "diamond"
        case .star: return "star"
        case .hexagon: return "hexagon"
        }
    }

    /// 显示名称
    var displayName: String {
        switch self {
        case .rectangle: return "矩形"
        case .circle: return "圆形"
        case .triangle: return "三角形"
        case .diamond: return "菱形"
        case .star: return "五角星"
        case .hexagon: return "六边形"
        }
    }

    /// 主选择器显示的形状（第一批支持）
    static var primaryShapes: [ShapeType] {
        [.rectangle, .circle, .triangle]
    }

    /// 所有可用形状
    static var allShapes: [ShapeType] {
        allCases
    }
}