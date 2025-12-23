# 图片选择器终极修复方案 v2.0

> 时间: 2025-12-23
> 版本: v2.0 (基于 v1.0 失败经验)
> 状态: 实施中

---

## 一、问题诊断

### 1.1 现象

- 选择图片工具后点击画布
- 相册界面弹出正常
- 选择图片后相册消失
- 画布上没有任何反应
- **控制台没有任何日志输出**（关键线索！）

### 1.2 代码审查发现

通过完整代码审查，发现以下问题：

| 问题 | 位置 | 严重程度 |
|-----|------|---------|
| **入口日志缺失** | showImagePicker() 方法没有任何入口日志 | 高 |
| **handleCanvasTap 日志缺失** | 图片工具分支没有日志 | 高 |
| **PHPickerViewControllerDelegate 无入口日志** | picker(_:didFinishPicking:) 没有立即打印的日志 | 高 |
| **ImagePickerPopover 孤立** | 定义完整但从未被使用 | 中 |
| **权限检查静默失败** | 权限失败时只打印日志但没有提示用户 | 中 |

### 1.3 根因分析

**最可能的原因**：

1. **delegate 回调未触发** - UIView 作为 PHPickerViewControllerDelegate，可能存在生命周期问题
2. **权限检查异步回调问题** - 权限检查后的异步回调可能没有正确执行
3. **findViewController() 返回 nil** - 在某些视图层级下可能找不到 ViewController

---

## 二、终极解决方案

### 2.1 核心思路

1. **添加完整的日志追踪** - 在每个关键节点添加日志
2. **简化架构** - 移除所有不必要的组件（ImagePickerPopover）
3. **使用最可靠的实现方式** - 参考 Apple 官方推荐和 GitHub 最佳实践
4. **增强错误处理** - 每个失败点都要有明确的日志和用户提示

### 2.2 实施步骤

#### 步骤 1: 添加完整的调试日志链

在以下位置添加日志：
- `handleCanvasTap` - 图片工具分支入口
- `showImagePicker` - 方法入口、权限检查、VC 查找、picker 创建
- `checkAndRequestPhotoPermission` - 权限状态
- `picker(_:didFinishPicking:)` - 回调入口、结果处理
- `handleImageDataSelected` - 图片处理

#### 步骤 2: 修复 PHPickerViewControllerDelegate

确保 delegate 正确设置且不会被提前释放。

#### 步骤 3: 清理无用代码

删除 ImagePickerPopover.swift（从未被使用）。

---

## 三、详细代码修改

### 3.1 NativeCanvasView.swift - handleCanvasTap 修改

```swift
// 图片工具模式
if currentTool == .image {
    print("========================================")
    print("[Image] handleCanvasTap - 图片工具模式")

    // 检查是否点击在已有图片上
    let location = gesture.location(in: objectLayerView)
    print("[Image] 点击位置: \(location)")

    let hitView = objectLayerView.hitTest(location, with: nil)
    print("[Image] hitTest 结果: \(type(of: hitView))")

    // 如果点击在已有图片上，让其自己处理（选中）
    if hitView is SelectableImageView {
        print("[Image] 点击在已有图片上，跳过")
        return
    }

    // 点击空白区域，显示图片选择弹窗
    print("[Image] 点击空白区域，调用 showImagePicker")
    showImagePicker(at: location)
    print("========================================")
    return
}
```

### 3.2 NativeCanvasView.swift - showImagePicker 修改

```swift
private func showImagePicker(at location: CGPoint) {
    print("========================================")
    print("[ImagePicker] showImagePicker 开始")
    print("[ImagePicker] 目标位置: \(location)")
    print("[ImagePicker] isShowingImagePicker: \(isShowingImagePicker)")

    guard !isShowingImagePicker else {
        print("[ImagePicker] 警告: 图片选择器已在显示中，忽略")
        return
    }

    // 保存位置信息
    pendingImageLocation = location
    isShowingImagePicker = true
    print("[ImagePicker] 状态已更新: pendingImageLocation=\(location)")

    // 检查权限
    print("[ImagePicker] 开始检查权限...")
    checkAndRequestPhotoPermission { [weak self] granted in
        print("[ImagePicker] 权限检查完成: granted=\(granted)")

        guard let self = self else {
            print("[ImagePicker] 错误: self 已释放")
            return
        }

        guard granted else {
            print("[ImagePicker] 错误: 相册权限被拒绝")
            self.isShowingImagePicker = false
            self.pendingImageLocation = nil
            return
        }

        // 找到视图控制器
        print("[ImagePicker] 查找视图控制器...")
        guard let viewController = self.findViewController() else {
            print("[ImagePicker] 错误: 未找到视图控制器")
            print("[ImagePicker] responder chain: \(self.responderChainDescription())")
            self.isShowingImagePicker = false
            self.pendingImageLocation = nil
            return
        }
        print("[ImagePicker] 找到视图控制器: \(type(of: viewController))")

        // 确保在主线程
        DispatchQueue.main.async {
            print("[ImagePicker] 开始创建 PHPicker...")

            // 配置 PHPicker
            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.selectionLimit = 1
            configuration.filter = .images
            configuration.preferredAssetRepresentationMode = .current

            // 创建并显示 PHPicker
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            print("[ImagePicker] PHPicker 创建完成，delegate: \(String(describing: picker.delegate))")

            print("[ImagePicker] 即将 present PHPicker...")
            viewController.present(picker, animated: true) {
                print("[ImagePicker] PHPicker present 完成")
            }
        }
    }
    print("========================================")
}

/// 获取响应者链描述（调试用）
private func responderChainDescription() -> String {
    var chain: [String] = []
    var responder: UIResponder? = self
    while let r = responder {
        chain.append(String(describing: type(of: r)))
        responder = r.next
    }
    return chain.joined(separator: " -> ")
}
```

