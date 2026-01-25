# 图片存储路径修复方案 v1.0

## 问题描述

### 现象
应用重启后，之前保存的图片无法加载，日志显示"文件不存在"：

```
[ImageStorageService] 文件不存在: .../Application/4C69D411-.../Documents/images/xxx.png
[ImageStorageService] 存储目录: .../Application/84693652-.../Documents/images
```

### 根本原因
`LayerNode.url` 存储的是**完整绝对路径**（包含 Application Container UUID）。iOS 在以下情况会分配新的 Container UUID：

| 场景 | 模拟器 | 真机 |
|------|--------|------|
| Xcode Build & Run | 可能变化 | 通常稳定 |
| 卸载重装应用 | UUID 变化 | UUID 变化 |
| 从备份恢复 | - | 可能变化 |
| iOS 系统更新 | - | 可能变化 |
| 迁移到新设备 | - | UUID 变化 |

### 影响范围
- 用户上传的图片 (`NodeType.userImage`)
- AI 生成的图片 (`NodeType.aiGenerated`)
- 所有持久化存储的 `LayerNode` 数据

---

## 解决方案

### 核心思路
**存储相对路径，加载时动态拼接完整路径**

- 保存时：只存储相对路径（如 `images/xxx.png`）
- 加载时：动态获取当前 Documents 目录 + 相对路径

### 方案对比

| 方案 | 优点 | 缺点 |
|------|------|------|
| A. 修改存储逻辑 | 根本解决，符合 Apple 规范 | 需要处理旧数据兼容 |
| B. 加载时路径修复 | 改动小，向后兼容 | 治标不治本 |
| C. 混合方案 | 兼顾新旧数据 | 代码稍复杂 |

**推荐方案 C（混合方案）**：新数据存相对路径，加载时兼容新旧两种格式。

---

## 详细设计

### 1. ImageStorageService 修改

#### 1.1 新增相对路径常量
```swift
// ImageStorageService.swift

/// 图片存储子目录名称
private static let imagesSubdirectory = "images"
```

#### 1.2 新增返回相对路径的保存方法
```swift
/// 保存图片并返回相对路径（推荐使用）
/// - Parameters:
///   - imageData: 图片数据
///   - fileName: 文件名（可选）
/// - Returns: 相对路径字符串（如 "images/xxx.png"），失败返回 nil
func saveImageWithRelativePath(_ imageData: Data, fileName: String? = nil) -> String? {
    guard let fileURL = saveImage(imageData, fileName: fileName) else {
        return nil
    }
    // 返回相对路径
    return "\(Self.imagesSubdirectory)/\(fileURL.lastPathComponent)"
}

/// 保存 UIImage 并返回相对路径
func saveImageWithRelativePath(_ image: UIImage, fileName: String? = nil) -> String? {
    guard let imageData = image.jpegData(compressionQuality: 1.0) else {
        return nil
    }
    return saveImageWithRelativePath(imageData, fileName: fileName)
}
```

#### 1.3 修改加载方法支持相对路径
```swift
/// 从路径字符串加载图片（支持相对路径和绝对路径）
/// - Parameter pathString: 路径字符串
/// - Returns: UIImage 对象
func loadImage(from pathString: String) -> UIImage? {
    // 1. 尝试作为相对路径处理
    if !pathString.hasPrefix("/") && !pathString.hasPrefix("file://") {
        let fullURL = resolveRelativePath(pathString)
        if let image = loadImage(from: fullURL) {
            return image
        }
    }

    // 2. 尝试作为 file:// URL 处理
    if let url = URL(string: pathString), url.isFileURL {
        // 先尝试原路径
        if let image = loadImage(from: url) {
            return image
        }
        // 路径失效时，尝试从文件名恢复
        let fileName = url.lastPathComponent
        let recoveredURL = storageDirectory.appendingPathComponent(fileName)
        if let image = loadImage(from: recoveredURL) {
            print("[ImageStorageService] 路径恢复成功: \(fileName)")
            return image
        }
    }

    // 3. 尝试作为纯文件路径处理
    let fileURL = URL(fileURLWithPath: pathString)
    if let image = loadImage(from: fileURL) {
        return image
    }

    // 4. 最后尝试从文件名恢复
    let fileName = (pathString as NSString).lastPathComponent
    let recoveredURL = storageDirectory.appendingPathComponent(fileName)
    return loadImage(from: recoveredURL)
}

/// 将相对路径解析为完整 URL
private func resolveRelativePath(_ relativePath: String) -> URL {
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return documentsURL.appendingPathComponent(relativePath)
}
```

#### 1.4 新增路径检测工具方法
```swift
/// 检查路径是否为相对路径
static func isRelativePath(_ path: String) -> Bool {
    !path.hasPrefix("/") && !path.hasPrefix("file://")
}

/// 从绝对路径提取相对路径
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
```

---

### 2. SelectableImageView 修改

