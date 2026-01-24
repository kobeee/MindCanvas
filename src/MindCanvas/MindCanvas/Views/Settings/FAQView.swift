import SwiftUI

struct FAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

struct FAQView: View {
    private let faqs: [FAQItem] = [
        FAQItem(
            question: "如何配置 API Key？",
            answer: "进入「设置 > API 配置」，输入您的 API Key 即可。支持多种 AI 服务商。"
        ),
        FAQItem(
            question: "生成的图片保存在哪里？",
            answer: "生成的图片会自动保存在您的作品中，您可以在「我的作品」中查看和管理。"
        ),
        FAQItem(
            question: "为什么生成失败？",
            answer: "请检查：1) API Key 是否正确配置；2) 网络连接是否正常；3) API 额度是否充足。"
        ),
        FAQItem(
            question: "如何导出作品？",
            answer: "在编辑器中点击右上角导出按钮，可选择导出为 PNG 或 JPG 格式。"
        ),
        FAQItem(
            question: "支持哪些 AI 模型？",
            answer: "目前支持主流的图像生成模型，具体取决于您配置的 API 服务商。"
        ),
        FAQItem(
            question: "免费额度如何使用？",
            answer: "新用户注册后会获得一定次数的免费额度，可以在编辑器中直接使用，无需配置 API Key。额度用完后需要配置 API Key 才能继续生成。"
        ),
        FAQItem(
            question: "如何升级到 Pro 版本？",
            answer: "Pro 版本即将推出，敬请期待。升级后将获得更多免费额度和高级功能。"
        ),
        FAQItem(
            question: "如何删除我的作品？",
            answer: "在「我的作品」页面，左滑作品卡片即可显示删除按钮，点击后确认删除即可。"
        )
    ]
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(faqs, id: \.id) { faq in
                    DisclosureGroup {
                        Text(faq.answer)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .padding(.vertical, Theme.Spacing.sm)
                            .lineSpacing(4)
                    } label: {
                        Text(faq.question)
                            .font(Theme.Fonts.bodyBold)
                            .foregroundStyle(Theme.Colors.primaryText)
                    }
                }
            }
            .background(Theme.Colors.appBackground)
            .navigationTitle("常见问题")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    NavigationStack {
        FAQView()
    }
}