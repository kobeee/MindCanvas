import SwiftUI

struct SettingsFAQItem: Identifiable {
    let id = UUID()
    let question: String
    let answer: String
}

struct FAQView: View {
    private let faqs: [SettingsFAQItem] = [
        SettingsFAQItem(
            question: "如何配置 API Key？",
            answer: "进入「设置 > API 配置」，输入您的 API Key 即可。支持多种 AI 服务商。"
        ),
        SettingsFAQItem(
            question: "生成的图片保存在哪里？",
            answer: "生成的图片会自动保存在您的作品中，您可以在「我的作品」中查看和管理。"
        ),
        SettingsFAQItem(
            question: "为什么生成失败？",
            answer: "请检查：1) API Key 是否正确配置；2) 网络连接是否正常；3) API 额度是否充足。"
        ),
        SettingsFAQItem(
            question: "如何保存生成图片？",
            answer: "在资源栏中点击选中图片，然后点击下载按钮即可保存到本地相册。"
        ),
        SettingsFAQItem(
            question: "支持哪些 AI 模型？",
            answer: "目前仅支持Gemini 3的nano banana pro模型。"
        ),
        SettingsFAQItem(
            question: "免费额度如何使用？",
            answer: "关注公众号可获得一定次数的免费额度，可以在编辑器中直接使用，无需配置 API Key。额度用完后需要配置 API Key 才能继续生成。"
        ),
        SettingsFAQItem(
            question: "如何升级到 Pro 版本？",
            answer: "Pro 版本即将推出，敬请期待。升级后将获得更多免费额度和高级功能。"
        ),
        SettingsFAQItem(
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