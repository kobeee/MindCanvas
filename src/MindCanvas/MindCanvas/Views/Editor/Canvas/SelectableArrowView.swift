import UIKit
import SwiftUI

/// 箭头控制点类型
enum ArrowHandle: Int {
    case startPoint = 0
    case endPoint = 1
    
    /// 获取控制点在箭头中的位置
    func position(for arrow: ArrowLayerNode, in bounds: CGRect) -> CGPoint {
        let center = arrow.center
        let scale = arrow.scale
        
        switch self {
        case .startPoint:
            let offset = CGPoint(
                x: arrow.startPoint.x - center.x,
                y: arrow.startPoint.y - center.y
            )
            return CGPoint(
                x: bounds.width / 2 + offset.x * scale,
                y: bounds.height / 2 + offset.y * scale
            )
        case .endPoint:
            let offset = CGPoint(
                x: arrow.endPoint.x - center.x,
                y: arrow.endPoint.y - center.y
            )
            return CGPoint(
                x: bounds.width / 2 + offset.x * scale,
                y: bounds.height / 2 + offset.y * scale
            )
        }
    }
}

/// 可选择的箭头视图（支持端点控制点交互）
class SelectableArrowView: UIView {
    // MARK: - Properties
    
    var arrowNode: ArrowLayerNode {
        didSet {
            updateFromNode()
        }
    }
    
    // 图层
    private let arrowLayer = CAShapeLayer()
    private let selectionBorder = CAShapeLayer()
    private var endpointHandleLayers: [CAShapeLayer] = []
    
    // 控制点配置
    private let handleSize: CGFloat = 12
    
    // 选中状态
    var isSelected: Bool = false {
        didSet {
            updateSelectionAppearance()
        }
    }
    
    // 当前拖动的控制点
    private var activeHandle: ArrowHandle?
    private var dragStartPoint: CGPoint = .zero
    private var initialNode: ArrowLayerNode?
    
    // 手势
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    
    // 回调
    var onNodeUpdated: ((ArrowLayerNode) -> Void)?
    var onSelected: ((UUID) -> Void)?
    var onOperationStart: ((ArrowLayerNode) -> Void)?
    var onOperationEnd: ((ArrowLayerNode, ArrowLayerNode) -> Void)?
    
    // MARK: - Initialization
    
    init(arrowNode: ArrowLayerNode) {
        self.arrowNode = arrowNode
        super.init(frame: arrowNode.bounds)
        setupViews()
        setupGestures()
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
        
        // 箭头图层
        arrowLayer.strokeColor = UIColor(Color.fromHex(arrowNode.color) ?? .black).cgColor
        arrowLayer.lineWidth = arrowNode.lineWidth
        arrowLayer.lineCap = .round
        arrowLayer.lineJoin = .round
        arrowLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(arrowLayer)
        
        // 选中边框
        selectionBorder.strokeColor = UIColor.systemBlue.cgColor
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.lineWidth = 1.5
        selectionBorder.lineDashPattern = [4, 4]
        selectionBorder.isHidden = true
        layer.addSublayer(selectionBorder)
        
        // 2个端点控制点
        for _ in 0..<2 {
            let handleLayer = CAShapeLayer()
            handleLayer.fillColor = UIColor.white.cgColor
            handleLayer.strokeColor = UIColor.systemBlue.cgColor
            handleLayer.lineWidth = 2
            handleLayer.isHidden = true
            layer.addSublayer(handleLayer)
            endpointHandleLayers.append(handleLayer)
        }
    }
    
    private func setupGestures() {
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
        
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(panGesture)
    }
    
    // MARK: - Node Sync
    
    func updateFromNode() {
        transform = .identity
        frame = arrowNode.bounds
        transform = CGAffineTransform(rotationAngle: arrowNode.rotation)
        updateArrowPath()
        updateSelectionAppearance()
    }
    
    private func updateArrowPath() {
        let path = UIBezierPath()
        let scale = arrowNode.scale
        let scaledBounds = bounds
        
        let originalCenter = arrowNode.center
        let originalStartOffset = CGPoint(
            x: arrowNode.startPoint.x - originalCenter.x,
            y: arrowNode.startPoint.y - originalCenter.y
        )
        let originalEndOffset = CGPoint(
            x: arrowNode.endPoint.x - originalCenter.x,
            y: arrowNode.endPoint.y - originalCenter.y
        )
        
        let localStart = CGPoint(
            x: scaledBounds.width / 2 + originalStartOffset.x * scale,
            y: scaledBounds.height / 2 + originalStartOffset.y * scale
        )
        let localEnd = CGPoint(
            x: scaledBounds.width / 2 + originalEndOffset.x * scale,
            y: scaledBounds.height / 2 + originalEndOffset.y * scale
        )
        
        path.move(to: localStart)
        path.addLine(to: localEnd)
        
        if arrowNode.hasArrowHead {
            let angle = atan2(localEnd.y - localStart.y, localEnd.x - localStart.x)
            
            let arrowLength: CGFloat = 20 * scale
            let arrowAngle: CGFloat = .pi / 6
            
            let arrowPoint1 = CGPoint(
                x: localEnd.x - arrowLength * cos(angle - arrowAngle),
                y: localEnd.y - arrowLength * sin(angle - arrowAngle)
            )
            
            let arrowPoint2 = CGPoint(
                x: localEnd.x - arrowLength * cos(angle + arrowAngle),
                y: localEnd.y - arrowLength * sin(angle + arrowAngle)
            )
            
            path.move(to: localEnd)
            path.addLine(to: arrowPoint1)
            
            path.move(to: localEnd)
            path.addLine(to: arrowPoint2)
        }
        
        arrowLayer.path = path.cgPath
    }
    
