//
//  ImageStorageService.swift
//  MindCanvas
//
//  图片本地存储服务
//  负责管理所有图片的本地存储，支持从远程URL下载并保存到本地
//

import Foundation
import UIKit

@MainActor
final class ImageStorageService {

    // MARK: - Singleton

    static let shared = ImageStorageService()

    private init() {
        setupMemoryCache()
    }

    // MARK: - Memory Cache

    /// 内存缓存，用于快速加载已加载过的图片
    private lazy var memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100  // 最多缓存100张图片
        cache.totalCostLimit = 50 * 1024 * 1024  // 最多50MB
        return cache
    }()

    /// 设置内存缓存策略
    private func setupMemoryCache() {
        // 监听内存警告，自动清理缓存
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    /// 处理内存警告
    @objc private func handleMemoryWarning() {
        print("[ImageStorageService] 收到内存警告，清理图片缓存")
        memoryCache.removeAllObjects()
    }

    // MARK: - URLSession

    /// 自定义 URLSession，用于下载图片
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 180
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    // MARK: - Properties

    /// 图片存储子目录名称
    private static let imagesSubdirectory = "images"

    /// 存储目录
    private lazy var storageDirectory: URL = {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = urls[0]

        // 创建 images 子目录
        let imagesDirectory = documentsDirectory.appendingPathComponent(Self.imagesSubdirectory)

        // 如果目录不存在则创建
        if !fileManager.fileExists(atPath: imagesDirectory.path) {
            try? fileManager.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        }

        return imagesDirectory
    }()
    
    // MARK: - Public Methods
    
    /// 保存图片数据到本地
    /// - Parameters:
    ///   - imageData: 图片数据
    ///   - fileName: 文件名（可选，如果不提供则自动生成）
    /// - Returns: 本地文件URL
    func saveImage(_ imageData: Data, fileName: String? = nil) -> URL? {
        let fileManager = FileManager.default

        // 确保目录存在
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            do {
                try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            } catch {
                print("[ImageStorageService] 创建存储目录失败: \(error)")
                return nil
            }
        }

        // 生成文件名
        let finalFileName = fileName ?? "\(UUID().uuidString).jpg"
        let fileURL = storageDirectory.appendingPathComponent(finalFileName)

        // 保存文件
        do {
            try imageData.write(to: fileURL)

            // 验证文件是否真的存在
            if fileManager.fileExists(atPath: fileURL.path) {
                return fileURL
            } else {
                print("[ImageStorageService] 警告：文件保存后验证失败，文件不存在")
                return nil
            }
        } catch {
            print("[ImageStorageService] 保存图片失败: \(error)")
            return nil
        }
    }
    
    /// 保存 UIImage 到本地
    /// - Parameters:
    ///   - image: UIImage 对象
    ///   - fileName: 文件名（可选）
    /// - Returns: 本地文件URL
    func saveImage(_ image: UIImage, fileName: String? = nil) -> URL? {
        // 使用最高质量的 JPEG 压缩
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            print("[ImageStorageService] 无法转换图片数据")
            return nil
        }
        return saveImage(imageData, fileName: fileName)
    }

    /// 保存图片数据并返回相对路径（推荐使用）
    /// - Parameters:
    ///   - imageData: 图片数据
    ///   - fileName: 文件名（可选，如果不提供则自动生成）
    /// - Returns: 相对路径字符串（如 "images/xxx.png"），失败返回 nil
    func saveImageWithRelativePath(_ imageData: Data, fileName: String? = nil) -> String? {
        guard let fileURL = saveImage(imageData, fileName: fileName) else {
            return nil
        }
        // 返回相对路径
        return "\(Self.imagesSubdirectory)/\(fileURL.lastPathComponent)"
    }

    /// 保存 UIImage 并返回相对路径
    /// - Parameters:
    ///   - image: UIImage 对象
    ///   - fileName: 文件名（可选）
    /// - Returns: 相对路径字符串（如 "images/xxx.png"），失败返回 nil
    func saveImageWithRelativePath(_ image: UIImage, fileName: String? = nil) -> String? {
        guard let imageData = image.jpegData(compressionQuality: 1.0) else {
            print("[ImageStorageService] 无法转换图片数据")
            return nil
        }
        return saveImageWithRelativePath(imageData, fileName: fileName)
    }
    
    /// 从远程URL下载图片并保存到本地
    /// - Parameter remoteURL: 远程图片URL
    /// - Returns: 本地文件URL
    func downloadAndSaveImage(from remoteURL: URL) async -> URL? {
        do {
            // 下载数据
            let (data, response) = try await downloadSession.data(from: remoteURL)

            // 验证响应
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  !data.isEmpty else {
                print("[ImageStorageService] 下载失败或数据为空")
                return nil
            }

            // 验证是否为有效图片
            guard UIImage(data: data) != nil else {
                print("[ImageStorageService] 下载的数据不是有效的图片")
                return nil
            }

            // 生成文件名（使用原始文件名或UUID）
            let fileName: String
            if let suggestedFilename = response.suggestedFilename, !suggestedFilename.isEmpty {
                fileName = suggestedFilename
            } else {
                fileName = "\(UUID().uuidString).jpg"
            }

            // 保存到本地
            return saveImage(data, fileName: fileName)

        } catch {
            print("[ImageStorageService] 下载图片失败: \(error)")
            return nil
        }
    }

    /// 从远程URL下载图片并保存到本地，返回相对路径
    /// - Parameter remoteURL: 远程图片URL
    /// - Returns: 相对路径字符串（如 "images/xxx.png"），失败返回 nil
    func downloadAndSaveImageWithRelativePath(from remoteURL: URL) async -> String? {
        print("[ImageStorageService] 开始下载图片到本地: \(remoteURL.absoluteString)")

        do {
            // 下载数据
            let (data, response) = try await downloadSession.data(from: remoteURL)
            print("[ImageStorageService] 下载完成，数据大小: \(data.count) bytes")

            // 验证响应
            guard let httpResponse = response as? HTTPURLResponse else {
                print("[ImageStorageService] 下载失败：响应不是HTTP响应")
                return nil
            }

            guard httpResponse.statusCode == 200, !data.isEmpty else {
                print("[ImageStorageService] 下载失败或数据为空，状态码: \(httpResponse.statusCode)")
                return nil
            }

            // 验证是否为有效图片
            guard UIImage(data: data) != nil else {
                print("[ImageStorageService] 下载的数据不是有效的图片")
                return nil
            }

            // 生成文件名（使用原始文件名或UUID）
            let fileName: String
            if let suggestedFilename = response.suggestedFilename, !suggestedFilename.isEmpty {
                fileName = suggestedFilename
            } else {
                fileName = "\(UUID().uuidString).jpg"
            }

            print("[ImageStorageService] 生成文件名: \(fileName)")

            // 保存到本地并返回相对路径
            if let relativePath = saveImageWithRelativePath(data, fileName: fileName) {
                print("[ImageStorageService] 图片保存成功: \(relativePath)")
                return relativePath
            } else {
                print("[ImageStorageService] 图片保存失败")
                return nil
            }

        } catch {
            print("[ImageStorageService] 下载图片失败: \(error)")
            return nil
        }
    }

    /// 从远程URL字符串下载图片并保存到本地
    /// - Parameter urlString: 远程图片URL字符串
    /// - Returns: 本地文件URL
    func downloadAndSaveImage(from urlString: String) async -> URL? {
        guard let url = URL(string: urlString) else {
            print("[ImageStorageService] 无效的URL: \(urlString)")
            return nil
        }
        return await downloadAndSaveImage(from: url)
    }
    
    /// 从本地文件URL加载图片
    /// - Parameter fileURL: 本地文件URL
    /// - Returns: UIImage 对象
    func loadImage(from fileURL: URL) -> UIImage? {
        guard fileURL.isFileURL else {
            return nil
        }

        // 【优先】尝试从内存缓存加载
        let cacheKey = fileURL.path as NSString
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            print("[ImageStorageService] 从内存缓存加载图片: \(fileURL.lastPathComponent)")
            return cachedImage
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            print("[ImageStorageService] 文件不存在: \(fileURL.path)")
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            print("[ImageStorageService] 读取文件失败: \(fileURL.path)")
            return nil
        }

        guard let image = UIImage(data: data) else {
            print("[ImageStorageService] 图片数据无效: \(fileURL.path)")
            return nil
        }

        // 加载成功后存入内存缓存，使用文件大小作为cost
        let imageSize = data.count
        memoryCache.setObject(image, forKey: cacheKey, cost: imageSize)
        print("[ImageStorageService] 从磁盘加载图片并存入缓存: \(fileURL.lastPathComponent), 大小: \(imageSize) bytes")

        return image
    }
    
    /// 从本地文件URL字符串加载图片
    /// - Parameter fileURLString: 本地文件URL字符串
    /// - Returns: UIImage 对象
    func loadImage(from fileURLString: String) -> UIImage? {
        print("[ImageStorageService] 尝试加载图片: \(fileURLString)")

        // 【优先】尝试从内存缓存加载
        let cacheKey = fileURLString as NSString
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            print("[ImageStorageService] 从内存缓存加载图片（使用原始字符串）: \(fileURLString)")
            return cachedImage
        }

        // 1. 尝试作为相对路径处理
        if !fileURLString.hasPrefix("/") && !fileURLString.hasPrefix("file://") && !fileURLString.hasPrefix("http://") && !fileURLString.hasPrefix("https://") {
            let fullURL = resolveRelativePath(fileURLString)
            print("[ImageStorageService] 尝试相对路径解析: \(fileURLString) -> \(fullURL.path)")
            if let image = loadImage(from: fullURL) {
                // 存入内存缓存（使用原始字符串作为key），计算cost
                let cost: Int
                if let imageData = try? Data(contentsOf: fullURL) {
                    cost = imageData.count
                } else {
                    cost = 0
                }
                memoryCache.setObject(image, forKey: cacheKey, cost: cost)
                return image
            }
        }

        // 2. 尝试作为 file:// URL 处理
        if let url = URL(string: fileURLString), url.isFileURL {
            print("[ImageStorageService] 尝试file:// URL: \(fileURLString)")
            // 先尝试原路径
            if let image = loadImage(from: url) {
                let cost: Int
                if let imageData = try? Data(contentsOf: url) {
                    cost = imageData.count
                } else {
                    cost = 0
                }
                memoryCache.setObject(image, forKey: cacheKey, cost: cost)
                return image
            }
            // 路径失效时，尝试从文件名恢复
            let fileName = url.lastPathComponent
            let recoveredURL = storageDirectory.appendingPathComponent(fileName)
            print("[ImageStorageService] 尝试从文件名恢复: \(fileName)")
            if FileManager.default.fileExists(atPath: recoveredURL.path) {
                if let image = loadImage(from: recoveredURL) {
                    let cost: Int
                    if let imageData = try? Data(contentsOf: recoveredURL) {
                        cost = imageData.count
                    } else {
                        cost = 0
                    }
                    memoryCache.setObject(image, forKey: cacheKey, cost: cost)
                    return image
                }
            }
        }

        // 3. 尝试作为纯文件路径处理
        let fileURL = URL(fileURLWithPath: fileURLString)
        print("[ImageStorageService] 尝试纯文件路径: \(fileURL.path)")
        if let image = loadImage(from: fileURL) {
            let cost: Int
            if let imageData = try? Data(contentsOf: fileURL) {
                cost = imageData.count
            } else {
                cost = 0
            }
            memoryCache.setObject(image, forKey: cacheKey, cost: cost)
            return image
        }

        // 4. 最后尝试从文件名恢复
        let fileName = (fileURLString as NSString).lastPathComponent
        let recoveredURL = storageDirectory.appendingPathComponent(fileName)
        print("[ImageStorageService] 最后尝试从文件名恢复: \(fileName)")
        if FileManager.default.fileExists(atPath: recoveredURL.path) {
            if let image = loadImage(from: recoveredURL) {
                let cost: Int
                if let imageData = try? Data(contentsOf: recoveredURL) {
                    cost = imageData.count
                } else {
                    cost = 0
                }
                memoryCache.setObject(image, forKey: cacheKey, cost: cost)
                return image
            }
        }

        print("[ImageStorageService] 加载图片失败: \(fileURLString)")
        return nil
    }
    
    /// 删除本地图片文件
    /// - Parameter fileURL: 本地文件URL
    /// - Returns: 是否删除成功
    func deleteImage(at fileURL: URL) -> Bool {
        guard fileURL.isFileURL else {
            return false
        }
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            print("[ImageStorageService] 删除图片失败: \(error)")
            return false
        }
    }
    
    /// 删除本地图片文件
    /// - Parameter fileURLString: 本地文件URL字符串
    /// - Returns: 是否删除成功
    func deleteImage(at fileURLString: String) -> Bool {
        // 优先尝试作为URL字符串解析（处理 file:// 开头的完整URL）
        if let url = URL(string: fileURLString) {
            if deleteImage(at: url) {
                return true
            }
        }
        // 尝试作为文件路径解析（处理纯路径字符串）
        let fileURL = URL(fileURLWithPath: fileURLString)
        return deleteImage(at: fileURL)
    }
    
    /// 获取存储目录的总大小（字节）
    /// - Returns: 存储目录大小
    func getStorageSize() -> Int64 {
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(at: storageDirectory,
                                                      includingPropertiesForKeys: [.fileSizeKey],
                                                      options: []) else {
            return 0
        }
        
        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    /// 清空所有存储的图片
    /// - Returns: 是否清理成功
    func clearAllImages() -> Bool {
        let fileManager = FileManager.default
        
        do {
            let files = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
            
            for fileURL in files {
                try fileManager.removeItem(at: fileURL)
            }
            
            return true
        } catch {
            print("[ImageStorageService] 清空图片失败: \(error)")
            return false
        }
    }
    
    /// 检查本地文件是否存在
    /// - Parameter fileURL: 本地文件URL
    /// - Returns: 文件是否存在
    func fileExists(at fileURL: URL) -> Bool {
        guard fileURL.isFileURL else {
            return false
        }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    /// 检查本地文件是否存在
    /// - Parameter fileURLString: 本地文件URL字符串
    /// - Returns: 文件是否存在
    func fileExists(at fileURLString: String) -> Bool {
        // 优先尝试作为URL字符串解析（处理 file:// 开头的完整URL）
        if let url = URL(string: fileURLString) {
            if fileExists(at: url) {
                return true
            }
        }
        // 尝试作为文件路径解析（处理纯路径字符串）
        let fileURL = URL(fileURLWithPath: fileURLString)
        return fileExists(at: fileURL)
    }

    /// 列出存储目录中的所有文件（用于调试）
    func listAllFiles() {
        let fileManager = FileManager.default
        print("[ImageStorageService] 存储目录: \(storageDirectory.path)")

        if let files = try? fileManager.contentsOfDirectory(atPath: storageDirectory.path) {
            print("[ImageStorageService] 找到 \(files.count) 个文件:")
            for file in files {
                let filePath = storageDirectory.appendingPathComponent(file).path
                if let attributes = try? fileManager.attributesOfItem(atPath: filePath) {
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    print("[ImageStorageService]   - \(file) (\(fileSize) bytes)")
                }
            }
        } else {
            print("[ImageStorageService] 无法读取存储目录")
        }
    }

    /// 列出内存缓存中的所有图片（用于调试）
    func listMemoryCacheInfo() {
        print("[ImageStorageService] 内存缓存信息:")
        print("[ImageStorageService]   - 数量限制: \(memoryCache.countLimit)")
        print("[ImageStorageService]   - 大小限制: \(memoryCache.totalCostLimit) bytes")
        // 注意：NSCache不提供当前数量和大小的公开API
        print("[ImageStorageService]   - 当前数量: (不可用)")
        print("[ImageStorageService]   - 当前大小: (不可用)")
    }
    
    /// 从远程URL获取图片（优先使用本地缓存）
    /// - Parameter remoteURL: 远程图片URL
    /// - Returns: UIImage 对象
    func getImage(from remoteURL: URL) async -> UIImage? {
        print("[ImageStorageService] 从远程URL获取图片: \(remoteURL.absoluteString)")

        // 【优先】尝试从内存缓存加载
        let cacheKey = remoteURL.absoluteString as NSString
        if let cachedImage = memoryCache.object(forKey: cacheKey) {
            print("[ImageStorageService] 从内存缓存加载图片（远程URL）: \(remoteURL.lastPathComponent)")
            return cachedImage
        }

        // 尝试从磁盘缓存加载
        if let cachedURL = getCachedURL(for: remoteURL),
           let cachedImage = loadImage(from: cachedURL) {
            // 存入内存缓存，计算cost
            let cost: Int
            if let imageData = try? Data(contentsOf: cachedURL) {
                cost = imageData.count
            } else {
                cost = 0
            }
            memoryCache.setObject(cachedImage, forKey: cacheKey, cost: cost)
            return cachedImage
        }

        // 下载并缓存
        print("[ImageStorageService] 开始下载图片: \(remoteURL.absoluteString)")
        if let downloadedURL = await downloadAndSaveImage(from: remoteURL),
           let downloadedImage = loadImage(from: downloadedURL) {
            // 存入内存缓存，计算cost
            let cost: Int
            if let imageData = try? Data(contentsOf: downloadedURL) {
                cost = imageData.count
            } else {
                cost = 0
            }
            memoryCache.setObject(downloadedImage, forKey: cacheKey, cost: cost)
            return downloadedImage
        }

        print("[ImageStorageService] 下载图片失败: \(remoteURL.absoluteString)")
        return nil
    }
    
    /// 从远程URL字符串获取图片（优先使用本地缓存）
    /// - Parameter urlString: 远程图片URL字符串
    /// - Returns: UIImage 对象
    func getImage(from urlString: String) async -> UIImage? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        return await getImage(from: url)
    }

    // MARK: - Static Utility Methods

    /// 检查路径是否为相对路径
    /// - Parameter path: 路径字符串
    /// - Returns: 是否为相对路径
    static func isRelativePath(_ path: String) -> Bool {
        return !path.hasPrefix("/") && !path.hasPrefix("file://") && !path.hasPrefix("http://") && !path.hasPrefix("https://")
    }

    /// 从绝对路径提取相对路径
    /// - Parameter absolutePath: 绝对路径
    /// - Returns: 相对路径字符串（如 "images/xxx.png"），失败返回 nil
    static func extractRelativePath(from absolutePath: String) -> String? {
        // 查找 "images/" 子串
        if let range = absolutePath.range(of: "\(imagesSubdirectory)/") {
            return String(absolutePath[range.lowerBound...])
        }
        // 如果只有文件名
        let fileName = (absolutePath as NSString).lastPathComponent
        if !fileName.isEmpty && fileName != absolutePath {
            return "\(imagesSubdirectory)/\(fileName)"
        }
        return nil
    }

    // MARK: - Private Methods

    /// 将相对路径解析为完整 URL
    /// - Parameter relativePath: 相对路径（如 "images/xxx.png"）
    /// - Returns: 完整的文件 URL
    private func resolveRelativePath(_ relativePath: String) -> URL {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsURL.appendingPathComponent(relativePath)
    }

    /// 获取远程URL对应的缓存URL
    /// - Parameter remoteURL: 远程URL
    /// - Returns: 本地缓存URL（如果存在）
    private func getCachedURL(for remoteURL: URL) -> URL? {
        // 使用URL的hash作为文件名
        let hash = remoteURL.absoluteString.hash
        let fileName = "cached_\(abs(hash)).jpg"
        let cachedURL = storageDirectory.appendingPathComponent(fileName)
        
        // 检查文件是否存在
        if fileExists(at: cachedURL) {
            return cachedURL
        }
        
        return nil
    }
}