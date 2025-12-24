//
//  SelectableImageView.swift
//  MindCanvas
//
//  Created by Elvis on 2025/12/23.
//

import UIKit

/// 可选择的图片视图（支持专业级控制点交互）
class SelectableImageView: UIView {

    // MARK: - Properties

    var layerNode: LayerNode {
        didSet {
            updateFromNode()
        }
    }

    // 图层
    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()
    
    private let selectionBorder = CAShapeLayer()
    private var cornerHandleLayers: [CAShapeLayer] = []
    private let rotationHandleLayer = CAShapeLayer()
    private let rotationLineLayer = CAShapeLayer()

    // 控制点配置
    private let handleSize: CGFloat = 12
    private let rotationHandleOffset: CGFloat = 30

    // 选中状态
    var isSelected: Bool = false {
        didSet {
            print("🖼️ [ImageView] isSelected 变化: \(oldValue) -> \(isSelected), 图片ID: \(layerNode.id)")
            updateSelectionAppearance()
        }
    }

    // 当前拖动的控制点
    private var activeHandle: ControlHandle?
    private var dragStartPoint: CGPoint = .zero
    
    // 初始状态 (手势开始时保存)
    private var initialBounds: CGRect = .zero
    private var initialCenter: CGPoint = .zero
    private var initialRotation: CGFloat = 0
    private var initialTouchAngle: CGFloat = 0  // 旋转手势: 初始触摸角度
    private var initialNode: LayerNode?
    
    // 拖动开始时的角点实际位置（不是触摸点，是角点本身的位置）
    private var initialHandlePosition: CGPoint = .zero

    // 手势
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    // 回调
    var onNodeUpdated: ((LayerNode) -> Void)?
    var onSelected: ((UUID) -> Void)?
    var onOperationStart: ((LayerNode) -> Void)?
    var onOperationEnd: ((LayerNode, LayerNode) -> Void)?

    // MARK: - Initialization

