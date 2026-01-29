# iOS 图片缓存最佳实践分析

## 行业标准实现

### 1. 主流图片缓存库对比

#### SDWebImage
- **内存缓存**: NSCache，自动清理
- **磁盘缓存**: 文件系统，使用 MD5 哈希作为文件名
- **异步加载**: URLSession，支持队列管理
- **图片解码**: 后台线程解码，避免主线程阻塞
- **缓存验证**: 响应头中的 ETag 和 Last-Modified

#### Kingfisher
- **内存缓存**: NSCache，支持成本计算
- **磁盘缓存**: 文件系统，使用 SHA1 哈希作为文件名
- **异步加载**: URLSession，支持优先级
- **图片解码**: 后台线程解码，支持降采样
- **缓存清理**: 支持过期时间、大小限制

#### SwiftUI AsyncImage
- **内存缓存**: URLCache (系统内置)
- **磁盘缓存**: URLCache (系统内置)
- **异步加载**: URLSession
- **局限性**: 无法自定义缓存策略

### 2. 最佳实践总结

#### 2.1 缓存层次结构

```
┌─────────────────────────────────────┐
│  第一层：内存缓存 (NSCache)          │
│  - 生命周期: App 运行期间            │
│  - 清理策略: 内存警告时自动清理       │
│  - 优点: 访问速度最快                │
└─────────────────────────────────────┘
                 ↓ 未命中
┌─────────────────────────────────────┐
│  第二层：磁盘缓存 (FileManager)     │
│  - 生命周期: 持久化保存              │
│  - 存储位置: Library/Caches 或 Documents
│  - 优点: App 重启后依然可用          │
└─────────────────────────────────────┘
                 ↓ 未命中
┌─────────────────────────────────────┐
│  第三层：网络下载 (URLSession)       │
│  - 支持断点续传                      │
│  - 支持响应式缓存 (304 Not Modified) │
│  - 缺点: 需要网络连接                │
└─────────────────────────────────────┘
```

#### 2.2 文件命名策略

**行业标准**：使用 URL 的哈希值作为文件名

```swift
// SDWebImage 使用 MD5 哈希
let fileName = MD5(url.absoluteString) + ".jpg"

// Kingfisher 使用 SHA1 哈希
let fileName = SHA1(url.absoluteString) + ".jpg"

// 优点:
// 1. 避免文件名冲突
// 2. 避免 URL 中的特殊字符问题
// 3. 统一命名规范，易于管理
// 4. 避免 URL 中的敏感信息泄露
```

**当前实现的问题**：
```swift
// ImageStorageService 使用原始文件名或 UUID
let fileName = suggestedFilename ?? "\(UUID().uuidString).jpg"

// 问题:
// 1. 如果使用 suggestedFilename，可能包含特殊字符
// 2. UUID 命名无法根据 URL 去重
// 3. 相同 URL 可能被多次下载并保存
```

#### 2.3 磁盘缓存验证机制

**行业标准做法**：

```swift
// 1. 保存时记录元数据
struct CacheMetadata: Codable {
    let url: String
    let createdAt: Date
    let expiresAt: Date?
    let fileSize: Int64
    let etag: String?
    let lastModified: String?
}

// 2. 验证缓存有效性
func isCacheValid(for url: URL) -> Bool {
    guard let metadata = loadMetadata(for: url) else {
        return false
    }

    // 检查文件是否存在
    guard FileManager.default.fileExists(atPath: cachePath(for: url)) else {
        return false
    }

    // 检查是否过期
    if let expiresAt = metadata.expiresAt, expiresAt < Date() {
        return false
    }

    // 检查文件大小是否匹配
    let attributes = try? FileManager.default.attributesOfItem(atPath: cachePath(for: url))
    let currentSize = attributes?[.size] as? Int64 ?? 0
    if currentSize != metadata.fileSize {
        return false
    }

    return true
}

// 3. 使用条件请求验证缓存
func loadImageWithValidation(url: URL) async throws -> UIImage? {
    if isCacheValid(for: url), let cachedImage = loadFromDisk(for: url) {
        // 尝试使用条件请求验证缓存是否最新
        var request = URLRequest(url: url)
        if let metadata = loadMetadata(for: url) {
            if let etag = metadata.etag {
                request.setValue(etag, forHTTPHeaderField: "If-None-Match")
            }
            if let lastModified = metadata.lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 304 {
            // 缓存仍然有效
            return cachedImage
        } else {
            // 缓存已过期，更新缓存
            if let newImage = UIImage(data: data) {
                saveToDisk(newImage, for: url, response: httpResponse)
                return newImage
            }
        }
    }

    // 缓存无效或不存在，重新下载
    return try await downloadImage(url: url)
}
```

