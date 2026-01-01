//
//  MindCanvasApp.swift
//  MindCanvas
//
//  Created by elvis on 2025/12/10.
//

import SwiftUI
import SwiftData

@main
struct MindCanvasApp: App {
    @State private var authManager = AuthManager.shared

    init() {
        setupApplication()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            Asset.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .onOpenURL { url in
                    handleOpenURL(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }

    // MARK: - 应用初始化

    private func setupApplication() {
        initializeThirdPartySDKs()
    }

    // MARK: - 第三方 SDK 初始化

    private func initializeThirdPartySDKs() {
        print("=== MindCanvasApp.initializeThirdPartySDKs() 开始 ===")
        print("应用 Bundle ID: \(Bundle.main.bundleIdentifier ?? "nil")")
        print("应用版本: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "nil")")
        print("构建版本: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "nil")")

        do {
            try GoogleSignInManager.shared.configure()
            print("✅ Google Sign In initialized successfully")
        } catch {
            print("❌ Failed to initialize Google Sign In: \(error.localizedDescription)")
            // 不要静默失败，让应用崩溃以便发现问题
            if let apiError = error as? APIError {
                print("❌ API Error: \(apiError.errorDescription ?? "Unknown error")")
            }
            fatalError("Google Sign In 初始化失败: \(error.localizedDescription)")
        }

        print("=== MindCanvasApp.initializeThirdPartySDKs() 完成 ===")
    }

    // MARK: - URL Scheme 处理

    private func handleOpenURL(_ url: URL) {
        guard url.scheme == "mindcanvas" else {
            return
        }

        if url.host == "auth" {
            handleAuthCallback(url)
        }
    }

    private func handleAuthCallback(_ url: URL) {
        GitHubOAuthManager.shared.handleCallback(url)
    }
}
