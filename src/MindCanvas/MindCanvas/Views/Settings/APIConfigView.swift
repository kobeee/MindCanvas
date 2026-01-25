import SwiftUI

struct APIConfigView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var isSaved: Bool = false
    @State private var showingAlert: Bool = false
    @State private var showingDeleteAlert: Bool = false
    @State private var alertMessage: String = ""

    var body: some View {
        NavigationStack {
            Form {
                apiKeySection
                deleteButtonSection
                descriptionSection
                validationSection
            }
            .background(Theme.Colors.appBackground)
            .navigationTitle("API 配置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.brandBlue)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveAPIKey()
                    }
                    .foregroundStyle(Theme.Colors.brandBlue)
                    .fontWeight(.semibold)
                }
            }
            .alert("提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .alert("删除 API Key", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    deleteAPIKey()
                }
            } message: {
                Text("确定要删除 API Key 吗？删除后将无法使用 AI 图像生成功能。")
            }
            .onAppear {
                loadExistingAPIKey()
            }
        }
    }

    private var apiKeySection: some View {
        Section {
            SecureAPIKeyField(
                apiKey: $apiKey
            )
        } header: {
            Text("Google Nano Banana Pro API Key")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.primaryText)
        } footer: {
            if isSaved {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                    Text("已保存")
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
    }
    
    private var deleteButtonSection: some View {
        Section {
            if isSaved && !apiKey.isEmpty {
                Button {
                    showingDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Label("删除 API Key", systemImage: "trash")
                            .font(Theme.Fonts.bodyBold)
                            .foregroundStyle(Theme.Colors.destructive)
                        Spacer()
                    }
                }
            }
        }
    }

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                descriptionRow(
                    icon: "info.circle",
                    title: "用途说明",
                    description: "用于启用 AI 图像生成功能，支持高质量图像创作。"
                )

                descriptionRow(
                    icon: "link",
                    title: "获取方式",
                    description: "访问 Google AI Studio 获取您的 API Key。"
                )

                descriptionRow(
                    icon: "checkmark.shield",
                    title: "安全保障",
                    description: "API Key 将安全存储在设备 Keychain 中，不会上传到服务器。"
                )
            }
            .padding(.vertical, Theme.Spacing.sm)
        } header: {
            Text("说明")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textCase(.uppercase)
        }
    }

    private var validationSection: some View {
        Section {
            if !apiKey.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: isValidFormat ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(isValidFormat ? Theme.Colors.success : Theme.Colors.warning)

                    Text(isValidFormat ? "API Key 格式正确" : "API Key 格式可能不正确")
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(isValidFormat ? Theme.Colors.success : Theme.Colors.warning)
                }
            }
        } header: {
            Text("验证状态")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textCase(.uppercase)
        }
    }

    private var isValidFormat: Bool {
        let pattern = "^AIza[A-Za-z0-9_-]{31,41}$"
        return apiKey.range(of: pattern, options: .regularExpression) != nil
    }

    private func descriptionRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.brandBlue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(Theme.Colors.primaryText)

                Text(description)
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }

    private func loadExistingAPIKey() {
        if let existingKey = KeychainManager.shared.getAPIKey() {
            apiKey = existingKey
            isSaved = true
        }
    }

    private func saveAPIKey() {
        if apiKey.isEmpty {
            alertMessage = "请输入 API Key 或点击删除按钮"
            showingAlert = true
            return
        }

        if !isValidFormat {
            alertMessage = "API Key 格式不正确，请检查后重试"
            showingAlert = true
            return
        }

        let success = KeychainManager.shared.saveAPIKey(apiKey)
        if success {
            isSaved = true
            dismiss()
        } else {
            alertMessage = "保存失败，请重试"
            showingAlert = true
        }
    }
    
    private func deleteAPIKey() {
        let success = KeychainManager.shared.deleteAPIKey()
        if success {
            apiKey = ""
            isSaved = false
        } else {
            alertMessage = "删除失败，请重试"
            showingAlert = true
        }
    }
}

#Preview {
    NavigationStack {
        APIConfigView()
    }
}