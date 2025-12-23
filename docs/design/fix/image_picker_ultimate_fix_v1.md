# 图片选择器终极修复方案 v1.0

> 时间: 2025-12-23
> 版本: v1.0
> 状态: 待实施

---

## 一、问题概述

### 1.1 当前问题

用户选择图片工具后点击画布，能够正常弹出图片选择界面，但选择图片后：
- 相册界面消失
- 画布上没有任何反应
- 控制台没有任何日志输出（关键！说明回调根本没有被触发）

### 1.2 问题现象分析

从现有日志和代码分析，问题出现在以下环节：
```
用户点击画布 --> showImagePicker() --> UIHostingController弹出
--> 用户选择图片 --> PhotosPicker系统弹窗关闭 --> [断点] onChange回调未触发
```

---

## 二、根因分析（第一性原理）

### 2.1 核心问题：UIHostingController + SwiftUI PhotosPicker 的架构缺陷

当前实现采用了一个**三层Modal嵌套**的架构：

```
NativeCanvasView (UIKit)
└── UIHostingController (Bridge)
    └── ImagePickerPopover (SwiftUI)
        └── .photosPicker modifier (系统弹窗)
```

**问题1：UIHostingController 生命周期管理**
- UIHostingController 的 rootView 在 modal 生命周期中可能被重建
- `@State` 变量（如 `selectedPhotoItem`）在重建时丢失
- 导致 `.onChange(of: selectedPhotoItem)` 永远无法被正确触发

**问题2：`.constant(true)` Binding 的致命错误**

```swift
// NativeCanvasView.swift 第826-836行
let popover = ImagePickerPopover(
    isPresented: .constant(true),  // <-- 致命问题！
    onImageSelected: { ... },
    onImageDataSelected: { ... },
    assets: assets
)
```

`.constant(true)` 创建了一个**不可变的 Binding**，无论 PhotosPicker 如何操作，这个值永远是 `true`。这导致：
1. SwiftUI 无法正确管理 PhotosPicker 的显示/隐藏状态
2. PhotosPicker 关闭后状态同步失败
3. 回调链断裂

**问题3：双层 Modal 的事件传递问题**
- ImagePickerPopover 作为一个 modal sheet
- PhotosPicker 又是其上的另一个系统 modal
- 当 PhotosPicker dismiss 后，事件需要传回两层，容易丢失

**问题4：权限API使用了旧版本**

```swift
// ImagePickerPopover.swift 第187行
let status = PHPhotoLibrary.authorizationStatus()  // 旧API，iOS 14已弃用

// 正确做法
let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
```

### 2.2 日志验证

根据 CHANGELOG.md 的记录，添加了大量调试日志但"控制台没有任何调试日志输出"，这说明：
- `handlePhotoItemSelected` 方法根本没有被调用
- `onChange(of: selectedPhotoItem)` 回调没有触发
- 问题出在 SwiftUI 状态管理层面，而非业务逻辑层面

---

## 三、解决方案：彻底重构为 UIKit 原生实现

### 3.1 方案总览

**核心思路**：既然 NativeCanvasView 已经是 UIKit 实现，图片选择器也应该使用 UIKit 原生的 `PHPickerViewController`，完全避免 SwiftUI 桥接问题。

```
修改前架构：
NativeCanvasView (UIKit) --> UIHostingController --> ImagePickerPopover (SwiftUI) --> PhotosPicker

修改后架构：
NativeCanvasView (UIKit) --> PHPickerViewController (UIKit 原生)
```

**优点**：
- 回调稳定可靠，不受 SwiftUI 生命周期影响
- 性能更好，没有 SwiftUI 桥接开销
- 完全控制权限和错误处理
- 只有一层 modal，事件传递可靠
- 代码更简洁，维护性更好

### 3.2 需要修改的文件

