import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var email = ""
    @State private var verificationCode = ""
    @State private var isCodeSent = false
    @State private var countdown = 0
    
    var body: some View {
        VStack(spacing: 40) {
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
        .padding(60)
        .frame(maxWidth: 600)
    }
    
    private var logoSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)
            
            Text("MindCanvas")
                .font(.system(size: 48, weight: .bold))
            
            Text("用 AI 绘制你的创意")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
    
    private var loginOptionsSection: some View {
        VStack(spacing: 20) {
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
            .frame(height: 50)
            .cornerRadius(8)
            
            socialLoginButton(
                title: "使用 Google 登录",
                icon: "g.circle.fill",
                color: .red
            ) {
                Task {
                    await authManager.loginWithGoogle()
                }
            }
            
            socialLoginButton(
                title: "使用 GitHub 登录",
                icon: "chevron.left.forwardslash.chevron.right",
                color: .gray
            ) {
                Task {
                    await authManager.loginWithGithub()
                }
            }
            
            Divider()
                .padding(.vertical, 8)
            
            emailLoginSection
        }
    }
    
    private var emailLoginSection: some View {
        VStack(spacing: 16) {
            TextField("邮箱地址", text: $email)
                .textFieldStyle(.roundedBorder)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
            
            if isCodeSent {
                HStack {
                    TextField("验证码", text: $verificationCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                    
                    Button(countdown > 0 ? "\(countdown)秒" : "重新发送") {
                        sendCode()
                    }
                    .disabled(countdown > 0)
                    .buttonStyle(.bordered)
                }
                
                Button("登录") {
                    Task {
                        await authManager.loginWithEmail(email, code: verificationCode)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(verificationCode.isEmpty)
            } else {
                Button("发送验证码") {
                    sendCode()
                }
                .buttonStyle(.bordered)
                .disabled(email.isEmpty)
            }
        }
    }
    
    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("登录中...")
                .foregroundStyle(.secondary)
        }
    }
    
    private func errorSection(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.red)
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(8)
    }
    
    private func socialLoginButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.bordered)
        .tint(color)
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