    init(layerNode: LayerNode) {
        self.layerNode = layerNode
        super.init(frame: layerNode.frame)
        setupViews()
        setupGestures()
        loadImage()
        updateFromNode()
        print("🖼️ [ImageView] 初始化完成 - 图片ID: \(layerNode.id.uuidString.prefix(8)), tapGesture初始状态: \(tapGesture.isEnabled)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        // 设置视图属性
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false

        // 添加图片视图
        addSubview(imageView)
        
        // 添加选中边框
        layer.addSublayer(selectionBorder)
        
        // 添加控制点
        for _ in 0..<4 {
            let handleLayer = CAShapeLayer()
            layer.addSublayer(handleLayer)
            cornerHandleLayers.append(handleLayer)
        }
        
        // 添加旋转连接线
        layer.addSublayer(rotationLineLayer)
        
        // 添加旋转手柄
        layer.addSublayer(rotationHandleLayer)
        
        // 设置默认样式
        updateSelectionStyle()
    }

    private func setupGestures() {
        // 点击手势
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        print("🖼️ [ImageView] 创建 tapGesture - target: \(ObjectIdentifier(self)), action: #selector(handleTap)")
        addGestureRecognizer(tapGesture)
        print("🖼️ [ImageView] tapGesture 已添加到视图")
        
        // 拖拽手势
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
        print("🖼️ [ImageView] panGesture 已添加到视图")
    }

    private func updateSelectionStyle() {
        // 选中边框样式
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.strokeColor = UIColor.systemBlue.cgColor
        selectionBorder.lineWidth = 1.5
        selectionBorder.lineDashPattern = [4, 4]
        
        // 控制点样式
        for handleLayer in cornerHandleLayers {
            handleLayer.fillColor = UIColor.white.cgColor
            handleLayer.strokeColor = UIColor.systemBlue.cgColor
            handleLayer.lineWidth = 2
        }
        
        // 旋转连接线样式
        rotationLineLayer.fillColor = UIColor.clear.cgColor
        rotationLineLayer.strokeColor = UIColor.systemBlue.cgColor
        rotationLineLayer.lineWidth = 1.5
        
        // 旋转手柄样式
        rotationHandleLayer.fillColor = UIColor.white.cgColor
        rotationHandleLayer.strokeColor = UIColor.systemBlue.cgColor
        rotationHandleLayer.lineWidth = 2
    }

    // MARK: - Image Loading
    
    private func loadImage() {
        guard let urlString = layerNode.url else { return }
        
        // 本地图片
        if let url = URL(string: urlString), url.isFileURL {
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                imageView.image = image
                updateViewSizeForImage(image)
            }
        }
        // 远程图片 (简单实现，生产环境应使用 Kingfisher 等库)
        else if let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self?.imageView.image = image
                    self?.updateViewSizeForImage(image)
                }
            }.resume()
        }
    }
    
    /// 根据图片实际尺寸更新视图尺寸
    private func updateViewSizeForImage(_ image: UIImage) {
        let imageSize = image.size
        
        // 限制最大尺寸，避免图片过大
        let maxSize: CGFloat = 600
        let scaledSize = scaleSizeToFit(imageSize, maxSize: maxSize)
        
        print("🖼️ [ImageView] 更新尺寸 - 原始: \(imageSize), 缩放后: \(scaledSize)")
        
        // 更新 layerNode 的 frame
        let newFrame = CGRect(
            x: layerNode.frame.midX - scaledSize.width / 2,
            y: layerNode.frame.midY - scaledSize.height / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
        
        layerNode = layerNode.updated(frame: newFrame)
        
        // 更新视图
        updateFromNode()
        
        // 通知父视图更新
        onNodeUpdated?(layerNode)
    }
    
    /// 缩放尺寸以适应最大尺寸限制
    private func scaleSizeToFit(_ size: CGSize, maxSize: CGFloat) -> CGSize {
        if size.width <= maxSize && size.height <= maxSize {
            return size
        }
        
        let scale = min(maxSize / size.width, maxSize / size.height)
        return CGSize(
            width: size.width * scale,
            height: size.height * scale
        )
    }

    // MARK: - Sync Methods

    /// 从数据模型更新视图
    private func updateFromNode() {
        // 重置 transform 为 identity
        transform = .identity

        // 设置 bounds 和 center
        bounds = CGRect(x: 0, y: 0, width: layerNode.frame.width, height: layerNode.frame.height)
        center = CGPoint(x: layerNode.frame.midX, y: layerNode.frame.midY)

        // 应用旋转
        transform = CGAffineTransform(rotationAngle: layerNode.rotation)
        
        // 更新透明度
        alpha = layerNode.opacity
        
        // 更新用户交互
        isUserInteractionEnabled = !layerNode.isLocked

        updateSelectionAppearance()
    }

    // 上次同步的 frame（用于防抖）
    private var lastSyncedFrame: CGRect?

    /// 同步到数据模型
    private func syncToNode() {
        let currentRotation = atan2(transform.b, transform.a)

        // 从 center 和 bounds 重建 frame
        let newFrame = CGRect(
            x: center.x - bounds.width / 2,
            y: center.y - bounds.height / 2,
            width: bounds.width,
            height: bounds.height
        )

        // 防护：如果与上次同步的 frame 几乎相同，不再更新（防抖机制）
        if let lastFrame = lastSyncedFrame,
           abs(lastFrame.width - newFrame.width) < 0.1,
           abs(lastFrame.height - newFrame.height) < 0.1 {
            return  // 跳过微小变化
        }

        lastSyncedFrame = newFrame
        layerNode = layerNode.updated(
            frame: newFrame,
            rotation: currentRotation,
            opacity: Double(alpha)
        )
        onNodeUpdated?(layerNode)
    }

    // MARK: - Selection Appearance

    private func updateSelectionAppearance() {
        // 角点在选中状态或操作过程中显示，提升交互体验
        let showHandles = isSelected || activeHandle != nil
        
        print("🖼️ [ImageView] updateSelectionAppearance - isSelected: \(isSelected), activeHandle: \(activeHandle != nil), showHandles: \(showHandles)")
        
        selectionBorder.isHidden = !showHandles
        rotationLineLayer.isHidden = !showHandles
        rotationHandleLayer.isHidden = !showHandles
        cornerHandleLayers.forEach { $0.isHidden = !showHandles }

        guard showHandles else { 
            print("🖼️ [ImageView] 隐藏控制点")
            return 
        }
        
        print("🖼️ [ImageView] 显示控制点")

        // 更新选中边框
        let borderRect = bounds
        selectionBorder.path = UIBezierPath(rect: borderRect).cgPath

        let corners: [ControlHandle] = [ControlHandle.topLeft, ControlHandle.topRight, ControlHandle.bottomRight, ControlHandle.bottomLeft]
        for (index, corner) in corners.enumerated() {
            let position = corner.position(in: bounds)
            let handleRect = CGRect(
                x: position.x - handleSize / 2,
                y: position.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            cornerHandleLayers[index].path = UIBezierPath(rect: handleRect).cgPath
        }

        // 更新旋转手柄连接线
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
        linePath.addLine(to: CGPoint(x: bounds.midX, y: bounds.minY - rotationHandleOffset))
        rotationLineLayer.path = linePath.cgPath

        // 更新旋转手柄（圆形）
        let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
        let rotationRect = CGRect(
            x: rotationPos.x - handleSize / 2,
            y: rotationPos.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        rotationHandleLayer.path = UIBezierPath(ovalIn: rotationRect).cgPath
        
        // 更新锁定标识
        viewWithTag(999)?.removeFromSuperview()
        if layerNode.isLocked {
            addLockIndicator()
        }
    }

    // MARK: - Hit Testing

    private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
        guard isSelected else { return nil }

        let hitRadius: CGFloat = handleSize + 10

        // point 参数已经在本地坐标系中（由 gesture.location(in: self) 提供）
        // 直接使用 point 进行距离检测

        // 先检查旋转手柄（优先级更高）
        let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
        if distance(from: point, to: rotationPos) < hitRadius {
            return ControlHandle.rotation
        }

        // 再检查角点
        let corners: [ControlHandle] = [ControlHandle.topLeft, ControlHandle.topRight, ControlHandle.bottomRight, ControlHandle.bottomLeft]
        for corner in corners {
            let cornerPos = corner.position(in: bounds)
            if distance(from: point, to: cornerPos) < hitRadius {
                return corner
            }
        }

        return nil
    }

    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // point 参数已经在本地坐标系中（UIKit 自动处理了 transform）
        
        // 1. 首先检查触摸点是否在原始bounds内（精确点击）
        if bounds.contains(point) {
            return true
        }
        
        // 2. 只有在选中状态下才扩展控制点区域
        guard isSelected else { 
            return false
        }
        
        // 3. 仅对控制点周围22pt半径区域进行扩展（精确控制点扩展）
        let controlPointHitRadius: CGFloat = 22
        
        // 检查旋转手柄区域
        let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
        if distance(from: point, to: rotationPos) <= controlPointHitRadius {
            return true
        }
        
        // 检查角点控制点区域
        let corners: [ControlHandle] = [ControlHandle.topLeft, ControlHandle.topRight, ControlHandle.bottomRight, ControlHandle.bottomLeft]
        for corner in corners {
            let cornerPos = corner.position(in: bounds)
            if distance(from: point, to: cornerPos) <= controlPointHitRadius {
                return true
            }
        }
        
        // 4. 不在控制点区域，返回false（消除隐形外圈区域）
        return false
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        print("🖼️ [ImageView] handleTap 被调用 - 图片ID: \(layerNode.id)")
        onSelected?(layerNode.id)
        print("🖼️ [ImageView] onSelected 回调已触发")
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let locationInSelf = gesture.location(in: self)

        switch gesture.state {
        case .began:
            // 保存初始状态
            initialNode = layerNode
            onOperationStart?(layerNode)

            activeHandle = hitTestHandle(at: locationInSelf)
            
            // 立即更新角点显示状态，确保操作过程中角点可见
            updateSelectionAppearance()

            // 关键: 保存 center 和 bounds，而非 frame
            initialCenter = center
            initialBounds = bounds
            initialRotation = atan2(transform.b, transform.a)

            // 如果是缩放，保存被拖动角点的实际位置（不是触摸点）
            if let handle = activeHandle, handle != ControlHandle.rotation {
                // 计算角点在 superview 坐标系中的位置
                let handleLocalOffset = handleOffset(for: handle)
                let cosR = cos(initialRotation)
                let sinR = sin(initialRotation)
                initialHandlePosition = CGPoint(
                    x: initialCenter.x + handleLocalOffset.x * cosR - handleLocalOffset.y * sinR,
                    y: initialCenter.y + handleLocalOffset.x * sinR + handleLocalOffset.y * cosR
                )
            }

            // 如果是旋转，计算初始触摸角度
            if activeHandle == ControlHandle.rotation {
                let touchInSuperview = gesture.location(in: superview)
                initialTouchAngle = atan2(
                    touchInSuperview.y - initialCenter.y,
                    touchInSuperview.x - initialCenter.x
                )
            }

            dragStartPoint = gesture.location(in: superview)

        case .changed:
            let currentPoint = gesture.location(in: superview)

            if let handle = activeHandle {
                switch handle {
                case ControlHandle.rotation:
                    handleRotationImproved(currentPoint: currentPoint)
                default:
                    handleResizeFixed(handle: handle, currentPoint: currentPoint)
                }
            } else {
                handleMoveImproved(currentPoint: currentPoint)
            }

        case .ended, .cancelled:
            activeHandle = nil
            
            // 立即更新角点显示状态，确保操作结束后角点状态正确
            updateSelectionAppearance()
            
            syncToNode()
            
            if let initial = initialNode {
                onOperationEnd?(initial, layerNode)
            }
            initialNode = nil

        default:
            break
        }
    }

    // MARK: - Transform Operations (Improved)

    /// 改进的移动方法
    private func handleMoveImproved(currentPoint: CGPoint) {
        let dx = currentPoint.x - dragStartPoint.x
        let dy = currentPoint.y - dragStartPoint.y

        // 直接修改 center，保持 bounds 不变
        center = CGPoint(
            x: initialCenter.x + dx,
            y: initialCenter.y + dy
        )
    }

    /// 平滑的比例缩放方法 - 基于原始尺寸但使用增量计算
    private func handleResizeFixed(handle: ControlHandle, currentPoint: CGPoint) {
        guard let oppositeCorner = handle.oppositeCorner else { return }
        
        // 如果有原始尺寸，使用基于原始尺寸的缩放
        if let originalSize = layerNode.originalSize {
            handleResizeWithOriginalSize(handle: handle, currentPoint: currentPoint, originalSize: originalSize)
        } else {
            // 如果没有原始尺寸，使用增量缩放方式
            handleResizeIncremental(handle: handle, currentPoint: currentPoint)
        }
    }
    
    /// 基于原始尺寸的平滑缩放
    private func handleResizeWithOriginalSize(handle: ControlHandle, currentPoint: CGPoint, originalSize: CGSize) {
        guard let oppositeCorner = handle.oppositeCorner else { return }

        // Step 1: 计算锚点位置（对角点）
        let anchorLocalOffset = anchorOffset(for: oppositeCorner)
        let cosR = cos(initialRotation)
        let sinR = sin(initialRotation)

        let anchorInSuperview = CGPoint(
            x: initialCenter.x + anchorLocalOffset.x * cosR - anchorLocalOffset.y * sinR,
            y: initialCenter.y + anchorLocalOffset.x * sinR + anchorLocalOffset.y * cosR
        )

        // Step 2: 计算拖动增量（使用增量而不是绝对位置）
        let dragDeltaX = currentPoint.x - dragStartPoint.x
        let dragDeltaY = currentPoint.y - dragStartPoint.y

        // Step 3: 将拖动增量逆旋转到本地坐标系
        let cosNegR = cos(-initialRotation)
        let sinNegR = sin(-initialRotation)
        let localDeltaX = dragDeltaX * cosNegR - dragDeltaY * sinNegR
        let localDeltaY = dragDeltaX * sinNegR + dragDeltaY * cosNegR

        // Step 4: 计算当前缩放比例（基于初始尺寸）
        let currentScale = initialBounds.width / originalSize.width
        
        // Step 5: 根据拖动方向计算增量缩放
        let widthSign: CGFloat = (handle == ControlHandle.topLeft || handle == ControlHandle.bottomLeft) ? -1 : 1
        let heightSign: CGFloat = (handle == ControlHandle.topLeft || handle == ControlHandle.topRight) ? -1 : 1
        
        // 计算增量缩放因子（基于拖动距离和原始尺寸）
        let scaleFactorX = (localDeltaX * widthSign) / originalSize.width
        let scaleFactorY = (localDeltaY * heightSign) / originalSize.height
        
        // 使用平均缩放因子保持宽高比
        let avgScaleFactor = (scaleFactorX + scaleFactorY) / 2
        
        // 新的缩放比例
        let newScale = currentScale + avgScaleFactor
        
        // 限制缩放范围
        let minScale: CGFloat = 0.1
        let maxScale: CGFloat = 5.0
        let clampedScale = max(minScale, min(maxScale, newScale))

        // Step 6: 计算新的显示尺寸
        let newWidth = originalSize.width * clampedScale
        let newHeight = originalSize.height * clampedScale

        // 最小尺寸限制
        let minSize: CGFloat = 20
        let finalWidth = max(newWidth, minSize)
        let finalHeight = max(newHeight, minSize)

        // Step 7: 计算新中心点
        let newHalfWidth = finalWidth / 2
        let newHalfHeight = finalHeight / 2

        // 新中心相对于锚点的本地偏移
        let newCenterLocalOffsetX = newHalfWidth * (-anchorLocalOffset.x / abs(anchorLocalOffset.x + 0.001))
        let newCenterLocalOffsetY = newHalfHeight * (-anchorLocalOffset.y / abs(anchorLocalOffset.y + 0.001))

        // 安全处理：如果锚点偏移接近0，使用默认方向
        let safeCenterOffsetX: CGFloat
        let safeCenterOffsetY: CGFloat

        if abs(anchorLocalOffset.x) < 0.001 {
            safeCenterOffsetX = 0
        } else {
            safeCenterOffsetX = anchorLocalOffset.x < 0 ? newHalfWidth : -newHalfWidth
        }

        if abs(anchorLocalOffset.y) < 0.001 {
            safeCenterOffsetY = 0
        } else {
            safeCenterOffsetY = anchorLocalOffset.y < 0 ? newHalfHeight : -newHalfHeight
        }

        // 将新中心偏移旋转回世界坐标系
        let newCenter = CGPoint(
            x: anchorInSuperview.x + safeCenterOffsetX * cosR - safeCenterOffsetY * sinR,
            y: anchorInSuperview.y + safeCenterOffsetX * sinR + safeCenterOffsetY * cosR
        )

        // Step 8: 更新视图（使用 bounds + center）
        bounds = CGRect(x: 0, y: 0, width: finalWidth, height: finalHeight)
        center = newCenter

        // Step 9: 保持旋转角度不变
        transform = CGAffineTransform(rotationAngle: initialRotation)

        // Step 10: 立即更新图片视图 frame，确保图像跟着缩放
        imageView.frame = bounds

        // Step 11: 更新选中外观 (控制点位置需要随缩放和旋转更新)
        updateSelectionAppearance()
    }
    
    /// 增量缩放方法（备用，当没有原始尺寸时使用）
    private func handleResizeIncremental(handle: ControlHandle, currentPoint: CGPoint) {
        guard let oppositeCorner = handle.oppositeCorner else { return }

        // Step 1: 计算锚点位置（对角点）
        let anchorLocalOffset = anchorOffset(for: oppositeCorner)
        let cosR = cos(initialRotation)
        let sinR = sin(initialRotation)

        let anchorInSuperview = CGPoint(
            x: initialCenter.x + anchorLocalOffset.x * cosR - anchorLocalOffset.y * sinR,
            y: initialCenter.y + anchorLocalOffset.x * sinR + anchorLocalOffset.y * cosR
        )

        // Step 2: 计算拖动增量
        let dragDeltaX = currentPoint.x - dragStartPoint.x
        let dragDeltaY = currentPoint.y - dragStartPoint.y

        // Step 3: 将拖动增量逆旋转到本地坐标系
        let cosNegR = cos(-initialRotation)
        let sinNegR = sin(-initialRotation)
        let localDeltaX = dragDeltaX * cosNegR - dragDeltaY * sinNegR
        let localDeltaY = dragDeltaX * sinNegR + dragDeltaY * cosNegR

        // Step 4: 计算新尺寸（增量计算）
        let widthSign: CGFloat = (handle == ControlHandle.topLeft || handle == ControlHandle.bottomLeft) ? -1 : 1
        let heightSign: CGFloat = (handle == ControlHandle.topLeft || handle == ControlHandle.topRight) ? -1 : 1

        var newWidth = initialBounds.width + localDeltaX * widthSign
        var newHeight = initialBounds.height + localDeltaY * heightSign

        // 最小尺寸限制
        let minSize: CGFloat = 20
        newWidth = max(newWidth, minSize)
        newHeight = max(newHeight, minSize)

        // Step 5: 计算新中心点
        let newHalfWidth = newWidth / 2
        let newHalfHeight = newHeight / 2

        // 新中心相对于锚点的本地偏移
        let newCenterLocalOffsetX = newHalfWidth * (-anchorLocalOffset.x / abs(anchorLocalOffset.x + 0.001))
        let newCenterLocalOffsetY = newHalfHeight * (-anchorLocalOffset.y / abs(anchorLocalOffset.y + 0.001))

        // 安全处理：如果锚点偏移接近0，使用默认方向
        let safeCenterOffsetX: CGFloat
        let safeCenterOffsetY: CGFloat

        if abs(anchorLocalOffset.x) < 0.001 {
            safeCenterOffsetX = 0
        } else {
            safeCenterOffsetX = anchorLocalOffset.x < 0 ? newHalfWidth : -newHalfWidth
        }

        if abs(anchorLocalOffset.y) < 0.001 {
            safeCenterOffsetY = 0
        } else {
            safeCenterOffsetY = anchorLocalOffset.y < 0 ? newHalfHeight : -newHalfHeight
        }

        // 将新中心偏移旋转回世界坐标系
        let newCenter = CGPoint(
            x: anchorInSuperview.x + safeCenterOffsetX * cosR - safeCenterOffsetY * sinR,
            y: anchorInSuperview.y + safeCenterOffsetX * sinR + safeCenterOffsetY * cosR
        )

        // Step 6: 更新视图（使用 bounds + center）
        bounds = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
        center = newCenter

        // Step 7: 保持旋转角度不变
        transform = CGAffineTransform(rotationAngle: initialRotation)

        // Step 8: 立即更新图片视图 frame，确保图像跟着缩放
        imageView.frame = bounds

        // Step 9: 更新选中外观
        updateSelectionAppearance()
    }

    /// 改进的旋转方法
    private func handleRotationImproved(currentPoint: CGPoint) {
        // 计算当前触摸角度
        let currentTouchAngle = atan2(
            currentPoint.y - initialCenter.y,
            currentPoint.x - initialCenter.x
        )

        // 计算角度增量
        let deltaAngle = currentTouchAngle - initialTouchAngle

        // 新旋转角度 = 初始旋转 + 增量
        let newRotation = initialRotation + deltaAngle

        // 只修改 transform，不改变 bounds 和 center
        transform = CGAffineTransform(rotationAngle: newRotation)

        // 更新选中外观 (控制点位置需要随旋转更新)
        updateSelectionAppearance()
    }

    /// 计算锚点相对于中心的偏移量
    private func anchorOffset(for corner: ControlHandle) -> CGPoint {
        let halfWidth = initialBounds.width / 2
        let halfHeight = initialBounds.height / 2

        switch corner {
        case ControlHandle.topLeft:
            return CGPoint(x: -halfWidth, y: -halfHeight)
        case ControlHandle.topRight:
            return CGPoint(x: halfWidth, y: -halfHeight)
        case ControlHandle.bottomRight:
            return CGPoint(x: halfWidth, y: halfHeight)
        case ControlHandle.bottomLeft:
            return CGPoint(x: -halfWidth, y: halfHeight)
        case ControlHandle.rotation:
            return .zero
        }
    }
    
    /// 计算锚点相对于中心的偏移量（基于原始尺寸）
    private func anchorOffset(for corner: ControlHandle, originalSize: CGSize) -> CGPoint {
        let halfWidth = originalSize.width / 2
        let halfHeight = originalSize.height / 2

        switch corner {
        case ControlHandle.topLeft:
            return CGPoint(x: -halfWidth, y: -halfHeight)
        case ControlHandle.topRight:
            return CGPoint(x: halfWidth, y: -halfHeight)
        case ControlHandle.bottomRight:
            return CGPoint(x: halfWidth, y: halfHeight)
        case ControlHandle.bottomLeft:
            return CGPoint(x: -halfWidth, y: halfHeight)
        case ControlHandle.rotation:
            return .zero
        }
    }

    /// 计算控制点（拖动的那个角）相对于中心的偏移量
    private func handleOffset(for handle: ControlHandle) -> CGPoint {
        let halfWidth = initialBounds.width / 2
        let halfHeight = initialBounds.height / 2

        switch handle {
        case ControlHandle.topLeft:
            return CGPoint(x: -halfWidth, y: -halfHeight)
        case ControlHandle.topRight:
            return CGPoint(x: halfWidth, y: -halfHeight)
        case ControlHandle.bottomRight:
            return CGPoint(x: halfWidth, y: halfHeight)
        case ControlHandle.bottomLeft:
            return CGPoint(x: -halfWidth, y: halfHeight)
        case ControlHandle.rotation:
            return .zero
        }
    }

    // MARK: - Public Methods

    func enableImageGestures() {
        print("🖼️ [ImageView] enableImageGestures - 图片ID: \(layerNode.id.uuidString.prefix(8))")
        isUserInteractionEnabled = true
        panGesture.isEnabled = true
        tapGesture.isEnabled = true
        print("🖼️ [ImageView] 手势已启用 - tapGesture.isEnabled: \(tapGesture.isEnabled), isUserInteractionEnabled: \(isUserInteractionEnabled)")
    }
    
    func disableImageGestures() {
        print("🖼️ [ImageView] disableImageGestures - 图片ID: \(layerNode.id.uuidString.prefix(8))")
        isUserInteractionEnabled = false
        panGesture.isEnabled = false
        tapGesture.isEnabled = false
        print("🖼️ [ImageView] 手势已禁用")
    }
    
    /// 让"画布缩放"优先：当 scrollView pinch 能识别时，本对象的 pinch 应当失败
    func requireObjectPinchToFail(_ gesture: UIGestureRecognizer) {
        // 图片对象不需要 pinch 手势，使用控制点进行缩放
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("🖼️ [ImageView] touchesBegan - 图片ID: \(layerNode.id.uuidString.prefix(8))")
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        print("🖼️ [ImageView] touchesEnded - 图片ID: \(layerNode.id.uuidString.prefix(8))")
        super.touchesEnded(touches, with: event)
    }

    // MARK: - Helper Methods
    
    private func addLockIndicator() {
        let lockIcon = UIImageView(image: UIImage(systemName: "lock.fill"))
        lockIcon.tintColor = .systemRed
        lockIcon.backgroundColor = .white
        lockIcon.layer.cornerRadius = 12
        lockIcon.clipsToBounds = true
        lockIcon.tag = 999
        lockIcon.frame = CGRect(x: 8, y: 8, width: 24, height: 24)
        addSubview(lockIcon)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // 更新图片视图 frame - 即使在手势中也要更新，确保图像跟着缩放
        imageView.frame = bounds
        
        // 更新选中外观
        if isSelected {
            updateSelectionAppearance()
        }
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SelectableImageView: UIGestureRecognizerDelegate {
}
