import SwiftUI
import PhotosUI
import SwiftData

struct AssetLibraryView: View {
    @Bindable var viewModel: EditorViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingPublishSheet = false
    @State private var publishTitle = ""
    @State private var assetToPublish: Asset?
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            assetListSection
        }
        .onAppear {
            viewModel.setModelContext(modelContext)
        }
        .sheet(isPresented: $showingPublishSheet) {
            publishSheet
        }
        // 下载成功 Toast 提示
        .overlay(alignment: .bottom) {
            if viewModel.showDownloadSuccessToast {
                ToastView(message: "已保存至相册", icon: "checkmark.circle.fill")
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        // 2秒后自动隐藏
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                viewModel.showDownloadSuccessToast = false
                            }
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showDownloadSuccessToast)
    }
    
    private var headerSection: some View {
        HStack {
            Text("资源库")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.primaryText)
            
            Spacer()
            
            Menu {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("从相册导入", systemImage: Theme.Icons.photo)
                }
                
                Button {
                } label: {
                    Label("拍照", systemImage: Theme.Icons.camera)
                }
            } label: {
                Image(systemName: Theme.Icons.add)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.Colors.brandBlue)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBackground)
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    await viewModel.importImage(data)
                }
                selectedPhotoItem = nil
            }
        }
    }
    
    private var assetListSection: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.lg) {
                ForEach(viewModel.assets) { asset in
                    AssetCard(
                        asset: asset,
                        isSelected: viewModel.selectedAsset?.id == asset.id,
                        onTap: {
                            viewModel.selectedAsset = asset
                        },
                        onAddToCanvas: {
                            viewModel.addAssetToCanvas(asset)
                        },
                        onDownload: {
                            viewModel.downloadAsset(asset)
                        },
                        onPublish: {
                            assetToPublish = asset
                            publishTitle = ""
                            showingPublishSheet = true
                        },
                        onDelete: {
                            viewModel.deleteAsset(asset)
                        }
                    )
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Theme.Colors.appBackground)
    }
    
    private var publishSheet: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                if let asset = assetToPublish {
                    CachedAsyncImage(urlString: asset.url, localPath: asset.localPath, contentMode: .fit)
                        .frame(height: 200)
                        .cornerRadius(Theme.Shapes.cardCornerRadius)
                }
                
                TextField("添加标题", text: $publishTitle)
                    .padding(Theme.Spacing.lg)
                    .background(Theme.Colors.appBackground)
                    .cornerRadius(Theme.Shapes.buttonCornerRadius)
                
                Button("发布到 MindStream") {
                    if let asset = assetToPublish {
                        Task {
                            await viewModel.publishAsset(asset, title: publishTitle)
                            showingPublishSheet = false
                        }
                    }
                }
                .primaryButtonStyle()
                .disabled(publishTitle.isEmpty)
                .opacity(publishTitle.isEmpty ? 0.5 : 1.0)
                
                Spacer()
            }
            .padding(Theme.Spacing.xxl)
            .navigationTitle("发布作品")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        showingPublishSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct AssetCard: View {
    let asset: Asset
    let isSelected: Bool
    let onTap: () -> Void
    let onAddToCanvas: () -> Void
    let onDownload: () -> Void
    let onPublish: () -> Void
    let onDelete: () -> Void
    
    @State private var showingMenu = false
    
    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button(action: onTap) {
                imageSection
            }
            .buttonStyle(.plain)
            .scaleEffect(isSelected ? 0.95 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .stroke(isSelected ? Theme.Colors.brandBlue : Color.clear, lineWidth: 3)
            )
            .animation(.spring(response: 0.3), value: isSelected)
            
            if isSelected {
                floatingToolbar
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onChange(of: isSelected) { _, newValue in
            withAnimation(.spring(response: 0.3)) {
                showingMenu = newValue
            }
        }
    }
    
    private var imageSection: some View {
        ZStack {
            if asset.isLoading {
                Rectangle()
                    .fill(Theme.Colors.secondaryText.opacity(0.1))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
            } else {
                CachedAsyncImage(urlString: asset.url, localPath: asset.localPath, contentMode: .fit)
                    .aspectRatio(4/3, contentMode: .fit)
                    .clipped()
            }
            
            if asset.type == .generated {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.Colors.brandBlue)
                            .padding(Theme.Spacing.sm)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .padding(Theme.Spacing.sm)
                    }
                    Spacer()
                }
            }
        }
        .cornerRadius(Theme.Shapes.buttonCornerRadius)
    }
    
    private var floatingToolbar: some View {
        HStack(spacing: Theme.Spacing.xl) {
            toolbarButton(
                icon: Theme.Icons.add,
                color: Theme.Colors.brandBlue,
                action: onAddToCanvas
            )
            
            if asset.type == .generated {
                toolbarButton(
                    icon: Theme.Icons.download,
                    color: Theme.Colors.brandBlue,
                    action: onDownload
                )
                
                toolbarButton(
                    icon: Theme.Icons.publish,
                    color: Theme.Colors.brandBlue,
                    action: onPublish
                )
            }
            
            toolbarButton(
                icon: Theme.Icons.delete,
                color: Theme.Colors.destructive,
                action: onDelete
            )
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private func toolbarButton(
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .hoverEffect(.lift)
    }
}

#Preview {
    AssetLibraryView(viewModel: EditorViewModel(project: Project(name: "示例")))
        .modelContainer(for: Asset.self, inMemory: true)
        .frame(width: 300, height: 600)
}

// MARK: - Toast 提示组件

private struct ToastView: View {
    let message: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
            
            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        )
    }
}

