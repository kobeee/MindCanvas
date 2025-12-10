import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var isCodeSent = false
    @State private var countdown = 0
    
    var body: some View {
        VStack(spacing: Theme.Spacing.xxxl) {
            Spacer()
            
            logoSection
            
            if authManager.isLoading {
                loadingSection
            } else {
                loginOptionsSection
            }
            
            if let errorMessage = authManager.errorMessage {
                errorSection(errorMessage)
            }
            
            Spacer()
        }
        .padding(.horizontal, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.appBackground)
    }
    
    private var logoSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: Theme.Icons.creationsFill)
                .font(.system(size: 80))
                .foregroundStyle(Theme.Colors.goldGradient)
            
            Text("MindCanvas")
                .font(Theme.Fonts.largeTitle)
            
            Text("用 AI 绘制你的创意")
                .font(Theme.Fonts.title3)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
    
    private var loginOptionsSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                switch result {
                case .success:
                    Task {
                        await authManager.loginWithApple()
                    }
                case .failure(let error):
                    print("Apple登录失败: \(error.localizedDescription)")
                }
            }
            .frame(height: Theme.Sizes.buttonHeight)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            
            modernSocialButton(
                title: "使用 Google 登录",
                icon: "g.circle.fill",
                iconColor: Color(hex: "#DB4437")
            ) {
                Task {
                    await authManager.loginWithGoogle()
                }
            }
            
            modernSocialButton(
                title: "使用 GitHub 登录",
                icon: "chevron.left.forwardslash.chevron.right",
                iconColor: Color(hex: "#333333")
            ) {
                Task {
                    await authManager.loginWithGithub()
                }
            }
            
            orDivider
            
            emailLoginSection
        }
        .frame(maxWidth: Theme.Sizes.maxContentWidth)
    }
    
    private var orDivider: some View {
        HStack(spacing: Theme.Spacing.md) {
            Rectangle()
                .fill(Theme.Colors.secondaryText.opacity(0.3))
                .frame(height: 1)
            
            Text("OR")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
            
            Rectangle()
                .fill(Theme.Colors.secondaryText.opacity(0.3))
                .frame(height: 1)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
    
    private var emailLoginSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            emailInputField
            
            if isCodeSent {
                verificationCodeSection
            } else {
                sendCodeButton
            }
        }
    }
    
    private var emailInputField: some View {
        TextField("邮箱地址", text: $email)
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .autocapitalization(.none)
            .padding()
            .frame(height: Theme.Sizes.buttonHeight)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .stroke(email.isEmpty ? Color.clear : Theme.Colors.brandBlue.opacity(0.3), lineWidth: 2)
            )
    }
    
    private var verificationCodeSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                TextField("验证码", text: $verificationCode)
                    .keyboardType(.numberPad)
                    .padding()
                    .frame(height: Theme.Sizes.buttonHeight)
                    .background(Theme.Colors.cardBackground)
                    .cornerRadius(Theme.Shapes.buttonCornerRadius)
                
                Button {
                    sendCode()
                } label: {
                    Text(countdown > 0 ? "\(countdown)秒" : "重新发送")
                        .font(Theme.Fonts.bodyBold)
                }
                .frame(width: 100, height: Theme.Sizes.buttonHeight)
                .background(countdown > 0 ? Theme.Colors.secondaryText.opacity(0.2) : Theme.Colors.brandBlue)
                .foregroundColor(countdown > 0 ? Theme.Colors.secondaryText : .white)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .disabled(countdown > 0)
            }
            
            Button {
                Task {
                    await authManager.loginWithEmail(email, code: verificationCode)
                }
            } label: {
                Text("登录")
                    .frame(maxWidth: .infinity)
            }
            .primaryButtonStyle()
            .disabled(verificationCode.isEmpty)
            .opacity(verificationCode.isEmpty ? 0.5 : 1.0)
        }
    }
    
    private var sendCodeButton: some View {
        Button {
            sendCode()
        } label: {
            Text("发送验证码")
                .frame(maxWidth: .infinity)
        }
        .primaryButtonStyle()
        .disabled(email.isEmpty)
        .opacity(email.isEmpty ? 0.5 : 1.0)
    }
    
    private var loadingSection: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.5)
            Text("登录中...")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
    
    private func errorSection(_ message: String) -> some View {
        Text(message)
            .font(Theme.Fonts.callout)
            .foregroundStyle(Theme.Colors.destructive)
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(Theme.Colors.destructive.opacity(0.1))
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
    }
    
    private func modernSocialButton(
        title: String,
        icon: String,
        iconColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(Theme.Colors.primaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Sizes.buttonHeight)
            .background(Theme.Colors.cardBackground)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .stroke(Theme.Colors.secondaryText.opacity(0.2), lineWidth: 1)
            )
        }
    }
    
    private func sendCode() {
        isCodeSent = true
        countdown = 60
        
        Task {
            do {
                try await MockAuthService.shared.sendVerificationCode(to: email)
                startCountdown()
            } catch {
                print("发送验证码失败")
            }
        }
    }
    
    private func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if countdown > 0 {
                countdown -= 1
            } else {
                timer.invalidate()
            }
        }
    }
}

#Preview {
    LoginView()
        .environment(AuthManager.shared)
}

