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
        do {
            try GoogleSignInManager.shared.configure()
        } catch {
            if let apiError = error as? APIError {
                fatalError("Google Sign In 初始化失败: \(apiError.errorDescription ?? "Unknown error")")
            }
            fatalError("Google Sign In 初始化失败: \(error.localizedDescription)")
        }
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