### 3.3 NativeCanvasView.swift - checkAndRequestPhotoPermission 修改

```swift
private func checkAndRequestPhotoPermission(completion: @escaping (Bool) -> Void) {
    print("[Permission] 检查相册权限...")

    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    print("[Permission] 当前权限状态: \(status.rawValue) (\(permissionStatusDescription(status)))")

    switch status {
    case .authorized:
        print("[Permission] 已完全授权")
        completion(true)

    case .limited:
        print("[Permission] 受限授权（可使用）")
        completion(true)

    case .notDetermined:
        print("[Permission] 权限未确定，请求授权...")
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
            print("[Permission] 授权请求完成: \(newStatus.rawValue)")
            DispatchQueue.main.async {
                let granted = newStatus == .authorized || newStatus == .limited
                print("[Permission] 授权结果: \(granted)")
                completion(granted)
            }
        }

    case .denied:
        print("[Permission] 权限被用户拒绝")
        completion(false)

    case .restricted:
        print("[Permission] 权限受系统限制")
        completion(false)

    @unknown default:
        print("[Permission] 未知权限状态: \(status.rawValue)")
        completion(false)
    }
}

private func permissionStatusDescription(_ status: PHAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "未确定"
    case .restricted: return "受限"
    case .denied: return "拒绝"
    case .authorized: return "已授权"
    case .limited: return "受限授权"
    @unknown default: return "未知"
    }
}
```

### 3.4 PHPickerViewControllerDelegate 修改

```swift
// MARK: - PHPickerViewControllerDelegate

extension NativeCanvasView: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        print("========================================")
        print("[PHPicker] didFinishPicking 回调触发!")
        print("[PHPicker] 结果数量: \(results.count)")

        // 先关闭选择器
        picker.dismiss(animated: true) {
            print("[PHPicker] 选择器已关闭")
        }

        // 重置状态
        isShowingImagePicker = false

        // 获取待定位置
        guard let location = pendingImageLocation else {
            print("[PHPicker] 错误: pendingImageLocation 为 nil")
            return
        }
        print("[PHPicker] 目标位置: \(location)")

        // 如果用户取消选择
        guard let result = results.first else {
            print("[PHPicker] 用户取消选择")
            pendingImageLocation = nil
            return
        }
        print("[PHPicker] 获取到选择结果")

        // 加载图片数据
        let itemProvider = result.itemProvider
        print("[PHPicker] ItemProvider: \(itemProvider)")
        print("[PHPicker] 注册类型: \(itemProvider.registeredTypeIdentifiers)")

        if itemProvider.canLoadObject(ofClass: UIImage.self) {
            print("[PHPicker] 开始加载 UIImage...")

            itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                print("[PHPicker] loadObject 回调")

                if let error = error {
                    print("[PHPicker] 加载失败: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.pendingImageLocation = nil
                    }
                    return
                }

                guard let image = object as? UIImage else {
                    print("[PHPicker] 错误: 对象不是 UIImage")
                    DispatchQueue.main.async {
                        self?.pendingImageLocation = nil
                    }
                    return
                }
                print("[PHPicker] 图片加载成功，尺寸: \(image.size)")

                // 转换为 JPEG 数据
                guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                    print("[PHPicker] 错误: JPEG 压缩失败")
                    DispatchQueue.main.async {
                        self?.pendingImageLocation = nil
                    }
                    return
                }
                print("[PHPicker] JPEG 压缩完成，大小: \(imageData.count) bytes")

                // 回到主线程处理
                DispatchQueue.main.async { [weak self] in
                    print("[PHPicker] 调用 handleImageDataSelected...")
                    self?.handleImageDataSelected(imageData, at: location)
                    self?.pendingImageLocation = nil
                    print("[PHPicker] 处理完成")
                }
            }
        } else {
            print("[PHPicker] 错误: itemProvider 无法加载 UIImage")
            print("[PHPicker] 可用类型: \(itemProvider.registeredTypeIdentifiers)")
            pendingImageLocation = nil
        }
        print("========================================")
    }
}
```

### 3.5 handleImageDataSelected 修改

