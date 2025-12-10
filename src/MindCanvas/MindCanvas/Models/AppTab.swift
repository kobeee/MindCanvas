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
        case .creations: Theme.Icons.creations
        case .mindStream: Theme.Icons.mindStream
        case .subscription: Theme.Icons.subscription
        case .settings: Theme.Icons.settings
        }
    }
    
    var iconFill: String {
        switch self {
        case .creations: Theme.Icons.creationsFill
        case .mindStream: Theme.Icons.mindStreamFill
        case .subscription: Theme.Icons.subscriptionFill
        case .settings: Theme.Icons.settingsFill
        }
    }
}

