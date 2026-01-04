import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()
    
    var body: some View {
        NavigationStack {
            comingSoonView
                .background(Theme.Colors.appBackground)
                .navigationTitle("MindStream")
        }
    }
    
    private var comingSoonView: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer()
            
            Image(systemName: "sparkles")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(Theme.Colors.brandBlue.opacity(0.6))
            
            VStack(spacing: Theme.Spacing.md) {
                Text("敬请期待")
                    .font(Theme.Fonts.largeTitle)
                    .foregroundStyle(Theme.Colors.primaryText)
                
                Text("精彩内容即将上线")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 原有实现（暂时隐藏）
    
    @ViewBuilder
    private var originalFeedContent: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.lg) {
                ForEach(viewModel.items) { item in
                    FeedCard(item: item) {
                        Task {
                            await viewModel.toggleLike(item)
                        }
                    } onRemix: {
                        viewModel.remixItem(item)
                    }
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .padding()
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .task {
            await viewModel.loadFeed()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

struct FeedCard: View {
    let item: FeedItem
    let onLike: () -> Void
    let onRemix: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            authorSection
            
            imageSection
            
            if item.showPrompt, let prompt = item.prompt {
                promptSection(prompt)
            }
            
            actionsSection
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBackground)
        .cornerRadius(Theme.Shapes.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
    
    private var authorSection: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let avatarUrl = item.author.avatarUrl, let url = URL(string: avatarUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    avatarPlaceholder
                }
                .frame(width: Theme.Sizes.avatarSmall, height: Theme.Sizes.avatarSmall)
                .clipShape(Circle())
            } else {
                avatarPlaceholder
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(item.author.username)
                        .font(Theme.Fonts.bodyBold)
                        .foregroundStyle(Theme.Colors.primaryText)
                    
                    if item.author.isPro {
                        Image(systemName: Theme.Icons.subscriptionFill)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Colors.goldGradient)
                    }
                }
                
                Text(item.createdAt, style: .relative)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            
            Spacer()
            
            Menu {
                Button {
                    print("举报")
                } label: {
                    Label("举报", systemImage: "exclamationmark.triangle")
                }
                
                Button(role: .destructive) {
                    print("拉黑")
                } label: {
                    Label("拉黑用户", systemImage: "person.crop.circle.badge.xmark")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(width: 32, height: 32)
            }
        }
    }
    
    private var avatarPlaceholder: some View {
        Circle()
            .fill(Theme.Colors.brandBlue.gradient)
            .frame(width: Theme.Sizes.avatarSmall, height: Theme.Sizes.avatarSmall)
            .overlay {
                Text(String(item.author.username.prefix(1)))
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(.white)
            }
    }
    
    private var imageSection: some View {
        AsyncImage(url: URL(string: item.imageUrl)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            case .failure:
                Rectangle()
                    .fill(Theme.Colors.secondaryText.opacity(0.1))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay {
                        Image(systemName: Theme.Icons.photo)
                            .font(.system(size: 32))
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
            case .empty:
                Rectangle()
                    .fill(Theme.Colors.secondaryText.opacity(0.1))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
            @unknown default:
                EmptyView()
            }
        }
        .cornerRadius(Theme.Shapes.buttonCornerRadius)
    }
    
    private func promptSection(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Prompt")
                .font(Theme.Fonts.caption2)
                .foregroundStyle(Theme.Colors.secondaryText)
                .textCase(.uppercase)
            
            Text(prompt)
                .font(Theme.Fonts.monospacedSmall)
                .foregroundStyle(Theme.Colors.primaryText)
                .padding(Theme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.Colors.secondaryText.opacity(0.05))
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
        }
    }
    
    private var actionsSection: some View {
        HStack(spacing: Theme.Spacing.xl) {
            Spacer()
            
            Button(action: onLike) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: item.isLiked ? Theme.Icons.likeFill : Theme.Icons.like)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(item.isLiked ? Theme.Colors.destructive : Theme.Colors.secondaryText)
                    Text("\(item.likesCount)")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(item.isLiked ? 1.1 : 1.0)
            .animation(.spring(response: 0.3), value: item.isLiked)
            
            Button(action: onRemix) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: Theme.Icons.remix)
                        .font(.system(size: 18, weight: .medium))
                    Text("Remix")
                        .font(Theme.Fonts.caption)
                }
                .foregroundStyle(Theme.Colors.secondaryText)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
}

