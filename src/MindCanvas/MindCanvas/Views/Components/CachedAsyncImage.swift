//
//  CachedAsyncImage.swift
//  MindCanvas
//
//  自定义图片加载 View，支持相对路径、绝对路径、远程 URL
//

import SwiftUI

/// 自定义图片加载 View，支持相对路径、绝对路径、远程 URL
@MainActor
struct CachedAsyncImage: View {
    let urlString: String
    let contentMode: ContentMode
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var hasFailed = false

    init(urlString: String, contentMode: ContentMode = .fit) {
        self.urlString = urlString
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if hasFailed {
                Rectangle()
                    .fill(Color.gray.opacity(0.1))
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(Color.gray)
                    }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: urlString) { _, _ in
            image = nil
            isLoading = true
            hasFailed = false
            loadImage()
        }
    }

    private func loadImage() {
        // 判断是否为本地路径（相对路径或 file:// URL）
        let isLocalPath = ImageStorageService.isRelativePath(urlString) ||
                          (URL(string: urlString)?.isFileURL == true)

        if isLocalPath {
            // 本地图片：使用 ImageStorageService 加载
            if let loadedImage = ImageStorageService.shared.loadImage(from: urlString) {
                image = loadedImage
                isLoading = false
            } else {
                hasFailed = true
                isLoading = false
            }
        } else if let url = URL(string: urlString) {
            // 远程 URL：异步加载
            Task {
                if let loadedImage = await ImageStorageService.shared.getImage(from: url) {
                    self.image = loadedImage
                } else {
                    self.hasFailed = true
                }
                self.isLoading = false
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CachedAsyncImage(urlString: "https://picsum.photos/400/300", contentMode: .fit)
            .frame(height: 200)
        
        CachedAsyncImage(urlString: "https://example.com/invalid.jpg", contentMode: .fit)
            .frame(height: 200)
    }
}