```swift
private func handleImageDataSelected(_ imageData: Data, at location: CGPoint) {
    print("========================================")
    print("[ImageData] handleImageDataSelected 开始")
    print("[ImageData] 数据大小: \(imageData.count) bytes")
    print("[ImageData] 位置: \(location)")

    let contentLocation = location
    let imageSize = CGSize(width: 300, height: 300)

    let imageFrame = CGRect(
        x: contentLocation.x - imageSize.width / 2,
        y: contentLocation.y - imageSize.height / 2,
        width: imageSize.width,
        height: imageSize.height
    )
    print("[ImageData] 计算的 frame: \(imageFrame)")

    // 保存图片到临时文件
    print("[ImageData] 保存到临时文件...")
    let tempURL = saveImageToTempFile(imageData)
    print("[ImageData] 临时文件 URL: \(tempURL?.absoluteString ?? "nil")")

    let imageLayer = LayerNode(
        id: UUID(),
        type: .userImage,
        url: tempURL?.absoluteString ?? "",
        frame: imageFrame,
        rotation: 0,
        isLocked: false,
        zIndex: getNextImageZIndex(),
        opacity: 1.0,
        createdAt: Date()
    )
    print("[ImageData] 创建 LayerNode: \(imageLayer.id)")

    // 添加图片到画布
    print("[ImageData] 添加到画布...")
    addLayer(imageLayer)

    // 自动选中新创建的图片
    print("[ImageData] 选中图片...")
    selectedNodeID = imageLayer.id

    print("[ImageData] 处理完成!")
    print("========================================")
}
```

---

## 四、删除无用文件

### 4.1 删除 ImagePickerPopover.swift

此文件定义完整但从未被使用，应该删除：

```
src/MindCanvas/MindCanvas/Views/Editor/Canvas/ImagePickerPopover.swift
```

---

## 五、验证清单

### 5.1 日志验证

成功流程应该看到以下日志序列：

```
========================================
[Image] handleCanvasTap - 图片工具模式
[Image] 点击位置: (xxx, xxx)
[Image] hitTest 结果: UIView
[Image] 点击空白区域，调用 showImagePicker
========================================
========================================
[ImagePicker] showImagePicker 开始
[ImagePicker] 目标位置: (xxx, xxx)
[ImagePicker] isShowingImagePicker: false
[ImagePicker] 状态已更新
[ImagePicker] 开始检查权限...
[Permission] 检查相册权限...
[Permission] 当前权限状态: 3 (已授权)
[Permission] 已完全授权
[ImagePicker] 权限检查完成: granted=true
[ImagePicker] 查找视图控制器...
[ImagePicker] 找到视图控制器: UIHostingController<...>
[ImagePicker] 开始创建 PHPicker...
[ImagePicker] PHPicker 创建完成，delegate: Optional(...)
[ImagePicker] 即将 present PHPicker...
[ImagePicker] PHPicker present 完成
========================================
... 用户选择图片 ...
========================================
[PHPicker] didFinishPicking 回调触发!
[PHPicker] 结果数量: 1
[PHPicker] 选择器已关闭
[PHPicker] 目标位置: (xxx, xxx)
[PHPicker] 获取到选择结果
[PHPicker] ItemProvider: ...
[PHPicker] 开始加载 UIImage...
[PHPicker] loadObject 回调
[PHPicker] 图片加载成功，尺寸: (xxx, xxx)
[PHPicker] JPEG 压缩完成，大小: xxx bytes
[PHPicker] 调用 handleImageDataSelected...
========================================
[ImageData] handleImageDataSelected 开始
[ImageData] 数据大小: xxx bytes
[ImageData] 位置: (xxx, xxx)
[ImageData] 计算的 frame: ...
[ImageData] 保存到临时文件...
[ImageData] 临时文件 URL: file:///...
[ImageData] 创建 LayerNode: ...
[ImageData] 添加到画布...
[ImageData] 选中图片...
[ImageData] 处理完成!
========================================
[PHPicker] 处理完成
========================================
```

### 5.2 功能验证

| 测试项 | 预期结果 |
|-------|---------|
| 点击图片工具，点击画布空白 | 弹出相册选择器 |
| 选择一张图片 | 图片显示在点击位置 |
| 取消选择 | 无任何变化 |
| 连续点击画布 | 每次都能正常弹出选择器 |
| 选择图片后立即选中 | 图片显示控制点 |

---

## 六、实施优先级

1. **P0 - 必须**: 添加完整日志链
2. **P0 - 必须**: 修复可能的 delegate 问题
3. **P1 - 推荐**: 删除 ImagePickerPopover.swift
4. **P2 - 可选**: 优化错误提示（权限被拒绝时显示 Alert）

---

## 七、总结

本方案的核心思路是：

1. **先诊断后治疗** - 通过完整的日志链确定问题的具体位置
2. **简化架构** - 移除冗余组件，减少出错概率
3. **最佳实践** - 遵循 Apple 官方推荐的 PHPickerViewController 使用方式
4. **防御性编程** - 每个关键节点都有日志和错误处理

实施后，即使问题仍然存在，我们也能通过日志准确定位到问题发生的具体环节。