| 文件 | 修改类型 | 说明 |
|-----|---------|------|
| `NativeCanvasView.swift` | **重构** | 实现 PHPickerViewControllerDelegate，重写 showImagePicker 方法 |
| `ImagePickerPopover.swift` | **删除或保留** | 可以完全删除，或保留作为资源库选择界面 |
| `CameraImagePicker.swift` | **保留** | 相机功能继续使用 UIImagePickerController |

### 3.3 详细实现

#### 步骤1：扩展 NativeCanvasView 实现 PHPickerViewControllerDelegate

在 `NativeCanvasView.swift` 文件末尾添加新的 extension：

```swift
// MARK: - PHPickerViewControllerDelegate

import PhotosUI

extension NativeCanvasView: PHPickerViewControllerDelegate {

    /// PHPicker 完成选择的回调
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        print("📸 [PHPicker] didFinishPicking 回调触发，结果数: \(results.count)")

        // 先关闭选择器
        picker.dismiss(animated: true)

        // 重置状态
        isShowingImagePicker = false

        // 获取待定位置
        guard let location = pendingImageLocation else {
            print("⚠️ [PHPicker] pendingImageLocation 为 nil")
            pendingImageLocation = nil
            return
        }

        // 如果用户取消选择
        guard let result = results.first else {
            print("📱 [PHPicker] 用户取消选择")
            pendingImageLocation = nil
            return
        }

        print("✅ [PHPicker] 开始加载图片...")

        // 加载图片数据
        let itemProvider = result.itemProvider

        if itemProvider.canLoadObject(ofClass: UIImage.self) {
            itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let error = error {
                    print("❌ [PHPicker] 加载图片失败: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self?.pendingImageLocation = nil
                    }
                    return
                }

                guard let image = object as? UIImage else {
                    print("❌ [PHPicker] 图片类型转换失败")
                    DispatchQueue.main.async {
                        self?.pendingImageLocation = nil
                    }
                    return
                }

                print("✅ [PHPicker] 图片加载成功，尺寸: \(image.size)")

                // 转换为 JPEG 数据
                guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                    print("❌ [PHPicker] 图片压缩失败")
                    DispatchQueue.main.async {
                        self?.pendingImageLocation = nil
                    }
                    return
                }

                print("✅ [PHPicker] 图片压缩成功，数据大小: \(imageData.count) bytes")

                // 回到主线程处理
                DispatchQueue.main.async { [weak self] in
                    self?.handleImageDataSelected(imageData, at: location)
                    self?.pendingImageLocation = nil
                }
            }
        } else {
            print("❌ [PHPicker] itemProvider 无法加载 UIImage")
            pendingImageLocation = nil
        }
    }
}
```

#### 步骤2：重写 showImagePicker 方法

在 `NativeCanvasView.swift` 中，替换现有的 `showImagePicker` 方法：

```swift
/// 显示图片选择器（使用 PHPickerViewController）
private func showImagePicker(at location: CGPoint) {
    print("🖼️ [Canvas] showImagePicker 开始，位置: \(location)")

    guard !isShowingImagePicker else {
        print("⚠️ [Canvas] 图片选择器已经在显示中，忽略请求")
        return
    }

    // 保存位置信息
    pendingImageLocation = location
    isShowingImagePicker = true
    print("✅ [Canvas] 设置状态: pendingImageLocation=\(location), isShowingImagePicker=true")

    // 检查权限
    checkAndRequestPhotoPermission { [weak self] granted in
        guard let self = self, granted else {
            print("❌ [Canvas] 相册权限被拒绝")
            self?.isShowingImagePicker = false
            self?.pendingImageLocation = nil
            return
        }

        // 找到视图控制器
        guard let viewController = self.findViewController() else {
            print("❌ [Canvas] 未找到视图控制器")
            self.isShowingImagePicker = false
            self.pendingImageLocation = nil
            return
        }

        print("✅ [Canvas] 找到视图控制器: \(type(of: viewController))")

        // 配置 PHPicker
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = .images
        configuration.preferredAssetRepresentationMode = .current

        // 创建并显示 PHPicker
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self

        print("🎯 [Canvas] 开始弹出 PHPickerViewController...")
        viewController.present(picker, animated: true) {
            print("✅ [Canvas] PHPickerViewController 弹出完成")
        }
    }
}

/// 检查并请求相册权限
private func checkAndRequestPhotoPermission(completion: @escaping (Bool) -> Void) {
    print("🔐 [Canvas] 检查相册权限...")

    // 使用新版本 API（iOS 14+）
    let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    print("   - 当前权限状态: \(status.rawValue)")

    switch status {
    case .authorized, .limited:
        print("✅ [Canvas] 已授权")
        completion(true)

    case .notDetermined:
        print("🔄 [Canvas] 权限未确定，请求权限...")
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
            DispatchQueue.main.async {
                print("📝 [Canvas] 权限请求结果: \(newStatus.rawValue)")
                completion(newStatus == .authorized || newStatus == .limited)
            }
        }

    case .denied, .restricted:
        print("❌ [Canvas] 权限被拒绝或受限")
        // 可以在这里显示提示引导用户去设置
        completion(false)

    @unknown default:
        print("❌ [Canvas] 未知权限状态")
        completion(false)
    }
}
```

