import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var showingLogoutAlert = false
    @State private var showingLoginView = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    profileHeader
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                
                if !authManager.isGuest {
                    accountSection
                }

                appSection
                helpSection
                aboutSection

                if !authManager.isGuest {
                    logoutSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.appBackground)
            .navigationTitle("设置")
            .alert("退出登录", isPresented: $showingLogoutAlert) {
                Button("取消", role: .cancel) { }
                Button("退出", role: .destructive) {
                    Task {
                        await authManager.switchToGuestMode()
                    }
                }
            } message: {
                Text("确定要退出登录吗？退出后将切换到游客模式。")
            }
            .onChange(of: authManager.isGuest) { oldValue, newValue in
                if showingLoginView && oldValue && !newValue {
                    showingLoginView = false
                }
            }
            .sheet(isPresented: $showingLoginView) {
                LoginView(isPresented: $showingLoginView)
            }
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if authManager.isAuthenticated, let user = authManager.currentUser {
                if let avatarUrl = user.avatarUrl, let url = URL(string: avatarUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        avatarPlaceholder(username: user.username)
                    }
                    .frame(width: Theme.Sizes.avatarLarge, height: Theme.Sizes.avatarLarge)
                    .clipShape(Circle())
                } else {
                    avatarPlaceholder(username: user.username)
                }
                
                VStack(spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(user.username)
                            .font(Theme.Fonts.title2)
                            .foregroundStyle(Theme.Colors.primaryText)
                        
                        if user.isPro {
                            Image(systemName: Theme.Icons.subscriptionFill)
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.Colors.goldGradient)
                        }
                    }
                    
                    if let email = user.email {
                        Text(email)
                            .font(Theme.Fonts.callout)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
            } else {
                guestModeHeader
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxxl)
        .background(Theme.Colors.cardBackground)
    }
    
    private var guestModeHeader: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Circle()
                .fill(Theme.Colors.secondaryText.opacity(0.2))
                .frame(width: Theme.Sizes.avatarLarge, height: Theme.Sizes.avatarLarge)
                .overlay {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

            VStack(spacing: Theme.Spacing.sm) {
                Text("游客模式")
                    .font(Theme.Fonts.title2)
                    .foregroundStyle(Theme.Colors.primaryText)

                Button {
                    showingLoginView = true
                } label: {
                    HStack(spacing: 4) {
                        Text("登录")
                            .font(Theme.Fonts.bodyBold)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.Colors.brandBlue)
                }
            }
        }
    }
    
    private func avatarPlaceholder(username: String) -> some View {
        Circle()
            .fill(Theme.Colors.brandBlue.gradient)
            .frame(width: Theme.Sizes.avatarLarge, height: Theme.Sizes.avatarLarge)
            .overlay {
                Text(String(username.prefix(1)))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
    
    private var accountSection: some View {
        Section {
            NavigationLink {
                AccountSettingsView()
            } label: {
                Label {
                    Text("账号设置")
                        .foregroundStyle(Theme.Colors.primaryText)
                } icon: {
                    SettingsIcon.account("person.fill")
                }
            }
        } header: {
            Text("账号")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textCase(.uppercase)
        }
    }
    
    private var appSection: some View {
        Section {
            NavigationLink {
                APIConfigView()
            } label: {
                Label {
                    Text("API 配置")
                        .foregroundStyle(Theme.Colors.primaryText)
                } icon: {
                    SettingsIcon.app("key.fill")
                }
            }
        } header: {
            Text("应用设置")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textCase(.uppercase)
        }
    }
    
    private var aboutSection: some View {
        Section {
            HStack {
                Label {
                    Text("版本")
                        .foregroundStyle(Theme.Colors.primaryText)
                } icon: {
                    SettingsIcon.about("info")
                }
                Spacer()
                Text(appVersion)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label {
                    Text("隐私政策")
                        .foregroundStyle(Theme.Colors.primaryText)
                } icon: {
                    SettingsIcon.about("lock.fill")
                }
            }

            NavigationLink {
                TermsOfServiceView()
            } label: {
                Label {
                    Text("使用条款")
                        .foregroundStyle(Theme.Colors.primaryText)
                } icon: {
                    SettingsIcon.about("doc.text.fill")
                }
            }
        } header: {
            Text("关于")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textCase(.uppercase)
        }
    }
    
    private var logoutSection: some View {
        Section {
            Button {
                showingLogoutAlert = true
            } label: {
                HStack {
                    Spacer()
                    Label {
                        Text("退出登录")
                            .font(Theme.Fonts.bodyBold)
                            .foregroundStyle(Theme.Colors.destructive)
                    } icon: {
                        SettingsIcon.danger("rectangle.portrait.and.arrow.right")
                    }
                    Spacer()
                }
            }
        }
    }

    private var helpSection: some View {
        Section {
            NavigationLink {
                FAQView()
            } label: {
                Label {
                    Text("常见问题")
                        .foregroundStyle(Theme.Colors.primaryText)
                } icon: {
                    SettingsIcon.help("questionmark")
                }
            }

            NavigationLink {
                ContactUsView()
            } label: {
                HStack {
                    Label {
                        Text("联系我们")
                            .foregroundStyle(Theme.Colors.primaryText)
                    } icon: {
                        SettingsIcon.contact("bubble.left.fill")
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Text("有福利")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        LinearGradient(
                            colors: [Color.fromHex("#FF6B6B") ?? .red, Color.fromHex("#FF8E53") ?? .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(4)
                }
            }

            Button {
                requestAppStoreReview()
            } label: {
                Label {
                    Text("给个好评")
                        .foregroundStyle(Theme.Colors.primaryText)
                } icon: {
                    SettingsIcon.rating("star.fill")
                }
            }
        } header: {
            Text("帮助与反馈")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textCase(.uppercase)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private func requestAppStoreReview() {
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AuthManager.shared)
    }
}

