import UIKit

/// 文本控制点类型
enum TextControlHandle: Int, CaseIterable {
    case topLeft = 0
    case topRight = 1
    case bottomRight = 2
    case bottomLeft = 3
    case rotation = 4

    func position(in bounds: CGRect, rotationOffset: CGFloat = 30) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: bounds.minX, y: bounds.minY)
        case .topRight: return CGPoint(x: bounds.maxX, y: bounds.minY)
        case .bottomRight: return CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .bottomLeft: return CGPoint(x: bounds.minX, y: bounds.maxY)
        case .rotation: return CGPoint(x: bounds.midX, y: bounds.minY - rotationOffset)
        }
    }

    var oppositeCorner: TextControlHandle? {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomRight: return .topLeft
        case .bottomLeft: return .topRight
        case .rotation: return nil
        }
    }
}

/// 可选择的文本视图（重构版）
/// 使用UILabel渲染文字，UITextView进行编辑
class SelectableTextView: UIView {

    // MARK: - Properties

    var textNode: TextLayerNode {
        didSet { updateFromNode() }
    }

    // 显示层 - 使用UILabel替代CATextLayer
    private let textLabel = UILabel()

    // 编辑层 - 使用UITextView替代UITextField
    private var editingTextView: UITextView?

    // 选中边框
    private let selectionBorder = CAShapeLayer()

    // 控制点图层
    private var cornerHandleLayers: [CAShapeLayer] = []
    private let rotationHandleLayer = CAShapeLayer()
    private let rotationLineLayer = CAShapeLayer()

    // 控制点配置
    private let handleSize: CGFloat = 12
    private let rotationHandleOffset: CGFloat = 30

    // 当前活动的控制点
    private var activeHandle: TextControlHandle?

    // 选中状态
    var isSelected: Bool = false {
        didSet { updateSelectionAppearance() }
    }

    // 编辑状态
    var isEditing: Bool = false {
        didSet { updateEditingState() }
    }
    
    // 占位符状态
    private var isShowingPlaceholder: Bool = false
    private let placeholderText = "输入文本"
    
    // 键盘定位状态
    
    // 全局状态跟踪（所有SelectableTextView实例共享）
    private static var isKeyboardVisible = false
    private static var originalContentOffset: CGPoint = .zero
    private static var responsibleInstance: SelectableTextView? // 负责键盘定位的实例
    private static var hasAdjustedForKeyboard = false

    // 手势
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    private var doubleTapGesture: UITapGestureRecognizer!

    // 初始状态（用于旋转和缩放）
    private var initialCenter: CGPoint = .zero
    private var initialBounds: CGRect = .zero
    private var initialRotation: CGFloat = 0
    private var initialTouchAngle: CGFloat = 0
    private var initialNode: TextLayerNode?
    private var dragStartPoint: CGPoint = .zero

    // 回调
    var onNodeUpdated: ((TextLayerNode) -> Void)?
    var onSelected: ((UUID) -> Void)?
    var onOperationStart: ((TextLayerNode) -> Void)?
    var onOperationEnd: ((SelectableTextView?, TextLayerNode) -> Void)?
    var onEditingStarted: ((TextLayerNode) -> Void)?
    var onEditingFinished: ((TextLayerNode, String) -> Void)?

    // MARK: - Initialization

    init(textNode: TextLayerNode) {
        self.textNode = textNode
        // 修复：使用size初始化frame，不包含position信息
        // position通过center设置，而不是通过frame.origin
        let textBounds = textNode.bounds
        let size = textBounds.size
        super.init(frame: CGRect(origin: .zero, size: size))

        setupViews()
        setupGestures()

        // 设置center位置（必须在添加到父视图后生效）
        // updateFromNode会正确设置center
        updateFromNode()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = false

        // 配置UILabel - 替代CATextLayer
        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        textLabel.backgroundColor = .clear
        textLabel.isUserInteractionEnabled = false
        addSubview(textLabel)

        // 添加选中边框
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.strokeColor = UIColor.systemBlue.cgColor
        selectionBorder.lineWidth = 1.5
        selectionBorder.lineDashPattern = [4, 4]
        layer.addSublayer(selectionBorder)

        // 添加旋转连接线
        rotationLineLayer.fillColor = UIColor.clear.cgColor
        rotationLineLayer.strokeColor = UIColor.systemBlue.cgColor
        rotationLineLayer.lineWidth = 1.5
        layer.addSublayer(rotationLineLayer)

        // 添加旋转手柄
        rotationHandleLayer.fillColor = UIColor.white.cgColor
        rotationHandleLayer.strokeColor = UIColor.systemBlue.cgColor
        rotationHandleLayer.lineWidth = 2
        layer.addSublayer(rotationHandleLayer)

        // 添加角点控制点
        for _ in 0..<4 {
            let handleLayer = CAShapeLayer()
            handleLayer.fillColor = UIColor.white.cgColor
            handleLayer.strokeColor = UIColor.systemBlue.cgColor
            handleLayer.lineWidth = 2
            layer.addSublayer(handleLayer)
            cornerHandleLayers.append(handleLayer)
        }
    }

