import SwiftUI

struct AccountSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var username: String = ""
    @State private var isSaving: Bool = false
    @State private var showingAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var alertType: AlertType = .success
    
    enum AlertType {
        case success
        case error
    }
    
    var body: some View {
        NavigationStack {
            Form {
                usernameSection
                emailSection
            }
            .background(Theme.Colors.appBackground)
            .navigationTitle("账号设置")
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
                        saveUsername()
                    }
                    .disabled(username.isEmpty || isSaving || username == (authManager.currentUser?.username ?? ""))
                    .foregroundStyle(username.isEmpty || isSaving || username == (authManager.currentUser?.username ?? "") ? Theme.Colors.secondaryText : Theme.Colors.brandBlue)
                    .fontWeight(username.isEmpty || isSaving || username == (authManager.currentUser?.username ?? "") ? .regular : .semibold)
                }
            }
            .alert("提示", isPresented: $showingAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                if let currentUser = authManager.currentUser {
                    username = currentUser.username
                }
            }
        }
    }
    
    private var usernameSection: some View {
        Section {
            TextField("账户名称", text: $username)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding()
                .background(Theme.Colors.cardBackground)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .stroke(username.isEmpty ? Color.clear : Theme.Colors.brandBlue.opacity(0.3), lineWidth: 2)
                )
        } header: {
            Text("账户名称")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textCase(.uppercase)
        } footer: {
            Text("这是您在应用中显示的名称")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
    
    private var emailSection: some View {
        Section {
            if let email = authManager.currentUser?.email {
                HStack {
                    Text(email)
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Spacer()
                }
            }
        } header: {
            Text("邮箱")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textCase(.uppercase)
        } footer: {
            Text("邮箱地址不可更改")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
    
    private func saveUsername() {
        guard !username.isEmpty else {
            showAlert(message: "账户名称不能为空", type: .error)
            return
        }
        
        guard username != (authManager.currentUser?.username ?? "") else {
            showAlert(message: "账户名称未更改", type: .error)
            return
        }
        
        isSaving = true
        
        Task {
            let success = await authManager.updateUsername(username)
            
            await MainActor.run {
                isSaving = false
                
                if success {
                    showAlert(message: "账户名称已更新", type: .success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        dismiss()
                    }
                } else {
                    showAlert(message: authManager.errorMessage ?? "更新失败，请重试", type: .error)
                }
            }
        }
    }
    
    private func showAlert(message: String, type: AlertType) {
        alertMessage = message
        alertType = type
        showingAlert = true
    }
}

#Preview {
    NavigationStack {
        AccountSettingsView()
            .environment(AuthManager.shared)
    }
}