#### 2.1 修改 loadImage 方法
```swift
// SelectableImageView.swift

private func loadImage() {
    guard let urlString = layerNode.url else { return }

    // 使用 ImageStorageService 统一处理路径
    // 支持：相对路径、绝对路径、file:// URL、远程 URL

    // 判断是否为本地路径（相对路径或 file:// URL）
    let isLocalPath = ImageStorageService.isRelativePath(urlString) ||
                      (URL(string: urlString)?.isFileURL == true)

    if isLocalPath {
        // 本地图片：使用 ImageStorageService 加载
        if let image = ImageStorageService.shared.loadImage(from: urlString) {
            imageView.image = image
            handleImageLoaded(image)
        } else {
            print("[SelectableImageView] 无法加载本地图片: \(urlString)")
        }
    } else if let url = URL(string: urlString) {
        // 远程 URL：异步加载
        Task { @MainActor in
            if let image = await ImageStorageService.shared.getImage(from: url) {
                self.imageView.image = image
                self.handleImageLoaded(image)
            } else {
                print("[SelectableImageView] 无法加载远程图片: \(urlString)")
            }
        }
    }
}
```

---

### 3. 调用方修改

所有保存图片的地方，改用 `saveImageWithRelativePath` 方法：

#### 3.1 NativeEditorViewModel（或其他保存图片的地方）

```swift
// 修改前
if let localURL = ImageStorageService.shared.saveImage(image) {
    let node = LayerNode.userImage(url: localURL.absoluteString, ...)
}

// 修改后
if let relativePath = ImageStorageService.shared.saveImageWithRelativePath(image) {
    let node = LayerNode.userImage(url: relativePath, ...)
}
```

需要检查并修改的文件：
- `NativeEditorViewModel.swift` - 用户上传图片
- 其他可能保存图片的地方

---

### 4. 数据迁移（可选）

如果需要修复已有的旧数据，可以在应用启动时执行一次迁移：

```swift
/// 迁移旧的绝对路径为相对路径
func migrateAbsolutePathsToRelative(layerNodes: inout [LayerNode]) {
    for i in layerNodes.indices {
        guard let url = layerNodes[i].url else { continue }

        // 如果是绝对路径，转换为相对路径
        if !ImageStorageService.isRelativePath(url) {
            if let relativePath = ImageStorageService.extractRelativePath(from: url) {
                layerNodes[i] = LayerNode(
                    id: layerNodes[i].id,
                    type: layerNodes[i].type,
                    url: relativePath,  // 使用相对路径
                    frame: layerNodes[i].frame,
                    originalSize: layerNodes[i].originalSize,
                    rotation: layerNodes[i].rotation,
                    isLocked: layerNodes[i].isLocked,
                    zIndex: layerNodes[i].zIndex,
                    opacity: layerNodes[i].opacity,
                    createdAt: layerNodes[i].createdAt
                )
            }
        }
    }
}
```

---

## 实现步骤

### Phase 1: 核心修复
1. [ ] 修改 `ImageStorageService.swift`
   - 添加 `saveImageWithRelativePath` 方法
   - 修改 `loadImage(from:)` 支持相对路径和路径恢复
   - 添加工具方法 `isRelativePath`、`extractRelativePath`

2. [ ] 修改 `SelectableImageView.swift`
   - 更新 `loadImage()` 方法使用新的加载逻辑

### Phase 2: 调用方修改
3. [ ] 搜索所有调用 `saveImage` 的地方，改用 `saveImageWithRelativePath`
4. [ ] 确保新保存的图片使用相对路径

### Phase 3: 测试验证
5. [ ] 模拟器测试：保存图片 -> 重新 Build & Run -> 验证图片加载
6. [ ] 真机测试：保存图片 -> 卸载重装 -> 验证图片加载（预期失败，因为数据被清除）
7. [ ] 兼容性测试：旧绝对路径数据能否正常加载

---

## 测试用例

### TC1: 新图片保存和加载
1. 添加一张图片到画布
2. 验证 `LayerNode.url` 为相对路径格式（如 `images/xxx.jpg`）
3. 重启应用，验证图片正常显示

### TC2: 模拟器路径变化
1. 添加图片到画布
2. 在 Xcode 中 Clean Build Folder
3. 重新 Build & Run
4. 验证图片正常显示（通过路径恢复机制）

### TC3: 旧数据兼容
1. 使用旧版本保存图片（绝对路径）
2. 升级到新版本
3. 验证旧图片能正常加载

### TC4: 远程图片不受影响
1. 添加远程 URL 图片
2. 验证远程图片正常加载
3. 验证缓存机制正常工作

---

## 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| 旧数据无法加载 | 低 | 高 | 路径恢复机制兜底 |
| 远程 URL 误判为本地路径 | 低 | 中 | 明确的路径判断逻辑 |
| 性能影响 | 极低 | 低 | 路径解析开销可忽略 |

---

## 参考资料

- [Apple File System Programming Guide - Accessing Files and Directories](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/AccessingFilesandDirectories/AccessingFilesandDirectories.html)
- Apple 建议：不要持久化存储绝对路径，应使用相对于已知目录的路径

---

## 文档信息

- **版本**: v1.0
- **创建日期**: 2025-01-25
- **状态**: 待实现
- **优先级**: 高（影响用户数据持久化）
