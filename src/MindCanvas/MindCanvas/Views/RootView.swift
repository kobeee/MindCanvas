import SwiftUI

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainView()
            } else {
                LoginView()
            }
        }
    }
}

#Preview {
    RootView()
        .environment(AuthManager.shared)
}