    private func syncToNode() {
        onNodeUpdated?(arrowNode)
    }
    
    // MARK: - Selection Appearance
    
    private func updateSelectionAppearance() {
        let showHandles = isSelected
        
        selectionBorder.isHidden = !showHandles
        endpointHandleLayers.forEach { $0.isHidden = !showHandles }
        
        guard showHandles else { return }
        
        // 更新选中边框
        let borderRect = bounds.insetBy(dx: -10, dy: -10)
        selectionBorder.path = UIBezierPath(rect: borderRect).cgPath
        
        // 更新端点控制点
        let endpoints: [ArrowHandle] = [.startPoint, .endPoint]
        for (index, endpoint) in endpoints.enumerated() {
            let position = endpoint.position(for: arrowNode, in: bounds)
            let handleRect = CGRect(
                x: position.x - handleSize / 2,
                y: position.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            endpointHandleLayers[index].path = UIBezierPath(ovalIn: handleRect).cgPath
        }
    }
    
    // MARK: - Hit Testing
    
    private func hitTestHandle(at point: CGPoint) -> ArrowHandle? {
        guard isSelected else { return nil }
        
        let hitRadius: CGFloat = handleSize + 10
        
        let endpoints: [ArrowHandle] = [.startPoint, .endPoint]
        for endpoint in endpoints {
            let endpointPos = endpoint.position(for: arrowNode, in: bounds)
            if distance(from: point, to: endpointPos) < hitRadius {
                return endpoint
            }
        }
        
        return nil
    }
    
    private func distance(from p1: CGPoint, to p2: CGPoint) -> CGFloat {
        sqrt(pow(p1.x - p2.x, 2) + pow(p1.y - p2.y, 2))
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let expandedBounds = bounds.insetBy(dx: -(handleSize + 20), dy: -(handleSize + 20))
        return expandedBounds.contains(point)
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onSelected?(arrowNode.id)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            initialNode = arrowNode
            onOperationStart?(arrowNode)
            
            activeHandle = hitTestHandle(at: location)
            dragStartPoint = gesture.location(in: superview)
            
        case .changed:
            let currentPoint = gesture.location(in: superview)
            
            if let handle = activeHandle {
                handleEndpointDrag(handle: handle, currentPoint: currentPoint)
            } else {
                handleMove(currentPoint: currentPoint)
            }
            
        case .ended, .cancelled:
            syncToNode()
            if let initial = initialNode {
                onOperationEnd?(initial, arrowNode)
            }
            activeHandle = nil
            initialNode = nil
            
        default:
            break
        }
    }
    
    // MARK: - Transform Operations
    
    private func handleMove(currentPoint: CGPoint) {
        let translation = CGPoint(
            x: currentPoint.x - dragStartPoint.x,
            y: currentPoint.y - dragStartPoint.y
        )
        
        dragStartPoint = currentPoint
        
        arrowNode = arrowNode.updated(
            startPoint: CGPoint(
                x: arrowNode.startPoint.x + translation.x,
                y: arrowNode.startPoint.y + translation.y
            ),
            endPoint: CGPoint(
                x: arrowNode.endPoint.x + translation.x,
                y: arrowNode.endPoint.y + translation.y
            )
        )
        
        updateFromNode()
    }
    
    private func handleEndpointDrag(handle: ArrowHandle, currentPoint: CGPoint) {
        // 将当前点从 superview 坐标系转换到画布内容坐标系
        // 注意：这里 currentPoint 已经是 superview 坐标系（画布内容坐标系）
        
        switch handle {
        case .startPoint:
            arrowNode = arrowNode.updated(startPoint: currentPoint)
        case .endPoint:
            arrowNode = arrowNode.updated(endPoint: currentPoint)
        }
        
        updateFromNode()
    }
    
    // MARK: - Public Methods
    
    func enableArrowGestures() {
        isUserInteractionEnabled = true
        panGesture.isEnabled = true
        tapGesture.isEnabled = true
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        updateArrowPath()
        if isSelected {
            updateSelectionAppearance()
        }
    }
}
