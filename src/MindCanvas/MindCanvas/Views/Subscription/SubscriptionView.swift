import SwiftUI

struct SubscriptionView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var selectedPlan: SubscriptionPlan = .yearly
    
    var body: some View {
        NavigationStack {
            comingSoonView
                .background(Theme.Colors.appBackground)
                .navigationTitle("订阅 Pro")
        }
    }
    
    private var comingSoonView: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Theme.Colors.goldGradient.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Image(systemName: Theme.Icons.subscriptionFill)
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(Theme.Colors.goldGradient)
            }
            
            VStack(spacing: Theme.Spacing.md) {
                Text("敬请期待")
                    .font(Theme.Fonts.largeTitle)
                    .foregroundStyle(Theme.Colors.primaryText)
                
                Text("Pro 订阅功能即将上线")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 原有实现（暂时隐藏）
    
    @ViewBuilder
    private var originalSubscriptionContent: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xxxl) {
                headerSection
                featuresSection
                planSelector
                subscribeButton
                faqSection
            }
            .padding(Theme.Spacing.xxl)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.goldGradient)
                    .frame(width: 100, height: 100)
                
                Image(systemName: Theme.Icons.subscriptionFill)
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            Text("升级到 Pro")
                .font(Theme.Fonts.largeTitle)
            
            Text("解锁所有功能，释放无限创意")
                .font(Theme.Fonts.title3)
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Theme.Spacing.lg)
    }
    
    private var featuresSection: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md)
        ], spacing: Theme.Spacing.lg) {
            FeatureCard(icon: "sparkles", title: "无限生成", description: "AI 图像生成")
            FeatureCard(icon: "cloud.fill", title: "云端存储", description: "10GB 空间")
            FeatureCard(icon: "wand.and.stars", title: "高级模型", description: "最新功能")
            FeatureCard(icon: "person.2.fill", title: "优先支持", description: "客服优先")
            FeatureCard(icon: "arrow.down.circle.fill", title: "高清下载", description: "无水印导出")
            FeatureCard(icon: "star.fill", title: "专属徽章", description: "Pro 标识")
        }
    }
    
    private var planSelector: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ModernPlanCard(
                plan: .monthly,
                isSelected: selectedPlan == .monthly,
                onSelect: { selectedPlan = .monthly }
            )
            
            ModernPlanCard(
                plan: .yearly,
                isSelected: selectedPlan == .yearly,
                onSelect: { selectedPlan = .yearly }
            )
        }
    }
    
    private var subscribeButton: some View {
        Button {
            print("订阅: \(selectedPlan)")
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Text("立即订阅")
                    .font(Theme.Fonts.headline)
                
                Text("\(selectedPlan.price) / \(selectedPlan.period)")
                    .font(Theme.Fonts.caption)
                    .opacity(0.9)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Sizes.buttonHeight + 10)
            .background(Theme.Colors.goldGradient)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
        }
    }
    
    private var faqSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("常见问题")
                .font(Theme.Fonts.headline)
                .padding(.horizontal, Theme.Spacing.sm)
            
            VStack(spacing: Theme.Spacing.sm) {
                FAQItem(
                    question: "如何取消订阅？",
                    answer: "您可以随时在 App Store 设置中取消订阅"
                )
                
                Divider()
                
                FAQItem(
                    question: "是否支持家庭共享？",
                    answer: "Pro 订阅支持最多 6 位家庭成员共享"
                )
                
                Divider()
                
                FAQItem(
                    question: "能否退款？",
                    answer: "根据 Apple 政策，订阅可在购买后 14 天内申请退款"
                )
            }
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(Theme.Shapes.cardCornerRadius)
        }
    }
}

enum SubscriptionPlan: String {
    case monthly = "月度订阅"
    case yearly = "年度订阅"
    
    var price: String {
        switch self {
        case .monthly: return "¥68"
        case .yearly: return "¥588"
        }
    }
    
    var period: String {
        switch self {
        case .monthly: return "每月"
        case .yearly: return "每年"
        }
    }
    
    var savings: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return "节省 ¥228"
        }
    }
}

struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.brandBlue.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.Colors.brandBlue)
            }
            
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(Theme.Colors.primaryText)
                
                Text(description)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBackground)
        .cornerRadius(Theme.Shapes.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

struct ModernPlanCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text(plan.rawValue)
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.primaryText)
                    
                    if let savings = plan.savings {
                        Text(savings)
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(Capsule().fill(Theme.Colors.success))
                    } else {
                        Spacer()
                            .frame(height: Theme.Spacing.lg)
                    }
                }
                
                VStack(spacing: 0) {
                    Text(plan.price)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(isSelected ? Theme.Colors.brandBlue : Theme.Colors.primaryText)
                    
                    Text(plan.period)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                
                Image(systemName: isSelected ? Theme.Icons.checkmark : "")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.Colors.brandBlue)
                    .frame(height: 20)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.xl)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(Theme.Shapes.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                    .stroke(isSelected ? Theme.Colors.brandBlue : Color.clear, lineWidth: 3)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.1 : 0.05), radius: 8, x: 0, y: 4)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct FAQItem: View {
    let question: String
    let answer: String
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(question)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Text(answer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    NavigationStack {
        SubscriptionView()
            .environment(AuthManager.shared)
    }
}