#### 步骤3：添加必要的 import

在 `NativeCanvasView.swift` 文件顶部，确保有以下 import：

```swift
import SwiftUI
import UIKit
import PencilKit
import PhotosUI  // <-- 添加这行
```

#### 步骤4：清理 ImagePickerPopover 相关代码（可选）

可以选择以下两种方式之一：

**方式A：完全删除 ImagePickerPopover.swift**
- 删除文件 `Views/Editor/Canvas/ImagePickerPopover.swift`
- 从项目中移除引用

**方式B：保留作为资源库选择界面**
- 如果需要保留"资源库"功能（从已有资源中选择），可以保留此文件
- 但需要移除其中的 PhotosPicker 相关代码，改为只展示资源库网格

### 3.4 相机功能保持不变

`CameraImagePicker.swift` 的实现已经是正确的 UIKit 封装方式，无需修改。

但需要在 `NativeCanvasView` 中添加相机入口。可以通过以下方式：

1. 在工具栏添加"拍照"选项
2. 或者在 PHPicker 界面添加相机入口（需要自定义实现）

---

## 四、实施步骤清单

### 阶段1：核心修复（必须完成）

| 步骤 | 文件 | 操作 | 验证标准 |
|-----|------|------|---------|
| 1.1 | `NativeCanvasView.swift` | 添加 `import PhotosUI` | 编译通过 |
| 1.2 | `NativeCanvasView.swift` | 添加 `PHPickerViewControllerDelegate` extension | 编译通过 |
| 1.3 | `NativeCanvasView.swift` | 实现 `picker(_:didFinishPicking:)` 方法 | 编译通过 |
| 1.4 | `NativeCanvasView.swift` | 重写 `showImagePicker(at:)` 方法 | 编译通过 |
| 1.5 | `NativeCanvasView.swift` | 添加 `checkAndRequestPhotoPermission` 方法 | 编译通过 |
| 1.6 | 真机测试 | 点击图片工具 -> 点击画布 -> 选择图片 | 图片正确显示在画布上 |

### 阶段2：清理工作（推荐完成）

| 步骤 | 文件 | 操作 | 验证标准 |
|-----|------|------|---------|
| 2.1 | `ImagePickerPopover.swift` | 决定删除或保留 | 项目编译通过 |
| 2.2 | `NativeCanvasView.swift` | 移除旧的 UIHostingController 相关代码 | 代码简洁 |
| 2.3 | 全项目 | 移除多余的调试日志 | 日志清晰 |

### 阶段3：功能增强（可选）

| 步骤 | 描述 | 优先级 |
|-----|------|-------|
| 3.1 | 添加加载进度指示器 | 中 |
| 3.2 | 添加图片压缩选项 | 低 |
| 3.3 | 支持多图选择 | 低 |
| 3.4 | 添加权限被拒绝时的引导提示 | 高 |