**当前实现的问题**：
```swift
// ImageStorageService 缺少以下功能:
// 1. 没有缓存元数据记录
// 2. 没有过期时间管理
// 3. 没有文件完整性验证
// 4. 没有条件请求支持
```

#### 2.4 错误处理和重试机制

**行业标准做法**：

```swift
func downloadImageWithRetry(url: URL, maxRetries: Int = 3) async throws -> UIImage? {
    var lastError: Error?

    for attempt in 0..<maxRetries {
        do {
            // 计算指数退避延迟
            if attempt > 0 {
                let delay = pow(2.0, Double(attempt)) * 0.5
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ImageError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200...299:
                // 成功
                if let image = UIImage(data: data) {
                    return image
                } else {
                    throw ImageError.invalidImageData
                }
            case 304:
                // 缓存有效
                return loadFromDisk(for: url)
            case 400...499:
                // 客户端错误，不需要重试
                throw ImageError.clientError(httpResponse.statusCode)
            case 500...599:
                // 服务器错误，可以重试
                throw ImageError.serverError(httpResponse.statusCode)
            default:
                throw ImageError.unknownError(httpResponse.statusCode)
            }
        } catch let error as ImageError {
            lastError = error
            if case .clientError = error {
                // 客户端错误不需要重试
                throw error
            }
        } catch {
            lastError = error
        }
    }

    throw lastError ?? ImageError.downloadFailed
}
```

**当前实现的问题**：
```swift
// ImageStorageService 的重试逻辑在 ViewModel 层
// Service 层没有内置的重试机制
// 没有区分不同类型的错误
// 没有指数退避策略
```

#### 2.5 内存缓存管理

**行业标准做法**：

```swift
class ImageCache {
    private let memoryCache = NSCache<NSString, UIImage>()

    init() {
        // 设置缓存限制
        memoryCache.countLimit = 100  // 最多缓存100张图片
        memoryCache.totalCostLimit = 50 * 1024 * 1024  // 最多50MB

        // 监听内存警告
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearMemoryCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    func setImage(_ image: UIImage, for url: URL) {
        // 计算缓存成本（图片大小）
        let cost = image.jpegData(compressionQuality: 1.0)?.count ?? 0
        memoryCache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }

    func getImage(for url: URL) -> UIImage? {
        return memoryCache.object(forKey: url.absoluteString as NSString)
    }

    @objc private func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }
}
```

**当前实现的问题**：
```swift
// ImageStorageService 没有内存缓存层
// 每次加载都需要从磁盘读取
// 没有缓存成本计算
// 没有内存警告监听
```

#### 2.6 图片解码优化

**行业标准做法**：

```swift
func decodeImage(_ image: UIImage, for size: CGSize) -> UIImage? {
    // 在后台线程解码
    return autoreleasepool {
        guard let cgImage = image.cgImage else { return nil }

        let width = Int(size.width)
        let height = Int(size.height)

        // 创建颜色空间
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        // 创建位图上下文
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
        }

        // 绘制图片到上下文
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        // 创建解码后的图片
        guard let decodedCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: decodedCGImage)
    }
}
```

**当前实现的问题**：
```swift
// ImageStorageService 直接使用 UIImage(data:)
// 没有后台线程解码
// 没有降采样优化
// 可能导致主线程阻塞
```

### 3. App 重启后的缓存恢复

#### 3.1 行业标准做法

```swift
class ImageStorageService {
    private let cacheDirectory: URL
    private let metadataFile = "cache_metadata.json"

    init() {
        // 在 Library/Caches 目录下创建缓存目录
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cacheURL.appendingPathComponent("ImageCache")

        // 创建目录
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )

        // App 启动时验证缓存
        validateCacheOnLaunch()
    }

    private func validateCacheOnLaunch() {
        print("[ImageStorageService] App 启动，验证缓存...")

        guard let metadata = loadMetadata() else {
            print("[ImageStorageService] 没有缓存元数据")
            return
        }

        var validMetadata: [String: CacheMetadata] = [:]

        for (url, meta) in metadata {
            let filePath = cacheDirectory.appendingPathComponent(meta.fileName)

            // 验证文件是否存在
            guard FileManager.default.fileExists(atPath: filePath.path) else {
                print("[ImageStorageService] 缓存文件不存在: \(meta.fileName)")
                continue
            }

            // 验证文件大小
            if let attributes = try? FileManager.default.attributesOfItem(atPath: filePath.path),
               let fileSize = attributes[.size] as? Int64,
               fileSize == meta.fileSize {
                validMetadata[url] = meta
                print("[ImageStorageService] 缓存有效: \(meta.fileName)")
            } else {
                print("[ImageStorageService] 缓存文件大小不匹配: \(meta.fileName)")
            }
        }

        // 更新元数据
        saveMetadata(validMetadata)

        print("[ImageStorageService] 缓存验证完成，有效文件数: \(validMetadata.count)")
    }
}
```

