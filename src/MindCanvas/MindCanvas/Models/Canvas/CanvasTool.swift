import Foundation

/// 画布工具枚举
/// 参考 Figma/Canva 的工具切换架构，每个工具独占手势
enum CanvasTool: String, CaseIterable, Identifiable {
    case select = "select"          // 选择工具
    case pan = "pan"                // 平移工具
    case pen = "pen"                // 画笔工具
    case eraser = "eraser"          // 橡皮擦
    case arrow = "arrow"            // 箭头工具（预留）
    case text = "text"              // 文字工具（预留）
    case annotation = "annotation"  // 标注工具（预留）
    case image = "image"            // 图片工具
    case rectangle = "rectangle"    // 矩形工具（预留）
    
    var id: String { rawValue }
    
    /// SF Symbol 图标名
    var iconName: String {
        switch self {
        case .select:
            return "arrow.up.left.and.arrow.down.right"
        case .pan:
            return "hand.raised"
        case .pen:
            return "paintbrush.pointed"
        case .eraser:
            return "eraser"
        case .arrow:
            return "arrow.up.right"
        case .text:
            return "textformat"
        case .annotation:
            return "bubble.left"
        case .image:
            return "photo"
        case .rectangle:
            return "rectangle"
        }
    }
    
    /// 显示名称
    var displayName: String {
        switch self {
        case .select:
            return "选择"
        case .pan:
            return "平移"
        case .pen:
            return "画笔"
        case .eraser:
            return "橡皮擦"
        case .arrow:
            return "箭头"
        case .text:
            return "文字"
        case .annotation:
            return "标注"
        case .image:
            return "图片"
        case .rectangle:
            return "矩形"
        }
    }
    
    /// 快捷键（预留）
    var shortcut: String? {
        switch self {
        case .select: return "V"
        case .pan: return "H"
        case .pen: return "B"
        case .eraser: return "E"
        case .arrow: return "L"
        case .text: return "T"
        case .annotation: return "C"
        case .image: return "I"
        case .rectangle: return "R"
        }
    }
    
    /// 是否在主工具栏显示（过滤预留工具）
    var isMainToolbarTool: Bool {
        switch self {
        case .select, .pan, .pen, .eraser, .rectangle, .image, .text:
            return true
        case .arrow:  // arrow 作为 rectangle 的子类型，不独立显示
            return false
        case .annotation:  // 功能未完整实现，暂不显示
            return false
        }
    }
    
    /// 获取主工具栏显示的工具
    static var mainToolbarTools: [CanvasTool] {
        allCases.filter(\.isMainToolbarTool)
    }
}

