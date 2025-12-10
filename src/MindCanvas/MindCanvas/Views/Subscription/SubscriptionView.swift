import SwiftUI

struct SubscriptionView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var selectedPlan: SubscriptionPlan = .monthly
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    headerSection
                    featuresSection
                    planSelector
                    subscribeButton
                    faqSection
                }
                .padding()
            }
            .navigationTitle("订阅 Pro")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 60))
                .foregroundStyle(.yellow.gradient)
            
            Text("升级到 Pro")
                .font(.largeTitle.bold())
            
            Text("解锁所有功能，释放无限创意")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical)
    }
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            FeatureRow(icon: "sparkles", title: "无限生成", description: "不受限制地使用 AI 生成图像")
            FeatureRow(icon: "cloud.fill", title: "云端存储", description: "10GB 云端项目存储空间")
            FeatureRow(icon: "wand.and.stars", title: "高级模型", description: "访问最新的 AI 模型和功能")
            FeatureRow(icon: "person.2.fill", title: "优先支持", description: "享受优先客户支持服务")
            FeatureRow(icon: "arrow.down.circle.fill", title: "高清下载", description: "无水印高清图片导出")
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
    
    private var planSelector: some View {
        VStack(spacing: 12) {
            PlanCard(
                plan: .monthly,
                isSelected: selectedPlan == .monthly,
                onSelect: { selectedPlan = .monthly }
            )
            
            PlanCard(
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
            Text("立即订阅")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.blue.gradient)
                .cornerRadius(12)
        }
    }
    
    private var faqSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("常见问题")
                .font(.headline)
            
            FAQItem(
                question: "如何取消订阅？",
                answer: "您可以随时在 App Store 设置中取消订阅"
            )
            
            FAQItem(
                question: "是否支持家庭共享？",
                answer: "Pro 订阅支持最多 6 位家庭成员共享"
            )
            
            FAQItem(
                question: "能否退款？",
                answer: "根据 Apple 政策，订阅可在购买后 14 天内申请退款"
            )
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
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

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
}

struct PlanCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(plan.rawValue)
                            .font(.headline)
                        
                        if let savings = plan.savings {
                            Text(savings)
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    
                    Text("\(plan.price) / \(plan.period)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? .blue : .secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
            )
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

