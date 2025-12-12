import Foundation

enum GenerationMode: String, Codable {
    case img2img
    case txt2img
}

enum ImageAspectRatio: String, CaseIterable, Identifiable, Codable {
    case square = "1:1"
    case landscape = "16:9"
    case portrait = "9:16"
    case standard = "4:3"
    case standardPortrait = "3:4"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .square: return "正方"
        case .landscape: return "横版"
        case .portrait: return "竖版"
        case .standard: return "标准横"
        case .standardPortrait: return "标准竖"
        }
    }
}


