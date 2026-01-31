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
    let localPath: String?
    let contentMode: ContentMode
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var hasFailed = false

    init(urlString: String, localPath: String? = nil, contentMode: ContentMode = .fit) {
        self.urlString = urlString
        self.localPath = localPath
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
            } else if hasFailed {
                ZStack {
                    Color(white: 0.95)
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title2)
                            .foregroundStyle(Color.orange)
                        Text("加载失败")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    Color(white: 0.97)
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("加载中")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(white: 0.5))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        if let localPath = localPath {
            if let loadedImage = ImageStorageService.shared.loadImage(from: localPath) {
                image = loadedImage
                isLoading = false
                return
            }
        }

        let isLocalPath = ImageStorageService.isRelativePath(urlString) ||
                          (URL(string: urlString)?.isFileURL == true)

        if isLocalPath {
            if let loadedImage = ImageStorageService.shared.loadImage(from: urlString) {
                image = loadedImage
                isLoading = false
            } else {
                hasFailed = true
                isLoading = false
            }
        } else if let url = URL(string: urlString) {
            Task {
                if let loadedImage = await ImageStorageService.shared.getImage(from: url) {
                    await MainActor.run {
                        self.image = loadedImage
                        self.isLoading = false
                    }
                } else {
                    await MainActor.run {
                        self.hasFailed = true
                        self.isLoading = false
                    }
                }
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