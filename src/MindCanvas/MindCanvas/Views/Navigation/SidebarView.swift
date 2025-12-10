import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: AppTab?
    
    var body: some View {
        List(AppTab.allCases, selection: $selectedTab) { tab in
            NavigationLink(value: tab) {
                Label(tab.title, systemImage: tab.icon)
            }
        }
        .navigationTitle("MindCanvas")
        .listStyle(.sidebar)
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(selectedTab: .constant(.creations))
    } detail: {
        Text("Detail")
    }
}

