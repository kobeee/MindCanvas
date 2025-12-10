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
    }
    
    private var headerSection: some View {
        HStack {
            Text("资源库")
                .font(.headline)
            
            Spacer()
            
            Menu {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("从相册导入", systemImage: "photo.on.rectangle")
                }
                
                Button {
                    print("拍照功能")
                } label: {
                    Label("拍照", systemImage: "camera")
                }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
        }
        .padding()
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
            LazyVStack(spacing: 12) {
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
            .padding()
        }
    }
    
    private var publishSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let asset = assetToPublish {
                    AsyncImage(url: URL(string: asset.url)) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(height: 200)
                    .cornerRadius(12)
                }
                
                TextField("添加标题", text: $publishTitle)
                    .textFieldStyle(.roundedBorder)
                
                Button("发布到 MindStream") {
                    if let asset = assetToPublish {
                        Task {
                            await viewModel.publishAsset(asset, title: publishTitle)
                            showingPublishSheet = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(publishTitle.isEmpty)
                
                Spacer()
            }
            .padding()
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
        Button(action: onTap) {
            VStack(spacing: 0) {
                imageSection
                
                if showingMenu {
                    menuSection
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
        )
        .onChange(of: isSelected) { _, newValue in
            showingMenu = newValue
        }
    }
    
    private var imageSection: some View {
        ZStack {
            if asset.isLoading {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(4/3, contentMode: .fit)
                    .overlay {
                        ProgressView()
                    }
            } else {
                AsyncImage(url: URL(string: asset.url)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            ProgressView()
                        }
                }
                .aspectRatio(4/3, contentMode: .fit)
                .clipped()
            }
            
            if asset.type == .generated {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .cornerRadius(12)
    }
    
    private var menuSection: some View {
        HStack(spacing: 12) {
            menuButton(icon: "plus.circle.fill", label: "添加", action: onAddToCanvas)
            
            if asset.type == .generated {
                menuButton(icon: "arrow.down.circle.fill", label: "下载", action: onDownload)
                menuButton(icon: "globe", label: "发布", action: onPublish)
            }
            
            menuButton(icon: "trash.fill", label: "删除", color: .red, action: onDelete)
        }
        .padding(.vertical, 8)
    }
    
    private func menuButton(icon: String, label: String, color: Color = .blue, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AssetLibraryView(viewModel: EditorViewModel(project: Project(name: "示例")))
        .modelContainer(for: Asset.self, inMemory: true)
        .frame(width: 300, height: 600)
}

