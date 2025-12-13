import SwiftUI

enum Theme {
    
    // MARK: - 色彩系统 (Color Palette)
    
    enum Colors {
        // 主品牌色
        static let accent = Color("AccentColor")
        static let brandBlue = Color.fromHex("#007AFF") ?? Color.blue
        
        // 背景色
        static let appBackground = Color(uiColor: .systemGroupedBackground)
        static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
        
        // 文本色
        static let primaryText = Color.primary
        static let secondaryText = Color.secondary
        static let placeholderText = Color(uiColor: .placeholderText)
        
        // 功能色
        static let destructive = Color.red
        static let success = Color.green
        static let warning = Color.orange
        
        // 渐变金色（用于高级功能）
        static let goldGradient = LinearGradient(
            colors: [Color.fromHex("#FFD700") ?? Color.yellow, Color.fromHex("#FFA500") ?? Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - 形状与质感 (Shapes & Materials)
    
    enum Shapes {
        // 圆角
        static let buttonCornerRadius: CGFloat = 12
        static let cardCornerRadius: CGFloat = 16
        static let largeCardCornerRadius: CGFloat = 20
        
        // 阴影
        static func cardShadow() -> some View {
            return EmptyView().shadow(
                color: Color.black.opacity(0.08),
                radius: 8,
                x: 0,
                y: 4
            )
        }
    }
    
    // MARK: - 间距系统 (Spacing)
    
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    
    // MARK: - 尺寸系统 (Sizes)
    
    enum Sizes {
        // 按钮
        static let buttonHeight: CGFloat = 50
        static let iconButtonSize: CGFloat = 44
        
        // 头像
        static let avatarSmall: CGFloat = 32
        static let avatarMedium: CGFloat = 48
        static let avatarLarge: CGFloat = 80
        
        // 缩略图
        static let thumbnailSmall: CGFloat = 60
        static let thumbnailMedium: CGFloat = 100
        static let thumbnailLarge: CGFloat = 150
        
        // 最大宽度
        static let maxContentWidth: CGFloat = 360
    }
    
    // MARK: - 字体系统 (Typography)
    
    enum Fonts {
        // 标题
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.bold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.semibold)
        
        // 正文
        static let headline = Font.headline
        static let subheadline = Font.subheadline
        static let body = Font.body
        static let bodyBold = Font.body.weight(.semibold)
        static let callout = Font.callout
        static let caption = Font.caption
        static let caption2 = Font.caption2
        
        // 特殊字体
        static let monospaced = Font.system(.body, design: .monospaced)
        static let monospacedSmall = Font.system(.caption, design: .monospaced)
    }
    
    // MARK: - 图标系统 (Icons)
    
    enum Icons {
        // 导航
        static let creations = "paintbrush"
        static let creationsFill = "paintbrush.fill"
        static let mindStream = "sparkles"
        static let mindStreamFill = "sparkles"
        static let subscription = "crown"
        static let subscriptionFill = "crown.fill"
        static let settings = "gearshape"
        static let settingsFill = "gearshape.fill"
        
        // 操作
        static let add = "plus.circle.fill"
        static let download = "arrow.down.circle"
        static let publish = "globe"
        static let delete = "trash"
        static let edit = "pencil"
        static let close = "xmark"
        static let back = "chevron.left"
        
        // 功能
        static let like = "heart"
        static let likeFill = "heart.fill"
        static let remix = "arrow.triangle.2.circlepath"
        static let photo = "photo"
        static let camera = "camera"
        static let checkmark = "checkmark"
    }
}

// MARK: - Color Extension (Hex Support)

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Extensions (便捷修饰符)

extension View {
    func cardStyle() -> some View {
        self
            .background(Theme.Colors.cardBackground)
            .cornerRadius(Theme.Shapes.cardCornerRadius)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    func primaryButtonStyle() -> some View {
        self
            .frame(height: Theme.Sizes.buttonHeight)
            .background(Theme.Colors.brandBlue)
            .foregroundColor(.white)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            .font(Theme.Fonts.bodyBold)
    }
    
    func secondaryButtonStyle() -> some View {
        self
            .frame(height: Theme.Sizes.buttonHeight)
            .background(Theme.Colors.cardBackground)
            .foregroundColor(Theme.Colors.brandBlue)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .stroke(Theme.Colors.brandBlue.opacity(0.3), lineWidth: 1)
            )
            .font(Theme.Fonts.bodyBold)
    }
}

