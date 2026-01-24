import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    titleSection
                    contentSections
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.appBackground)
            .navigationTitle("隐私政策")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("MindCanvas 隐私政策")
                .font(Theme.Fonts.title2)
                .foregroundStyle(Theme.Colors.primaryText)
            
            Text("最后更新日期：2025年1月")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
            
            Text("感谢您使用 MindCanvas。我们非常重视您的隐私，本隐私政策旨在向您说明我们如何收集、使用和保护您的个人信息。")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.secondaryText)
                .lineSpacing(4)
        }
        .padding(.bottom, Theme.Spacing.md)
    }
    
    private var contentSections: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            section(title: "一、信息收集", content: infoCollectionContent)
            section(title: "二、信息使用", content: infoUsageContent)
            section(title: "三、信息共享", content: infoSharingContent)
            section(title: "四、第三方服务", content: thirdPartyServicesContent)
            section(title: "五、数据安全", content: dataSecurityContent)
            section(title: "六、您的权利", content: userRightsContent)
            section(title: "七、儿童隐私", content: childrenPrivacyContent)
            section(title: "八、隐私政策更新", content: policyUpdateContent)
            section(title: "九、联系我们", content: contactUsContent)
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
    
    private var infoCollectionContent: String {
        """
        1. 账户信息
        当您注册 MindCanvas 账户时，我们会收集您的电子邮箱地址用于账户验证和登录。

        2. 使用数据
        我们可能收集您使用应用的基本信息，包括：
        - 设备类型和操作系统版本
        - 应用崩溃日志（用于改进应用稳定性）
        - 功能使用频率（匿名统计）

        3. 创作内容
        您在 MindCanvas 中创建的画作和生成的图像存储在您的本地设备上。
        """
    }
    
    private var infoUsageContent: String {
        """
        我们收集的信息仅用于：
        - 提供和维护应用服务
        - 改进用户体验
        - 发送重要的服务通知
        - 分析和解决技术问题
        """
    }
    
    private var infoSharingContent: String {
        """
        我们不会出售、交易或以其他方式向第三方转让您的个人信息，除非：
        - 获得您的明确同意
        - 法律法规要求
        - 保护我们的合法权益
        """
    }
    
    private var thirdPartyServicesContent: String {
        """
        MindCanvas 使用第三方 AI 服务生成图像。当您使用 AI 生成功能时，您的提示词会发送至相应的 AI 服务提供商。请参阅相关服务商的隐私政策了解其数据处理方式。
        """
    }
    
    private var dataSecurityContent: String {
        """
        我们采取合理的技术和管理措施保护您的个人信息安全，包括：
        - 使用加密技术保护敏感数据
        - 定期审查数据收集和存储实践
        - 限制员工访问个人信息
        """
    }
    
    private var userRightsContent: String {
        """
        您有权：
        - 访问您的个人信息
        - 更正不准确的信息
        - 删除您的账户和相关数据
        - 撤回同意

        如需行使上述权利，请通过应用内的反馈渠道联系我们。
        """
    }
    
    private var childrenPrivacyContent: String {
        """
        MindCanvas 不面向 13 岁以下儿童。我们不会故意收集儿童的个人信息。
        """
    }
    
    private var policyUpdateContent: String {
        """
        我们可能会不时更新本隐私政策。更新后的政策将在应用内公布，建议您定期查阅。
        """
    }
    
    private var contactUsContent: String {
        """
        如您对本隐私政策有任何疑问，请关注微信公众号「逃离莫比乌斯」与我们联系。
        """
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}