    private func setupGestures() {
        // 点击手势
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        // 双击手势（用于编辑）
        doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTapGesture.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTapGesture)

        // 确保点击手势和双击手势不冲突
        tapGesture.require(toFail: doubleTapGesture)

        // 拖拽手势
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
    }

    // MARK: - Update Methods

    func updateFromNode() {
        // 重置transform以便正确计算
        transform = .identity

        // 计算边界
        let textBounds = textNode.bounds
        bounds = CGRect(origin: .zero, size: textBounds.size)
        center = textNode.position

        // 更新UILabel
        updateTextLabel()

        // 应用旋转
        transform = CGAffineTransform(rotationAngle: textNode.rotation)

        // 更新选中外观
        updateSelectionAppearance()
    }

    private func updateTextLabel() {
        // 设置文字内容 - 不显示占位符，只显示实际内容
        textLabel.text = textNode.text
        textLabel.textColor = UIColor(hex: textNode.color) ?? .black

        // 设置字体
        let font = UIFont(name: textNode.fontName, size: textNode.fontSize * textNode.scale)
            ?? UIFont.systemFont(ofSize: textNode.fontSize * textNode.scale)
        textLabel.font = font

        // 设置frame - 确保UILabel填满整个bounds
        textLabel.frame = bounds
        
        // 如果文本为空，隐藏视图
        isHidden = textNode.text.isEmpty
    }

    private func syncToNode() {
        let currentRotation = atan2(transform.b, transform.a)

        textNode = textNode.updated(
            position: center,
            rotation: currentRotation
        )

        onNodeUpdated?(textNode)
    }

    private func updateSelectionAppearance() {
        let showHandles = isSelected && !isEditing

        selectionBorder.isHidden = !showHandles
        rotationLineLayer.isHidden = !showHandles
        rotationHandleLayer.isHidden = !showHandles
        cornerHandleLayers.forEach { $0.isHidden = !showHandles }

        guard showHandles else { return }

        // 更新选中边框
        selectionBorder.path = UIBezierPath(rect: bounds).cgPath

        // 更新角点控制点
        let corners: [TextControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
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

        // 更新旋转连接线
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
        linePath.addLine(to: CGPoint(x: bounds.midX, y: bounds.minY - rotationHandleOffset))
        rotationLineLayer.path = linePath.cgPath

        // 更新旋转手柄
        let rotationPos = TextControlHandle.rotation.position(in: bounds, rotationOffset: rotationHandleOffset)
        let rotationRect = CGRect(
            x: rotationPos.x - handleSize / 2,
            y: rotationPos.y - handleSize / 2,
            width: handleSize,
            height: handleSize
        )
        rotationHandleLayer.path = UIBezierPath(ovalIn: rotationRect).cgPath
    }

    // MARK: - Hit Testing

    private func hitTestHandle(at point: CGPoint) -> TextControlHandle? {
        guard isSelected else { return nil }

        let hitRadius: CGFloat = handleSize + 10

        // 坐标转换：将触摸点从旋转后的坐标系转换到本地坐标系
        let rotationAngle = atan2(transform.b, transform.a)
        let cosR = cos(-rotationAngle)
        let sinR = sin(-rotationAngle)

        let centerPoint = CGPoint(x: bounds.midX, y: bounds.midY)
        let relativePoint = CGPoint(x: point.x - centerPoint.x, y: point.y - centerPoint.y)
        let rotatedPoint = CGPoint(
            x: relativePoint.x * cosR - relativePoint.y * sinR,
            y: relativePoint.x * sinR + relativePoint.y * cosR
        )
        let localTouchPoint = CGPoint(x: rotatedPoint.x + centerPoint.x, y: rotatedPoint.y + centerPoint.y)

        // 先检查旋转手柄
        let rotationPos = TextControlHandle.rotation.position(in: bounds, rotationOffset: rotationHandleOffset)
        if distance(from: localTouchPoint, to: rotationPos) < hitRadius {
            return .rotation
        }

        // 再检查角点
        let corners: [TextControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        for corner in corners {
            let cornerPos = corner.position(in: bounds)
            if distance(from: localTouchPoint, to: cornerPos) < hitRadius {
                return corner
            }
        }

        return nil
    }

    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // 1. 编辑状态：扩大点击区域，包含 UITextView
        if isEditing {
            let expandedBounds = bounds.insetBy(dx: -20, dy: -20)
            return expandedBounds.contains(point)
        }

        // 2. 在原始 bounds 内
        if bounds.contains(point) {
            return true
        }

        // 3. 选中状态：检查控制点区域
        guard isSelected else {
            return false
        }

        let controlPointHitRadius: CGFloat = 22

        // 检查旋转手柄
        let rotationPos = TextControlHandle.rotation.position(in: bounds, rotationOffset: rotationHandleOffset)
        if distance(from: point, to: rotationPos) <= controlPointHitRadius {
            return true
        }

        // 检查角点
        let corners: [TextControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
        for corner in corners {
            let cornerPos = corner.position(in: bounds)
            if distance(from: point, to: cornerPos) <= controlPointHitRadius {
                return true
            }
        }

        return false
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if !isEditing {
            onSelected?(textNode.id)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        startEditing()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let locationInSelf = gesture.location(in: self)
        let locationInSuperview = gesture.location(in: superview)

        switch gesture.state {
        case .began:
            initialNode = textNode
            onOperationStart?(textNode)

            activeHandle = hitTestHandle(at: locationInSelf)

            initialCenter = center
            initialBounds = bounds
            initialRotation = atan2(transform.b, transform.a)

            if activeHandle == .rotation {
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
                case .rotation:
                    handleRotation(currentPoint: currentPoint)
                default:
                    handleResize(handle: handle, currentPoint: currentPoint)
                }
            } else {
                handleMove(currentPoint: currentPoint)
            }

        case .ended, .cancelled:
            syncToNode()
            if initialNode != nil {
                onOperationEnd?(self, textNode)
            }
            activeHandle = nil
            initialNode = nil

        default:
            break
        }
    }

    private func handleMove(currentPoint: CGPoint) {
        let dx = currentPoint.x - dragStartPoint.x
        let dy = currentPoint.y - dragStartPoint.y
        center = CGPoint(x: initialCenter.x + dx, y: initialCenter.y + dy)
    }

    private func handleRotation(currentPoint: CGPoint) {
        let currentTouchAngle = atan2(
            currentPoint.y - initialCenter.y,
            currentPoint.x - initialCenter.x
        )
        let deltaAngle = currentTouchAngle - initialTouchAngle
        let newRotation = initialRotation + deltaAngle
        transform = CGAffineTransform(rotationAngle: newRotation)
        updateSelectionAppearance()
    }

    private func handleResize(handle: TextControlHandle, currentPoint: CGPoint) {
        // 简化的缩放实现：根据拖拽距离计算缩放因子
        let dragDeltaX = currentPoint.x - dragStartPoint.x
        let dragDeltaY = currentPoint.y - dragStartPoint.y

        // 计算拖拽方向上的总距离
        let totalDelta = sqrt(dragDeltaX * dragDeltaX + dragDeltaY * dragDeltaY)
        let sign: CGFloat = (dragDeltaX + dragDeltaY) > 0 ? 1 : -1

        // 计算缩放因子（限制在合理范围内）
        let scaleFactor = 1.0 + (sign * totalDelta) / 200.0
        let newScale = max(0.5, min(3.0, textNode.scale * scaleFactor))

        // 更新节点
        textNode = textNode.updated(scale: newScale)

        // 重新计算边界
        let textBounds = textNode.bounds
        bounds = CGRect(origin: .zero, size: textBounds.size)
        textLabel.frame = bounds

        // 保持旋转角度
        transform = CGAffineTransform(rotationAngle: initialRotation)

        updateSelectionAppearance()
    }

    // MARK: - Editing Methods

    /// 开始编辑文字
    func startEditing() {
        guard !isEditing else { return }

        isEditing = true
        onEditingStarted?(textNode)

        // 关键修复：键盘已显示时，保留原始位置信息
        // 不重置 hasAdjustedForKeyboard 和 responsibleInstance
        // 这些信息需要保留到键盘真正收起时使用
        if Self.isKeyboardVisible {
            // 注意：不清除 hasAdjustedForKeyboard 和 responsibleInstance
            // 这些信息需要保留到键盘真正收起时使用
        }

        // 隐藏Label
        textLabel.isHidden = true

        // 创建UITextView
        setupEditingTextView()
    }

    /// 完成编辑文字
    func finishEditing() {
        guard isEditing else { return }

        let rawText = editingTextView?.text ?? ""
        let originalText = textNode.text

        // 处理占位符情况
        let newText: String
        if isShowingPlaceholder || rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newText = ""
        } else {
            newText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 关键修复：finishEditing不再主动恢复画布位置
        // 恢复逻辑完全由keyboardWillHide负责
        // 这样可以正确处理"切换编辑位置"（键盘保持）和"真正收起键盘"的区别
        //
        // 注意：我们需要在resignFirstResponder之前保持监听器存活
        // 只有这样才能接收到keyboardWillHide通知
        //
        // 状态保留逻辑：
        // - hasAdjustedForKeyboard: 保留（由keyboardWillHide负责重置）
        // - responsibleInstance: 保留（由keyboardWillHide负责重置）
        // - originalContentOffset: 保留（由keyboardWillHide负责重置）
        // - isKeyboardVisible: 保留（由keyboardWillHide负责重置）
        //
        // 只有当没有调整过位置时，才清理状态
        if !Self.hasAdjustedForKeyboard {
            Self.responsibleInstance = nil
            Self.originalContentOffset = .zero
        }
        // 注意：不要在这里重置isKeyboardVisible，由keyboardWillHide负责

        // 清理编辑视图
        cleanupEditingTextView()

        // 显示Label
        textLabel.isHidden = false
        isEditing = false
        isShowingPlaceholder = false

        // 如果文本为空，通过回调通知删除该对象
        if newText.isEmpty {
            onEditingFinished?(textNode, "")
            return
        }

        // 更新节点
        textNode = textNode.updated(text: newText)

        // 更新显示
        updateFromNode()

        // 回调
        if newText != originalText {
            onEditingFinished?(textNode, newText)
        }
        onNodeUpdated?(textNode)
    }
    
    /// 计算文本是否被键盘（及其上方的工具栏）遮挡
    ///
    /// 遮挡区域包括：
    /// 1. 键盘本身的高度
    /// 2. 键盘上方的工具栏高度（约60点，包含内边距）
    /// 3. 舒适边距
    private func calculateIfTextIsHidden(scrollView: UIScrollView, keyboardFrame: CGRect, textView: UITextView?) -> Bool {
        guard let textView = textView else { return false }
        guard let window = scrollView.window else { return false }

        // 工具栏高度（包含padding）
        // CanvasToolbar高度约50点，加上安全区域和内边距
        let toolbarHeight: CGFloat = 60

        // 舒适边距，确保文本框与工具栏有足够间距
        let comfortMargin: CGFloat = 20

        // 计算有效遮挡区域顶部 = 键盘顶部 - 工具栏高度 - 舒适边距
        // 这个区域是键盘弹出后，文本框不应该出现的区域
        let keyboardTopInWindow = window.bounds.height - keyboardFrame.height
        let effectiveOcclusionTop = keyboardTopInWindow - toolbarHeight - comfortMargin

        // 计算文本框底部在window坐标系中的位置
        let textViewFrameInWindow = textView.convert(textView.bounds, to: window)
        let textViewBottomInWindow = textViewFrameInWindow.maxY

        // 如果文本框底部低于有效遮挡区域顶部，则需要调整
        let isHidden = textViewBottomInWindow > effectiveOcclusionTop

        

        return isHidden
    }
    
        
    
        /// 恢复画布位置（如果需要）
    private func restoreCanvasPositionIfNeeded() {
        // 只有在之前调整过位置时才恢复
        guard Self.hasAdjustedForKeyboard else { return }
        
        guard let canvasView = findParentCanvasView() else { return }
        
        let scrollView = canvasView.pencilCanvas
        let currentOffset = scrollView.contentOffset
        
        // 如果当前位置不等于原始位置，则恢复
        if currentOffset != Self.originalContentOffset {
            let animationDuration = 0.3
            
            UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut], animations: {
                scrollView.setContentOffset(Self.originalContentOffset, animated: false)
            }) { _ in
                // 恢复完成后，更新UITextView位置并重置所有状态
                self.updateTextViewPositionAfterScroll()
                Self.hasAdjustedForKeyboard = false
                Self.responsibleInstance = nil  // 重要：重置负责实例
            }
        } else {
            // 即使不需要恢复位置，也要重置状态
            Self.hasAdjustedForKeyboard = false
            Self.responsibleInstance = nil  // 重要：重置负责实例
        }
    }

    /// Setup UITextView for editing - Refactored: Use independent editing container
    private func setupEditingTextView() {
        // Safety check
        guard bounds.width >= 10 && bounds.height >= 10 else {
            isEditing = false
            textLabel.isHidden = false
            return
        }

        guard window != nil else {
            isEditing = false
            textLabel.isHidden = false
            return
        }

        // Setup keyboard notification listeners
        setupKeyboardNotifications()

        // Key refactor: Add UITextView to independent editing container to avoid transform impact
        createTextViewInIndependentContainer()
    }
    
    /// Create UITextView for true in-place editing
    private func createTextViewInIndependentContainer() {
        // 开始创建编辑框
        
        // Get NativeCanvasView reference
        guard let canvasView = findParentCanvasView() else {
            return
        }
        
        // Key insight: UITextView should be placed in the transformed coordinate system
        // but positioned exactly where the text will appear
        let canvasContentOffset = canvasView.pencilCanvas.contentOffset
        let canvasScale = canvasView.pencilCanvas.zoomScale
        
        // Calculate position in canvas content coordinates (where the text will finally be)
        let finalTextPosition = textNode.position
        
        // Convert to screen coordinates for UITextView positioning
        let screenX = (finalTextPosition.x * canvasScale) - canvasContentOffset.x
        let screenY = (finalTextPosition.y * canvasScale) - canvasContentOffset.y
        
        // TextView坐标计算完成
        
        // Create UITextView with frame sized for "输入文本" placeholder
        let initialFrame = CGRect(
            x: screenX - 50,  // Increased width to accommodate "输入文本"
            y: screenY - 20,  // Increased height for better visibility
            width: 100,
            height: 40
        )
        
        // TextView初始frame设置完成
        
        let textView = UITextView(frame: initialFrame)
        
        // Configure UITextView for in-place editing - make it blend with the canvas
        textView.text = textNode.text
        textView.font = textLabel.font
        textView.textColor = UIColor(hex: textNode.color) ?? .black
        textView.textAlignment = .center
        textView.backgroundColor = UIColor.clear  // Transparent background for true in-place feel
        textView.layer.cornerRadius = 0  // No corner radius for seamless integration
        textView.layer.borderWidth = 1  // Minimal border to show editing state
        textView.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.5).cgColor
        textView.delegate = self
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.returnKeyType = .done
        textView.tintColor = UIColor(hex: textNode.color) ?? .systemBlue
        
        // Key: Disable UITextView scrolling to avoid conflicts with PKCanvasView
        textView.isScrollEnabled = false
        
        // Remove shadow for cleaner in-place appearance
        textView.layer.shadowColor = UIColor.clear.cgColor
        textView.layer.shadowOpacity = 0
        
        // In-place editing visual feedback - subtle indication
        textView.layer.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.1).cgColor
        
        // Handle placeholder with fixed font size
        if textView.text.isEmpty {
            textView.text = placeholderText
            textView.textColor = .systemGray
            // Use a fixed font size for placeholder (16pt) regardless of user's text size
            textView.font = UIFont.systemFont(ofSize: 16)
            isShowingPlaceholder = true
        } else {
            // Restore user's font size for actual text
            textView.font = textLabel.font
            isShowingPlaceholder = false
        }

        // Key insight: Add UITextView directly to canvasView's overlayContainerView
        // This ensures it follows the same transform as other canvas objects for true in-place editing
        canvasView.overlayContainerView.addSubview(textView)
        canvasView.overlayContainerView.bringSubviewToFront(textView)
        editingTextView = textView
        
        // TextView成功添加到overlayContainerView
        // 视图frame设置完成
        
        // Set up dynamic text sizing to match final text appearance
        setupDynamicTextSizing(for: textView)

        // Activate keyboard immediately for seamless in-place experience
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isEditing else { 
                return 
            }
            guard let textView = self.editingTextView else { 
                return 
            }

            let success = textView.becomeFirstResponder()

            if success && !textView.text.isEmpty && !self.isShowingPlaceholder {
                textView.selectAll(nil)
            }
        }
    }
            
            /// Setup dynamic text sizing for true in-place editing experience
                private func setupDynamicTextSizing(for textView: UITextView) {                    
                    // Observe text changes to adjust frame dynamically
                    NotificationCenter.default.addObserver(
                        forName: UITextView.textDidChangeNotification,
                        object: textView,
                        queue: .main
                    ) { [weak self] _ in
                        guard let self = self, self.isEditing else { return }
                        guard let textView = self.editingTextView else { return }
                        
                        self.updateTextViewSizeForContent(textView)
                    }
                }
                
                /// Update UITextView size based on content for seamless in-place editing
                private func updateTextViewSizeForContent(_ textView: UITextView) {
                    // Calculate the size needed for the current text
                    let maxSize = CGSize(width: 300, height: 1000) // Max width for text wrapping
                    let textRect = textView.text.boundingRect(
                        with: maxSize,
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: textView.font ?? UIFont.systemFont(ofSize: textNode.fontSize)],
                        context: nil
                    )
                    
                    // Add padding
                    let padding: CGFloat = 16
                    let newSize = CGSize(
                        width: max(60, textRect.width + padding),
                        height: max(30, textRect.height + padding)
                    )
                    
                    // Update frame while maintaining center position
                    let currentCenter = textView.center
                    textView.frame = CGRect(
                        x: currentCenter.x - newSize.width / 2,
                        y: currentCenter.y - newSize.height / 2,
                        width: newSize.width,
                        height: newSize.height
                    )
                    
                    
                }

    /// Clean up UITextView after in-place editing
    private func cleanupEditingTextView() {
        // Clean up text change observer
        if let textView = editingTextView {
            NotificationCenter.default.removeObserver(self, name: UITextView.textDidChangeNotification, object: textView)
        }

        // 关键修复：先resignFirstResponder，让keyboardWillHide有机会被触发
        // 然后再移除键盘通知监听器
        // 这样可以正确接收到键盘隐藏通知并执行画布位置恢复
        editingTextView?.resignFirstResponder()

        // 延迟移除监听器，确保keyboardWillHide有机会被接收和处理
        // 使用异步执行，让当前RunLoop周期完成后再移除
        DispatchQueue.main.async { [weak self] in
            self?.removeKeyboardNotifications()
        }

        editingTextView?.removeFromSuperview()
        editingTextView = nil
    }

    /// 更新编辑状态
    private func updateEditingState() {
        if isEditing {
            // 编辑状态下隐藏选中边框
            selectionBorder.isHidden = true
            // 禁用拖拽手势
            panGesture.isEnabled = false
        } else {
            // 恢复选中状态显示
            updateSelectionAppearance()
            // 启用拖拽手势
            panGesture.isEnabled = true
        }
    }

    // MARK: - Helper Methods
    
    /// 调整UITextView位置以确保可见性
    private func adjustTextViewPositionForVisibility(_ textView: UITextView) {
        guard let window = window else { return }
        
        
        
        // 获取当前在屏幕坐标系中的frame
        let currentScreenFrame = convert(textView.frame, to: window)
        let windowBounds = window.bounds
        
        // 计算需要的偏移量
        var adjustedFrame = textView.frame
        
        // 水平方向调整
                    if currentScreenFrame.maxX > windowBounds.maxX {
                        let overflow = currentScreenFrame.maxX - windowBounds.maxX
                        adjustedFrame.origin.x -= overflow
                    } else if currentScreenFrame.minX < windowBounds.minX {
                        let overflow = windowBounds.minX - currentScreenFrame.minX
                        adjustedFrame.origin.x += overflow
                    }
                    
                    // 垂直方向调整
                    if currentScreenFrame.maxY > windowBounds.maxY {
                        let overflow = currentScreenFrame.maxY - windowBounds.maxY
                        adjustedFrame.origin.y -= overflow
                    } else if currentScreenFrame.minY < windowBounds.minY {
                        let overflow = windowBounds.minY - currentScreenFrame.minY
                        adjustedFrame.origin.y += overflow
                    }        
// 应用调整
            if adjustedFrame != textView.frame {
                textView.frame = adjustedFrame
                
                // 再次验证调整后的可见性
                let newScreenFrame = convert(textView.frame, to: window)
                let isNowVisible = window.bounds.intersects(newScreenFrame)
            }
    }

    private func UIColor_fromHex(_ hex: String) -> UIColor {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        return UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

// MARK: - UITextViewDelegate

extension SelectableTextView: UITextViewDelegate {

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // 处理占位符：如果当前显示占位符且用户开始输入，清除占位符并恢复用户字体
        if isShowingPlaceholder && !text.isEmpty {
            textView.text = ""
            textView.textColor = UIColor(hex: textNode.color) ?? .black
            // Restore user's font size when they start typing
            textView.font = textLabel.font
            isShowingPlaceholder = false
        }
        
        // 回车键完成编辑
        if text == "\n" {
            finishEditing()
            return false
        }
        return true
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if isEditing {
            finishEditing()
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        // 如果当前显示占位符，准备清除
        if isShowingPlaceholder {
            // 准备清除占位符状态
        }
    }
}

// MARK: - Keyboard Handling

extension SelectableTextView {
    
    /// 重置全局键盘状态（仅重置状态，不恢复位置）
    static func resetGlobalKeyboardState() {
        isKeyboardVisible = false
        hasAdjustedForKeyboard = false
        originalContentOffset = .zero
        responsibleInstance = nil
    }

    /// 重置全局键盘状态并恢复画布位置
    /// - Parameter canvasView: 画布视图引用，用于执行位置恢复
    static func resetGlobalKeyboardStateAndRestorePosition(canvasView: NativeCanvasView?) {
        // 如果有调整过位置，先执行恢复
        if hasAdjustedForKeyboard, let canvasView = canvasView {
            let scrollView = canvasView.pencilCanvas
            let savedOffset = originalContentOffset

            UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
                scrollView.setContentOffset(savedOffset, animated: false)
            }
        }

        // 重置所有状态
        isKeyboardVisible = false
        hasAdjustedForKeyboard = false
        originalContentOffset = .zero
        responsibleInstance = nil
    }
    
    /// 设置键盘通知监听
    private func setupKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }
    
    /// 移除键盘通知监听
    func removeKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    @objc private func keyboardWillShow(notification: NSNotification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        guard let canvasView = findParentCanvasView() else { return }

        // 标记键盘为显示状态
        Self.isKeyboardVisible = true

        // 关键修复：如果已经有责任实例且已调整过位置，后续实例不应该重复处理
        // 这保证了originalContentOffset始终是第一次调整前的真实位置
        if Self.hasAdjustedForKeyboard && Self.responsibleInstance != nil {
            // 只需要更新当前UITextView的位置
            updateTextViewPositionAfterScroll()
            return
        }

        let scrollView = canvasView.pencilCanvas
        let currentScale = scrollView.zoomScale
        let currentOffset = scrollView.contentOffset
        let canvasBounds = scrollView.bounds
        let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3

        // 检查文本是否被键盘遮挡
        let isTextHidden = calculateIfTextIsHidden(
            scrollView: scrollView,
            keyboardFrame: keyboardFrame,
            textView: editingTextView
        )

        // 需要调整且尚未调整过
        if isTextHidden {
            // 记录原始位置（这是第一次调整，记录真实的原始位置）
            Self.originalContentOffset = currentOffset
            Self.responsibleInstance = self
            Self.hasAdjustedForKeyboard = true

            guard let textView = editingTextView else { return }
            guard let window = scrollView.window else { return }

            // 计算文本框位置
            let textNodePosition = textNode.position
            let screenX = (textNodePosition.x * currentScale) - currentOffset.x
            let screenY = (textNodePosition.y * currentScale) - currentOffset.y

            // 更新UITextView位置
            let textViewFrame = CGRect(
                x: screenX - textView.frame.width / 2,
                y: screenY - textView.frame.height / 2,
                width: textView.frame.width,
                height: textView.frame.height
            )
            textView.frame = textViewFrame

            // 计算重叠量（包含工具栏高度）
            let textViewFrameInWindow = textView.convert(textViewFrame, to: window)
            let textViewBottomInScreen = textViewFrameInWindow.maxY
            let keyboardHeight = keyboardFrame.height
            let keyboardTopInScreen = window.bounds.height - keyboardHeight

            // 工具栏高度（与calculateIfTextIsHidden保持一致）
            let toolbarHeight: CGFloat = 60

            // 有效遮挡区域顶部 = 键盘顶部 - 工具栏高度
            let effectiveOcclusionTop = keyboardTopInScreen - toolbarHeight

            // 计算需要滚动的距离：文本框底部到有效遮挡区域顶部
            let overlapAmount = textViewBottomInScreen - effectiveOcclusionTop

            if overlapAmount > 0 {
                let comfortableMargin: CGFloat = 30
                let maxScrollDistance = canvasBounds.height * 0.4
                let requiredOffset = min(max(0, overlapAmount + comfortableMargin), maxScrollDistance)
                let scrollOffset = requiredOffset / currentScale

                let newOffsetY = currentOffset.y + scrollOffset
                let maxOffsetY = scrollView.contentSize.height - canvasBounds.height
                let clampedOffsetY = min(newOffsetY, max(0, maxOffsetY))
                let newOffset = CGPoint(x: currentOffset.x, y: clampedOffsetY)

                UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut]) {
                    scrollView.setContentOffset(newOffset, animated: false)
                } completion: { _ in
                    self.updateTextViewPositionAfterScroll()
                }
            }
        } else {
            updateTextViewPositionAfterScroll()
        }
    }
    
    /// 滚动后更新UITextView位置
    private func updateTextViewPositionAfterScroll() {
        guard let textView = editingTextView,
              let canvasView = findParentCanvasView() else { return }
        
        let scrollView = canvasView.pencilCanvas
        let currentScale = scrollView.zoomScale
        let currentOffset = scrollView.contentOffset
        
        // 重新计算UITextView位置
        let textNodePosition = textNode.position
        let screenX = (textNodePosition.x * currentScale) - currentOffset.x
        let screenY = (textNodePosition.y * currentScale) - currentOffset.y
        
        let updatedFrame = CGRect(
            x: screenX - textView.frame.width / 2,
            y: screenY - textView.frame.height / 2,
            width: textView.frame.width,
            height: textView.frame.height
        )
        
        textView.frame = updatedFrame
        // 滚动后位置更新完成
    }
    
    @objc private func keyboardWillHide(notification: NSNotification) {
        // 重置键盘可见状态
        Self.isKeyboardVisible = false

        // 防御性检查：如果没有调整过位置，无需恢复
        guard Self.hasAdjustedForKeyboard else {
            Self.responsibleInstance = nil  // 清理可能的残留状态
            return
        }

        guard let canvasView = findParentCanvasView() else {
            // 清理状态
            Self.hasAdjustedForKeyboard = false
            Self.responsibleInstance = nil
            return
        }

        let scrollView = canvasView.pencilCanvas
        let currentOffset = scrollView.contentOffset
        let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.3

        // 恢复画布位置
        if currentOffset != Self.originalContentOffset {
            UIView.animate(withDuration: animationDuration, delay: 0, options: [.curveEaseOut]) {
                scrollView.setContentOffset(Self.originalContentOffset, animated: false)
            } completion: { _ in
                self.updateTextViewPositionAfterScroll()
            }
        }

        // 无论是否执行恢复，都要重置状态
        Self.hasAdjustedForKeyboard = false
        Self.responsibleInstance = nil
        Self.originalContentOffset = .zero
    }
    
    /// 查找父级的NativeCanvasView
    private func findParentCanvasView() -> NativeCanvasView? {
        var view: UIView? = superview
        while view != nil {
            if let canvasView = view as? NativeCanvasView {
                return canvasView
            }
            view = view?.superview
        }
        return nil
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SelectableTextView: UIGestureRecognizerDelegate {
    
    /// 启用文字手势（与其他视图保持一致）
    func enableTextGestures() {
        isUserInteractionEnabled = true
        tapGesture.isEnabled = true
        doubleTapGesture.isEnabled = true
        panGesture.isEnabled = !isEditing  // 编辑时禁用拖拽
    }
    
    /// 禁用文字手势（与其他视图保持一致）
    func disableTextGestures() {
        isUserInteractionEnabled = false
        tapGesture.isEnabled = false
        doubleTapGesture.isEnabled = false
        panGesture.isEnabled = false
    }
}

// MARK: - UIColor Extension

extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b, a: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}