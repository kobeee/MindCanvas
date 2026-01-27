import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Group {
            if !authManager.isInitialized {
                LoadingView()
            } else if authManager.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
        .id(authManager.isAuthenticated)
    }
}

#Preview {
    RootView()
        .environment(AuthManager.shared)
}

