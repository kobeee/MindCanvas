import SwiftUI

struct SidebarView: View {
    @Binding var selectedTab: AppTab?
    
    var body: some View {
        List(AppTab.allCases, selection: $selectedTab) { tab in
            NavigationLink(value: tab) {
                SidebarRowView(tab: tab, isSelected: selectedTab == tab)
            }
            .listRowBackground(rowBackground(for: tab))
        }
        .navigationTitle("MindCanvas")
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }
    
    private func rowBackground(for tab: AppTab) -> some View {
        Group {
            if selectedTab == tab {
                Theme.Colors.brandBlue.opacity(0.1)
                    .cornerRadius(Theme.Shapes.buttonCornerRadius)
            } else {
                Color.clear
            }
        }
    }
}

struct SidebarRowView: View {
    let tab: AppTab
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            iconView
            textView
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
    
    private var iconView: some View {
        Image(systemName: isSelected ? tab.iconFill : tab.icon)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(isSelected ? Theme.Colors.brandBlue : Theme.Colors.secondaryText)
            .frame(width: 28)
    }
    
    private var textView: some View {
        Text(tab.title)
            .font(isSelected ? Theme.Fonts.bodyBold : Theme.Fonts.body)
            .foregroundStyle(isSelected ? Theme.Colors.brandBlue : Theme.Colors.primaryText)
    }
}

#Preview {
    NavigationSplitView {
        SidebarView(selectedTab: .constant(.creations))
    } detail: {
        Text("Detail")
    }
}

