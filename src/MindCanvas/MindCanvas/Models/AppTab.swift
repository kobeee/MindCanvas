import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case creations
    case mindStream
    case subscription
    case settings
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .creations: "我的创作"
        case .mindStream: "MindStream"
        case .subscription: "订阅"
        case .settings: "设置"
        }
    }
    
    var icon: String {
        switch self {
        case .creations: "paintbrush.fill"
        case .mindStream: "water.waves"
        case .subscription: "crown.fill"
        case .settings: "gearshape.fill"
        }
    }
}

