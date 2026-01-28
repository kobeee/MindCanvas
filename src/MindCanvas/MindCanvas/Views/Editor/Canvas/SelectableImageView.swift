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
        // 使用 scaleToFill 以支持自由缩放（宽高独立变化）
        // 图片会拉伸填满整个视图，与自由缩放逻辑保持一致
        view.contentMode = .scaleToFill
        view.clipsToBounds = true
        return view
    }()

    // 置顶胶囊按钮
    private let bringToFrontButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("置顶", for: .normal)
        button.backgroundColor = .white
        button.setTitleColor(.systemBlue, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        button.layer.cornerRadius = 12
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.systemBlue.cgColor
        button.isHidden = true
        return button
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
    var onBringToFront: ((UUID) -> Void)?

    // MARK: - Initialization

    init(layerNode: LayerNode) {
        self.layerNode = layerNode
        super.init(frame: layerNode.frame)
        
        setupViews()
        setupGestures()
        loadImage()
        updateFromNode()
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

        // 添加置顶按钮
        addSubview(bringToFrontButton)
        bringToFrontButton.addTarget(self, action: #selector(handleBringToFront), for: .touchUpInside)

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
        addGestureRecognizer(tapGesture)

        // 拖拽手势
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
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
    
    /// 标记是否已经完成首次图片加载（防止重复调整尺寸）
    private var hasCompletedInitialLoad = false

    private func loadImage() {
        guard let urlString = layerNode.url else {
            return
        }

        // 使用 ImageStorageService 统一处理路径
        // 支持：相对路径、绝对路径、file:// URL、远程 URL

        // 判断是否为本地路径（相对路径或 file:// URL）
        let isLocalPath = ImageStorageService.isRelativePath(urlString) ||
                          (URL(string: urlString)?.isFileURL == true)

        if isLocalPath {
            // 本地图片：使用 ImageStorageService 加载（支持相对路径和路径恢复）
            if let image = ImageStorageService.shared.loadImage(from: urlString) {
                imageView.image = image
                handleImageLoaded(image)
            }
        } else if let url = URL(string: urlString) {
            // 远程 URL：异步加载
            Task { @MainActor in
                if let image = await ImageStorageService.shared.getImage(from: url) {
                    self.imageView.image = image
                    self.handleImageLoaded(image)
                }
            }
        }
    }
    
    /// 处理图片加载完成
    /// 只在必要时更新尺寸，避免重复调整导致的突变
    private func handleImageLoaded(_ image: UIImage) {
        // 如果已经完成初次加载，不再调整尺寸
        guard !hasCompletedInitialLoad else {
            return
        }
        hasCompletedInitialLoad = true

        // 更新 originalSize（如果还没有设置）
        // 注意：不再自动调整 frame，保持创建时设置的尺寸
        if layerNode.originalSize == nil {
            // 只更新 originalSize，不改变 frame
            let updatedNode = LayerNode(
                id: layerNode.id,
                type: layerNode.type,
                url: layerNode.url,
                frame: layerNode.frame,  // 保持原有 frame 不变
                originalSize: image.size,  // 设置原始尺寸
                rotation: layerNode.rotation,
                isLocked: layerNode.isLocked,
                zIndex: layerNode.zIndex,
                opacity: layerNode.opacity,
                createdAt: layerNode.createdAt
            )
            layerNode = updatedNode
            onNodeUpdated?(layerNode)
        }
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

        // 防护：如果与上次同步的 frame 完全相同，不再更新（防抖机制）
        // 注意：必须同时检查位置和大小，否则移动操作会被错误地跳过
        if let lastFrame = lastSyncedFrame,
           abs(lastFrame.origin.x - newFrame.origin.x) < 0.1,
           abs(lastFrame.origin.y - newFrame.origin.y) < 0.1,
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

        selectionBorder.isHidden = !showHandles
        rotationLineLayer.isHidden = !showHandles
        rotationHandleLayer.isHidden = !showHandles
        cornerHandleLayers.forEach { $0.isHidden = !showHandles }

        // 更新置顶按钮显示状态
        bringToFrontButton.isHidden = !isSelected

        guard showHandles else {
            return
        }

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

        // 更新置顶按钮位置
        updateBringToFrontButtonPosition()
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
        
        // 3. 检查置顶按钮区域（在选中状态下）
        if !bringToFrontButton.isHidden && bringToFrontButton.frame.contains(point) {
            return true
        }
        
        // 4. 仅对控制点周围22pt半径区域进行扩展（精确控制点扩展）
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
        
        // 5. 不在控制点区域，返回false（消除隐形外圈区域）
        return false
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onSelected?(layerNode.id)
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

    /// 自由缩放方法 - 允许独立改变宽高比例
    private func handleResizeFixed(handle: ControlHandle, currentPoint: CGPoint) {
        // 统一使用自由缩放方法，允许任意改变长宽比
        handleResizeFreeform(handle: handle, currentPoint: currentPoint)
    }
    
    /// 自由缩放方法 - 可以独立改变宽度和高度
    private func handleResizeFreeform(handle: ControlHandle, currentPoint: CGPoint) {
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
        isUserInteractionEnabled = true
        panGesture.isEnabled = true
        tapGesture.isEnabled = true
    }

    func disableImageGestures() {
        isUserInteractionEnabled = false
        panGesture.isEnabled = false
        tapGesture.isEnabled = false
    }
    
    /// 让"画布缩放"优先：当 scrollView pinch 能识别时，本对象的 pinch 应当失败
    func requireObjectPinchToFail(_ gesture: UIGestureRecognizer) {
        // 图片对象不需要 pinch 手势，使用控制点进行缩放
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
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

        // 更新置顶按钮位置
        updateBringToFrontButtonPosition()
    }

    // MARK: - Bring to Front Button

    /// 更新置顶按钮位置
    private func updateBringToFrontButtonPosition() {
        guard isSelected else { return }

        let buttonWidth: CGFloat = 60
        let buttonHeight: CGFloat = 24
        let buttonYOffset: CGFloat = 8

        bringToFrontButton.frame = CGRect(
            x: bounds.midX - buttonWidth / 2,
            y: bounds.maxY + buttonYOffset,
            width: buttonWidth,
            height: buttonHeight
        )
    }

    /// 处理置顶按钮点击
    @objc private func handleBringToFront() {
        onBringToFront?(layerNode.id)
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SelectableImageView: UIGestureRecognizerDelegate {
}
