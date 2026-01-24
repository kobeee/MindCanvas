import SwiftUI

struct TermsOfServiceView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    titleSection
                    contentSections
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.appBackground)
            .navigationTitle("使用条款")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("MindCanvas 使用条款")
                .font(Theme.Fonts.title2)
                .foregroundStyle(Theme.Colors.primaryText)
            
            Text("最后更新日期：2025年1月")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
            
            Text("欢迎使用 MindCanvas。请在使用本应用前仔细阅读以下条款。")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineSpacing(4)
        }
        .padding(.bottom, Theme.Spacing.md)
    }
    
    private var contentSections: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            section(title: "一、服务说明", content: serviceDescriptionContent)
            section(title: "二、账户责任", content: accountResponsibilityContent)
            section(title: "三、使用规范", content: usageGuidelinesContent)
            section(title: "四、知识产权", content: intellectualPropertyContent)
            section(title: "五、API 配置", content: apiConfigurationContent)
            section(title: "六、免责声明", content: disclaimerContent)
            section(title: "七、服务变更", content: serviceChangesContent)
            section(title: "八、条款修改", content: termsModificationContent)
            section(title: "九、适用法律", content: applicableLawContent)
            section(title: "十、联系方式", content: contactUsContent)
        }
    }
    
    private func section(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.primaryText)
            
            Text(content)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineSpacing(4)
        }
    }
    
    // MARK: - Section Contents
    
    private var serviceDescriptionContent: String {
        """
        MindCanvas 是一款基于 AI 的创意绘图应用，允许用户通过画布操作和文字描述创作艺术作品。
        """
    }
    
    private var accountResponsibilityContent: String {
        """
        1. 您需要注册账户才能使用完整功能
        2. 您有责任保管好您的账户信息
        3. 您对账户下的所有活动负责
        """
    }
    
    private var usageGuidelinesContent: String {
        """
        使用 MindCanvas 时，您同意不会：
        1. 生成违法、色情、暴力或侵权内容
        2. 尝试破解、逆向工程或干扰应用正常运行
        3. 使用自动化工具批量生成内容
        4. 将应用用于任何非法目的
        """
    }
    
    private var intellectualPropertyContent: String {
        """
        1. MindCanvas 应用的所有权利归开发者所有
        2. 您使用 MindCanvas 创作的原创内容归您所有
        3. AI 生成内容的版权归属请参考相关 AI 服务商的条款
        """
    }
    
    private var apiConfigurationContent: String {
        """
        1. 您可以配置自己的 API Key 使用 AI 生成功能
        2. API 使用费用由您自行承担
        3. 请妥善保管您的 API Key，因泄露造成的损失由您自行承担
        """
    }
    
    private var disclaimerContent: String {
        """
        1. MindCanvas 按「现状」提供，不提供任何明示或暗示的保证
        2. 我们不对 AI 生成内容的准确性、适用性负责
        3. 我们不对因使用本应用造成的任何直接或间接损失负责
        4. 第三方 AI 服务的可用性和质量不在我们的控制范围内
        """
    }
    
    private var serviceChangesContent: String {
        """
        我们保留随时修改、暂停或终止服务的权利，恕不另行通知。
        """
    }
    
    private var termsModificationContent: String {
        """
        我们可能会不时修改本使用条款。继续使用本应用即表示您接受修改后的条款。
        """
    }
    
    private var applicableLawContent: String {
        """
        本条款受中华人民共和国法律管辖。
        """
    }
    
    private var contactUsContent: String {
        """
        如有任何问题，请关注微信公众号「逃离莫比乌斯」与我们联系。
        """
    }
}

#Preview {
    NavigationStack {
        TermsOfServiceView()
    }
}