---

## 五、完整代码示例

### 5.1 修改后的 NativeCanvasView.swift 关键部分

```swift
import SwiftUI
import UIKit
import PencilKit
import PhotosUI  // 新增

/// 原生画布视图 (UIKit 实现)
class NativeCanvasView: UIView {
    // ... 现有属性保持不变 ...

    // MARK: - Image Picker (重写)

    /// 显示图片选择器（使用 PHPickerViewController）
    private func showImagePicker(at location: CGPoint) {
        print("🖼️ [Canvas] showImagePicker 开始，位置: \(location)")

        guard !isShowingImagePicker else {
            print("⚠️ [Canvas] 图片选择器已经在显示中，忽略请求")
            return
        }

        pendingImageLocation = location
        isShowingImagePicker = true

        checkAndRequestPhotoPermission { [weak self] granted in
            guard let self = self, granted else {
                print("❌ [Canvas] 相册权限被拒绝")
                self?.isShowingImagePicker = false
                self?.pendingImageLocation = nil
                return
            }

            guard let viewController = self.findViewController() else {
                print("❌ [Canvas] 未找到视图控制器")
                self.isShowingImagePicker = false
                self.pendingImageLocation = nil
                return
            }

            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.selectionLimit = 1
            configuration.filter = .images
            configuration.preferredAssetRepresentationMode = .current

            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self

            viewController.present(picker, animated: true)
        }
    }

    /// 检查并请求相册权限（使用 iOS 14+ API）
    private func checkAndRequestPhotoPermission(completion: @escaping (Bool) -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch status {
        case .authorized, .limited:
            completion(true)

        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    completion(newStatus == .authorized || newStatus == .limited)
                }
            }

        case .denied, .restricted:
            completion(false)

        @unknown default:
            completion(false)
        }
    }

    // ... 其他方法保持不变 ...
}

// MARK: - PHPickerViewControllerDelegate

extension NativeCanvasView: PHPickerViewControllerDelegate {

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        print("📸 [PHPicker] didFinishPicking 回调触发")

        picker.dismiss(animated: true)
        isShowingImagePicker = false

        guard let location = pendingImageLocation else {
            pendingImageLocation = nil
            return
        }

        guard let result = results.first else {
            pendingImageLocation = nil
            return
        }

        let itemProvider = result.itemProvider

        if itemProvider.canLoadObject(ofClass: UIImage.self) {
            itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let error = error {
                    print("❌ [PHPicker] 加载失败: \(error)")
                    DispatchQueue.main.async {
                        self?.pendingImageLocation = nil
                    }
                    return
                }

                guard let image = object as? UIImage,
                      let imageData = image.jpegData(compressionQuality: 0.8) else {
                    DispatchQueue.main.async {
                        self?.pendingImageLocation = nil
                    }
                    return
                }

                DispatchQueue.main.async { [weak self] in
                    self?.handleImageDataSelected(imageData, at: location)
                    self?.pendingImageLocation = nil
                }
            }
        } else {
            pendingImageLocation = nil
        }
    }
}
```

---

## 六、测试验证清单

### 6.1 功能测试

| 测试用例 | 操作步骤 | 预期结果 |
|---------|---------|---------|
| 基础选择 | 1. 选择图片工具 2. 点击画布 3. 选择一张图片 | 图片显示在点击位置 |
| 取消选择 | 1. 选择图片工具 2. 点击画布 3. 点击取消 | 无任何变化，可重新点击 |
| 权限拒绝 | 1. 在设置中拒绝相册权限 2. 选择图片工具 3. 点击画布 | 显示权限提示或无响应 |
| 连续选择 | 1. 选择图片工具 2. 连续点击画布多次 3. 每次选择不同图片 | 每次都正确创建图片 |
| 大图片 | 选择一张 4K 或更大的图片 | 图片正确压缩后显示 |
| HEIF 格式 | 选择一张 iPhone 拍摄的 HEIF 图片 | 图片正确转换后显示 |

