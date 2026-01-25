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
    
    private init() {}
    
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
            let (data, response) = try await URLSession.shared.data(from: remoteURL)

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
        do {
            // 下载数据
            let (data, response) = try await URLSession.shared.data(from: remoteURL)

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

            // 保存到本地并返回相对路径
            return saveImageWithRelativePath(data, fileName: fileName)

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

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        guard let image = UIImage(data: data) else {
            return nil
        }

        return image
    }
    
    /// 从本地文件URL字符串加载图片
    /// - Parameter fileURLString: 本地文件URL字符串
    /// - Returns: UIImage 对象
    func loadImage(from fileURLString: String) -> UIImage? {
        // 1. 尝试作为相对路径处理
        if !fileURLString.hasPrefix("/") && !fileURLString.hasPrefix("file://") && !fileURLString.hasPrefix("http://") && !fileURLString.hasPrefix("https://") {
            let fullURL = resolveRelativePath(fileURLString)
            if let image = loadImage(from: fullURL) {
                return image
            }
        }

        // 2. 尝试作为 file:// URL 处理
        if let url = URL(string: fileURLString), url.isFileURL {
            // 先尝试原路径
            if let image = loadImage(from: url) {
                return image
            }
            // 路径失效时，尝试从文件名恢复
            let fileName = url.lastPathComponent
            let recoveredURL = storageDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: recoveredURL.path) {
                if let image = loadImage(from: recoveredURL) {
                    return image
                }
            }
        }

        // 3. 尝试作为纯文件路径处理
        let fileURL = URL(fileURLWithPath: fileURLString)
        if let image = loadImage(from: fileURL) {
            return image
        }

        // 4. 最后尝试从文件名恢复
        let fileName = (fileURLString as NSString).lastPathComponent
        let recoveredURL = storageDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: recoveredURL.path) {
            return loadImage(from: recoveredURL)
        }

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

        if let files = try? fileManager.contentsOfDirectory(atPath: storageDirectory.path) {
            for file in files {
                let filePath = storageDirectory.appendingPathComponent(file).path
                if let attributes = try? fileManager.attributesOfItem(atPath: filePath) {
                    let fileSize = attributes[.size] as? Int64 ?? 0
                }
            }
        }
    }
    
    /// 从远程URL获取图片（优先使用本地缓存）
    /// - Parameter remoteURL: 远程图片URL
    /// - Returns: UIImage 对象
    func getImage(from remoteURL: URL) async -> UIImage? {
        // 尝试从缓存加载
        if let cachedURL = getCachedURL(for: remoteURL),
           let cachedImage = loadImage(from: cachedURL) {
            return cachedImage
        }
        
        // 下载并缓存
        if let downloadedURL = await downloadAndSaveImage(from: remoteURL),
           let downloadedImage = loadImage(from: downloadedURL) {
            return downloadedImage
        }
        
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