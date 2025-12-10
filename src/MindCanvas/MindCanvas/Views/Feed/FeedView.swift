import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
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
                .padding()
            }
            .navigationTitle("MindStream")
            .task {
                await viewModel.loadFeed()
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
    }
}

struct FeedCard: View {
    let item: FeedItem
    let onLike: () -> Void
    let onRemix: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            authorSection
            
            imageSection
            
            if item.showPrompt, let prompt = item.prompt {
                promptSection(prompt)
            }
            
            actionsSection
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
    
    private var authorSection: some View {
        HStack {
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(item.author.username.prefix(1))
                        .foregroundStyle(.white)
                        .font(.headline)
                }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(item.author.username)
                        .font(.headline)
                    
                    if item.author.isPro {
                        Image(systemName: "crown.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }
                
                Text(item.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var imageSection: some View {
        AsyncImage(url: URL(string: item.imageUrl)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .aspectRatio(4/3, contentMode: .fit)
                .overlay {
                    ProgressView()
                }
        }
        .cornerRadius(12)
    }
    
    private func promptSection(_ prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("提示词")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(prompt)
                .font(.body)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
        }
    }
    
    private var actionsSection: some View {
        HStack(spacing: 20) {
            Button(action: onLike) {
                HStack(spacing: 6) {
                    Image(systemName: item.isLiked ? "heart.fill" : "heart")
                        .foregroundStyle(item.isLiked ? .red : .primary)
                    Text("\(item.likesCount)")
                        .font(.body)
                }
            }
            .buttonStyle(.plain)
            
            Button(action: onRemix) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Remix")
                        .font(.body)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
}

