import UIKit
import SwiftUI
import Foundation

/// 控制点类型
enum ControlHandle: Int, CaseIterable {
    case topLeft = 0
    case topRight = 1
    case bottomRight = 2
    case bottomLeft = 3
    case rotation = 4
    
    /// 控制点相对于边界框的位置
    func position(in bounds: CGRect, rotationHandleOffset: CGFloat = 30) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: bounds.minX, y: bounds.minY)
        case .topRight:
            return CGPoint(x: bounds.maxX, y: bounds.minY)
        case .bottomRight:
            return CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .bottomLeft:
            return CGPoint(x: bounds.minX, y: bounds.maxY)
        case .rotation:
            return CGPoint(x: bounds.midX, y: bounds.minY - rotationHandleOffset)
        }
    }
    
    /// 缩放时的锚点（对角点）
    var oppositeCorner: ControlHandle? {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomRight: return .topLeft
        case .bottomLeft: return .topRight
        case .rotation: return nil
        }
    }
}

/// 可选择的通用形状视图（支持控制点交互）
class SelectableShapeView: UIView {

    // MARK: - Properties

    var shapeNode: ShapeLayerNode {
        didSet {
            updateFromNode()
        }
    }

    // 图层
    private let shapeLayer = CAShapeLayer()
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
    private var initialNode: ShapeLayerNode?
    
    // 拖动开始时的角点实际位置（不是触摸点，是角点本身的位置）
    private var initialHandlePosition: CGPoint = .zero

    // 手势
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    // 回调
    var onNodeUpdated: ((ShapeLayerNode) -> Void)?
    var onSelected: ((UUID) -> Void)?
    var onOperationStart: ((ShapeLayerNode) -> Void)?
    var onOperationEnd: ((ShapeLayerNode, ShapeLayerNode) -> Void)?

    // MARK: - Initialization