#### 3.2 文件系统清理策略

```swift
class CacheCleanupService {
    static let shared = CacheCleanupService()

    func cleanupExpiredCache(maxAge: TimeInterval = 7 * 24 * 60 * 60) async {
        // 清理超过7天的缓存
        let now = Date()
        let cutoffDate = now.addingTimeInterval(-maxAge)

        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        ) else {
            return
        }

        var removedSize: Int64 = 0

        for file in files {
            if let resourceValues = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
               let creationDate = resourceValues.creationDate,
               creationDate < cutoffDate {
                let fileSize = resourceValues.fileSize ?? 0
                try? fileManager.removeItem(at: file)
                removedSize += Int64(fileSize)
            }
        }

        print("[CacheCleanupService] 清理完成，释放空间: \(removedSize / 1024 / 1024) MB")
    }

    func cleanupCacheOverLimit(maxSize: Int64 = 100 * 1024 * 1024) async {
        // 清理超过100MB的缓存（LRU策略）
        var totalSize: Int64 = 0
        var files: [(URL, Date, Int64)] = []

        let fileManager = FileManager.default
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        ) else {
            return
        }

        for file in fileURLs {
            if let resourceValues = try? file.resourceValues(forKeys: [.creationDateKey, .fileSizeKey]),
               let creationDate = resourceValues.creationDate,
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
                files.append((file, creationDate, fileSize))
            }
        }

        if totalSize > maxSize {
            // 按创建时间排序（最旧的优先删除）
            files.sort { $0.1 < $1.1 }

            var removedSize: Int64 = 0
            let targetSize = maxSize * 80 / 100  // 清理到80%

            for (file, _, fileSize) in files {
                if totalSize - removedSize > targetSize {
                    try? fileManager.removeItem(at: file)
                    removedSize += Int64(fileSize)
                } else {
                    break
                }
            }

            print("[CacheCleanupService] 清理完成，释放空间: \(removedSize / 1024 / 1024) MB")
        }
    }
}
```

### 4. 关键发现和建议

#### 4.1 当前实现的主要问题

1. **缺少内存缓存层**
   - 每次加载都需要从磁盘读取
   - 重复加载相同图片时效率低下

2. **文件命名策略不完善**
   - 使用原始文件名可能导致冲突
   - UUID 命名无法根据 URL 去重

3. **缺少缓存验证机制**
   - 没有缓存元数据
   - 没有过期时间管理
   - 没有文件完整性验证

4. **错误处理不完善**
   - 没有详细的错误日志
   - 重试逻辑在 ViewModel 层
   - 没有区分不同类型的错误

5. **缺少图片解码优化**
   - 在主线程解码
   - 没有降采样

6. **缺少缓存清理策略**
   - 没有过期清理
   - 没有大小限制

#### 4.2 改进建议

**短期改进**：
1. 添加详细的调试日志
2. 添加文件存在性验证
3. 添加缓存元数据记录
4. 改进错误处理和日志

**中期改进**：
1. 添加内存缓存层
2. 改进文件命名策略（使用 URL 哈希）
3. 添加缓存验证机制
4. 添加重试逻辑到 Service 层

**长期改进**：
1. 考虑使用成熟的图片缓存库（Kingfisher）
2. 添加图片解码优化
3. 添加缓存清理策略
4. 添加预加载机制

### 5. 推荐方案

#### 方案A: 使用 Kingfisher（推荐）

**优点**：
- 成熟稳定，广泛使用
- 完整的缓存管理
- 优秀的性能优化
- 活跃的社区支持

**缺点**：
- 需要引入第三方依赖
- 需要一定的学习成本

**示例代码**：
```swift
import Kingfisher

struct CachedAsyncImage: View {
    let urlString: String
    let contentMode: ContentMode

    var body: some View {
        KFImage(URL(string: urlString))
            .cacheMemoryOnly()
            .loadDiskFileSynchronously()
            .resizable()
            .aspectRatio(contentMode: contentMode)
    }
}
```

#### 方案B: 改进 ImageStorageService

**优点**：
- 无需引入第三方依赖
- 完全可控
- 可以根据需求定制

**缺点**：
- 需要大量开发工作
- 可能存在未发现的边界情况

**改进要点**：
1. 添加内存缓存层
2. 改进文件命名策略
3. 添加缓存验证机制
4. 改进错误处理
5. 添加图片解码优化
6. 添加缓存清理策略

### 6. 参考资源

- SDWebImage: https://github.com/SDWebImage/SDWebImage
- Kingfisher: https://github.com/onevcat/Kingfisher
- Nuke: https://github.com/kean/Nuke
- Apple URLCache Documentation: https://developer.apple.com/documentation/foundation/urlcache