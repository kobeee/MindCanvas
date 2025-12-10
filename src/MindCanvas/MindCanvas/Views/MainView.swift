import SwiftUI

struct MainView: View {
    @State private var selectedTab: AppTab? = .creations
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selectedTab: $selectedTab)
        } detail: {
            contentView
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.columnVisibilityBinding, $columnVisibility)
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .creations:
            ProjectListView()
        case .mindStream:
            FeedView()
        case .subscription:
            SubscriptionView()
        case .settings:
            SettingsView()
        case .none:
            placeholderView
        }
    }
    
    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text("请从左侧选择一个功能")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    MainView()
        .environment(AuthManager.shared)
}