    init(shapeNode: ShapeLayerNode) {
        self.shapeNode = shapeNode
        super.init(frame: shapeNode.frame)
        setupViews()
        setupGestures()
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

        // 添加形状图层
        layer.addSublayer(shapeLayer)
        
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
        updateShapeStyle()
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

    // MARK: - Style Updates

    private func updateShapeStyle() {
        shapeLayer.fillColor = shapeNode.isFilled ? UIColor_fromHex(shapeNode.color).cgColor : UIColor.clear.cgColor
        shapeLayer.strokeColor = UIColor_fromHex(shapeNode.color).cgColor
        shapeLayer.lineWidth = shapeNode.lineWidth
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
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

    // MARK: - Shape Path

    private func updateShapePath() {
        let path = createShapePath(for: shapeNode.shapeType, in: bounds)
        shapeLayer.path = path.cgPath
    }

    private func createShapePath(for shapeType: ShapeType, in rect: CGRect) -> UIBezierPath {
        switch shapeType {
        case .rectangle:
            return UIBezierPath(rect: rect)
            
        case .circle:
            return UIBezierPath(ovalIn: rect)
            
        case .triangle:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.close()
            return path
            
        case .diamond:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.close()
            return path
            
        case .pentagon:
            return createPolygonPath(in: rect, sides: 5)
            
        case .hexagon:
            return createPolygonPath(in: rect, sides: 6)
            
        case .star:
            return createStarPath(in: rect, points: 5)
            
        case .roundedRectangle:
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
            return path
            
        case .line:
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
            
        case .arrow:
            // Arrow is handled by SelectableArrowView, not SelectableShapeView
            return UIBezierPath()
        }
    }

    // MARK: - Sync Methods

    /// 从数据模型更新视图
    func updateFromNode() {
        // 重置 transform 为 identity
        transform = .identity

        // 设置 bounds 和 center
        bounds = CGRect(x: 0, y: 0, width: shapeNode.frame.width, height: shapeNode.frame.height)
        center = CGPoint(x: shapeNode.frame.midX, y: shapeNode.frame.midY)

        // 应用旋转
        transform = CGAffineTransform(rotationAngle: shapeNode.rotation)

        updateShapePath()
        updateSelectionAppearance()
    }

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

        shapeNode = shapeNode.updated(
            frame: newFrame,
            rotation: currentRotation
        )
        onNodeUpdated?(shapeNode)
    }

    // MARK: - Selection Appearance

    private func updateSelectionAppearance() {
        let showHandles = isSelected

        selectionBorder.isHidden = !showHandles
        rotationLineLayer.isHidden = !showHandles
        rotationHandleLayer.isHidden = !showHandles
        cornerHandleLayers.forEach { $0.isHidden = !showHandles }

        guard showHandles else { return }

        // 更新选中边框
        let borderRect = bounds
        selectionBorder.path = UIBezierPath(rect: borderRect).cgPath

        // 更新角点控制点
        let corners: [ControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
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
    }

    // MARK: - Hit Testing

    private func hitTestHandle(at point: CGPoint) -> ControlHandle? {
        guard isSelected else { return nil }

        let hitRadius: CGFloat = handleSize + 10

        // 先检查旋转手柄
        let rotationPos = ControlHandle.rotation.position(in: bounds, rotationHandleOffset: rotationHandleOffset)
        if distance(from: point, to: rotationPos) < hitRadius {
            return .rotation
        }

        // 再检查角点
        let corners: [ControlHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft]
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
        let expandedBounds = bounds.insetBy(
            dx: -(handleSize + rotationHandleOffset + 20),
            dy: -(handleSize + rotationHandleOffset + 20)
        )
        return expandedBounds.contains(point)
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onSelected?(shapeNode.id)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let locationInSelf = gesture.location(in: self)

        switch gesture.state {
        case .began:
            // 保存初始状态
            initialNode = shapeNode
            onOperationStart?(shapeNode)

            activeHandle = hitTestHandle(at: locationInSelf)

            // 关键: 保存 center 和 bounds，而非 frame
            initialCenter = center
            initialBounds = bounds
            initialRotation = atan2(transform.b, transform.a)

            // 如果是缩放，保存被拖动角点的实际位置（不是触摸点）
            if let handle = activeHandle, handle != .rotation {
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
                    handleRotationImproved(currentPoint: currentPoint)
                default:
                    handleResizeFixed(handle: handle, currentPoint: currentPoint)
                }
            } else {
                handleMoveImproved(currentPoint: currentPoint)
            }

        case .ended, .cancelled:
            syncToNode()
            if let initial = initialNode {
                onOperationEnd?(initial, shapeNode)
            }
            activeHandle = nil
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

    

    /// 修复后的缩放方法 - 使用增量计算，避免第一帧跳变
    private func handleResizeFixed(handle: ControlHandle, currentPoint: CGPoint) {
        guard let oppositeCorner = handle.oppositeCorner else { return }

        // Step 1: 计算锚点位置（对角点）
        let anchorLocalOffset = anchorOffset(for: oppositeCorner)
        let cosR = cos(initialRotation)
        let sinR = sin(initialRotation)

        let anchorInSuperview = CGPoint(
            x: initialCenter.x + anchorLocalOffset.x * cosR - anchorLocalOffset.y * sinR,
            y: initialCenter.y + anchorLocalOffset.x * sinR + anchorLocalOffset.y * cosR
        )

        // Step 2: 计算拖动增量（关键修复：使用 dragStartPoint 而非 anchorInSuperview）
        let dragDeltaX = currentPoint.x - dragStartPoint.x
        let dragDeltaY = currentPoint.y - dragStartPoint.y

        // Step 3: 将拖动增量逆旋转到本地坐标系
        let cosNegR = cos(-initialRotation)
        let sinNegR = sin(-initialRotation)
        let localDeltaX = dragDeltaX * cosNegR - dragDeltaY * sinNegR
        let localDeltaY = dragDeltaX * sinNegR + dragDeltaY * cosNegR

        // Step 4: 计算新尺寸（增量计算，不是绝对计算）
        // 根据拖动方向决定符号
        let widthSign: CGFloat = (handle == .topLeft || handle == .bottomLeft) ? -1 : 1
        let heightSign: CGFloat = (handle == .topLeft || handle == .topRight) ? -1 : 1

        var newWidth = initialBounds.width + localDeltaX * widthSign
        var newHeight = initialBounds.height + localDeltaY * heightSign

        // 最小尺寸限制
        let minSize: CGFloat = 20
        newWidth = max(newWidth, minSize)
        newHeight = max(newHeight, minSize)

        // Step 5: 计算新中心点
        // 锚点固定不动，中心点根据新尺寸移动
        let newHalfWidth = newWidth / 2
        let newHalfHeight = newHeight / 2

        // 新中心相对于锚点的本地偏移（注意符号与锚点相反）
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

        // Step 8: 更新内容
        updateShapePath()
        updateSelectionAppearance()
    }

    /// 改进的旋转方法
    private func handleRotationImproved(currentPoint: CGPoint) {
        // 关键: 使用 initialCenter 而非 frame.mid
        // 因为 frame 在有 transform 时是不可靠的

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
        case .topLeft:
            return CGPoint(x: -halfWidth, y: -halfHeight)
        case .topRight:
            return CGPoint(x: halfWidth, y: -halfHeight)
        case .bottomRight:
            return CGPoint(x: halfWidth, y: halfHeight)
        case .bottomLeft:
            return CGPoint(x: -halfWidth, y: halfHeight)
        case .rotation:
            return .zero
        }
    }

    /// 计算控制点（拖动的那个角）相对于中心的偏移量
    private func handleOffset(for handle: ControlHandle) -> CGPoint {
        let halfWidth = initialBounds.width / 2
        let halfHeight = initialBounds.height / 2

        switch handle {
        case .topLeft:
            return CGPoint(x: -halfWidth, y: -halfHeight)
        case .topRight:
            return CGPoint(x: halfWidth, y: -halfHeight)
        case .bottomRight:
            return CGPoint(x: halfWidth, y: halfHeight)
        case .bottomLeft:
            return CGPoint(x: -halfWidth, y: halfHeight)
        case .rotation:
            return .zero
        }
    }

    // MARK: - Public Methods

    func enableShapeGestures() {
        isUserInteractionEnabled = true
        panGesture.isEnabled = true
        tapGesture.isEnabled = true
    }

    // MARK: - Helper Methods

    private func createStarPath(in rect: CGRect, points: Int) -> UIBezierPath {
        let path = UIBezierPath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.4

        for i in 0..<(points * 2) {
            let radius = i % 2 == 0 ? outerRadius : innerRadius
            let angle = CGFloat(i) * .pi / CGFloat(points) - .pi / 2
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        return path
    }

    private func createPolygonPath(in rect: CGRect, sides: Int) -> UIBezierPath {
        let path = UIBezierPath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        for i in 0..<sides {
            let angle = CGFloat(i) * 2 * .pi / CGFloat(sides) - .pi / 2
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        return path
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateShapePath()
        if isSelected {
            updateSelectionAppearance()
        }
    }
    
    // MARK: - Private Helper Functions
    
    /// Convert hex string to UIColor
    private func UIColor_fromHex(_ hex: String) -> UIColor {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        return UIColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SelectableShapeView: UIGestureRecognizerDelegate {
}