### 6.2 边界条件测试

| 测试用例 | 操作步骤 | 预期结果 |
|---------|---------|---------|
| 快速点击 | 快速连续点击画布多次 | 只弹出一个选择器 |
| 切换工具 | 1. 点击画布弹出选择器 2. 切换到其他工具 | 选择器保持显示或关闭 |
| 内存压力 | 在低内存情况下选择大图片 | 不崩溃，可能提示失败 |

### 6.3 日志验证

成功流程应该看到以下日志：
```
🖼️ [Canvas] 检测到图片工具模式下的点击
📱 [Canvas] 点击空白区域，显示图片选择弹窗
🖼️ [Canvas] showImagePicker 开始，位置: (xxx, xxx)
🔐 [Canvas] 检查相册权限...
✅ [Canvas] 已授权
✅ [Canvas] 找到视图控制器: xxx
🎯 [Canvas] 开始弹出 PHPickerViewController...
✅ [Canvas] PHPickerViewController 弹出完成
📸 [PHPicker] didFinishPicking 回调触发
✅ [PHPicker] 开始加载图片...
✅ [PHPicker] 图片加载成功，尺寸: (xxx, xxx)
✅ [PHPicker] 图片压缩成功，数据大小: xxx bytes
📷 [Canvas] handleImageDataSelected 开始
✅ [Canvas] 创建图片图层: xxx
✅ [Canvas] 图片图层已添加到画布
✅ [Canvas] 图片已选中: xxx
```

---

## 七、风险评估与回退方案

### 7.1 风险评估

| 风险 | 概率 | 影响 | 缓解措施 |
|-----|------|------|---------|
| PHPickerViewController 在特定 iOS 版本有兼容性问题 | 低 | 中 | iOS 17+ 已稳定，保持最低版本要求 |
| 图片加载失败未正确处理 | 中 | 低 | 添加完整的错误处理和用户提示 |
| 相机功能入口丢失 | 低 | 低 | 可在工具栏添加相机按钮 |

### 7.2 回退方案

如果 PHPickerViewController 方案出现问题，可以回退到：

1. **使用 UIImagePickerController**（最古老但最稳定）
2. **修复现有 SwiftUI 实现**（但不推荐）

回退代码示例：
```swift
// 使用 UIImagePickerController 作为备选
private func showImagePickerLegacy(at location: CGPoint) {
    let picker = UIImagePickerController()
    picker.sourceType = .photoLibrary
    picker.delegate = self  // 需要实现 UIImagePickerControllerDelegate
    viewController?.present(picker, animated: true)
}
```

---

## 八、总结

### 8.1 问题根源

当前实现的核心问题在于：
1. **架构问题**：三层 Modal 嵌套（UIKit -> UIHostingController -> SwiftUI PhotosPicker）
2. **状态管理错误**：使用 `.constant(true)` 导致 Binding 失效
3. **API 过时**：使用了旧版本的权限检查 API

### 8.2 解决方案

采用 UIKit 原生的 `PHPickerViewController`：
- 彻底避免 SwiftUI 桥接问题
- 回调稳定可靠
- 代码更简洁，维护性更好

### 8.3 实施优先级

**必须完成**：
- 重写 `showImagePicker` 方法
- 实现 `PHPickerViewControllerDelegate`
- 使用正确的权限 API

**推荐完成**：
- 清理 `ImagePickerPopover.swift`
- 移除多余的调试日志

---

## 附录：参考资料

1. [Apple PHPickerViewController 官方文档](https://developer.apple.com/documentation/photokit/phpickerviewcontroller)
2. [Apple PhotosPicker SwiftUI 文档](https://developer.apple.com/documentation/photokit/photospicker)
3. [WWDC 2020 - Meet the New Photos Picker](https://developer.apple.com/videos/play/wwdc2020/10652/)
4. [UIHostingController 生命周期问题](https://developer.apple.com/documentation/swiftui/uihostingcontroller)
