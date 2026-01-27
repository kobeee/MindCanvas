import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var isCodeSent = false
    @State private var countdown = 0

    // Toast 状态
    @State private var toastMessage = ""
    @State private var toastType: ToastType = .info
    @State private var showToast = false
    
    enum ToastType {
        case info, success, error
        
        var icon: String {
            switch self {
            case .info: return "envelope.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .info: return Theme.Colors.brandBlue
            case .success: return Color.fromHex("#34C759") ?? .green
            case .error: return Theme.Colors.destructive
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 主内容
                ScrollView {
                    VStack(spacing: Theme.Spacing.xxxl) {
                        logoSection

                        if authManager.isLoading {
                            loadingSection
                        } else {
                            loginOptionsSection
                        }

                        if let errorMessage = authManager.errorMessage {
                            errorSection(errorMessage)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
                .background(Theme.Colors.appBackground)

                // Toast 弹窗
                if showToast {
                    toastView
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showToast)
                }
            }
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && !authManager.isGuest {
                dismiss()
            }
        }
        .onChange(of: authManager.isGuest) { _, isGuest in
            if !isGuest && authManager.isAuthenticated {
                dismiss()
            }
        }
    }
    
    private var toastView: some View {
        HStack(spacing: 12) {
            Image(systemName: toastType.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(toastType.color)
            
            Text(toastMessage)
                .font(Theme.Fonts.bodyBold)
                .foregroundStyle(Theme.Colors.primaryText)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Theme.Colors.cardBackground)
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
        )
        .overlay(
            Capsule()
                .stroke(toastType.color.opacity(0.3), lineWidth: 1)
        )
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }
    
    private func showToast(message: String, type: ToastType, duration: Double = 2.5) {
        toastMessage = message
        toastType = type
        withAnimation {
            showToast = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showToast = false
            }
        }
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
                case .failure:
                    break
                }
            }
            .frame(height: Theme.Sizes.buttonHeight)
            .cornerRadius(Theme.Shapes.buttonCornerRadius)
            
            modernSocialButton(
                title: "使用 Google 登录",
                icon: "g.circle.fill",
                iconColor: Color.fromHex("#DB4437") ?? Color.red
            ) {
                Task {
                    await authManager.loginWithGoogle()
                }
            }
            
            modernSocialButton(
                title: "使用 GitHub 登录",
                icon: "chevron.left.forwardslash.chevron.right",
                iconColor: Color.fromHex("#333333") ?? Color.gray
            ) {
                Task {
                    await authManager.loginWithGithub()
                }
            }
            
            orDivider
            
            emailLoginSection

            Spacer()
                .frame(height: Theme.Spacing.xl)

            if !authManager.isGuest {
                guestLoginButton
            }
        }
        .frame(maxWidth: Theme.Sizes.maxContentWidth)
    }
    
    private var guestLoginButton: some View {
        Button {
            Task {
                await authManager.switchToGuestMode()
            }
        } label: {
            Text("游客模式")
                .font(Theme.Fonts.bodyBold)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
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
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
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
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
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

        // 显示发送中提示
        showToast(message: "验证码发送中...", type: .info)

        Task {
            let success = await authManager.sendVerificationCode(email: email)
            if success {
                showToast(message: "验证码已发送至您的邮箱", type: .success)
            } else if let error = authManager.errorMessage {
                showToast(message: error, type: .error)
                isCodeSent = false
                countdown = 0
            }
            startCountdown()
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

