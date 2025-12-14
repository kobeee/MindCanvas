import UIKit
import SwiftUI

/// 可选择的箭头视图
/// 支持选择、拖拽、缩放和旋转的箭头对象
class SelectableArrowView: UIView {
    // MARK: - Properties
    
    /// 关联的箭头图层节点
    var arrowNode: ArrowLayerNode {
        didSet {
            updateFromNode()
        }
    }
    
    /// 箭头路径
    private let arrowLayer = CAShapeLayer()
    
    /// 选中状态
    var isSelected: Bool = false {
        didSet {
            updateSelectionAppearance()
        }
    }
    
    /// 选中边框
    private let selectionBorder = CAShapeLayer()
    
    /// 手势识别器
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    
    /// 节点更新回调
    var onNodeUpdated: ((ArrowLayerNode) -> Void)?
    
    /// 选中回调
    var onSelected: ((UUID) -> Void)?
    
    /// 操作开始回调（用于撤销）
    var onOperationStart: ((ArrowLayerNode) -> Void)?
    
    /// 操作结束回调（用于撤销）
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
        clipsToBounds = false // 关键：允许箭头超出边界显示

        // 设置箭头图层
        arrowLayer.strokeColor = UIColor(Color.fromHex(arrowNode.color) ?? .black).cgColor
        arrowLayer.lineWidth = arrowNode.lineWidth
        arrowLayer.lineCap = .round
        arrowLayer.lineJoin = .round
        arrowLayer.fillColor = UIColor.clear.cgColor
        layer.addSublayer(arrowLayer)
        
        // 设置选中边框
        selectionBorder.strokeColor = UIColor.systemBlue.cgColor
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.lineWidth = 2
        selectionBorder.lineDashPattern = [6, 3]
        selectionBorder.isHidden = true
        layer.addSublayer(selectionBorder)
    }
    
    private func setupGestures() {
        // 点击选中
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
        
        // 拖拽
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(panGesture)
        
        // 允许多个手势同时识别
        panGesture.delegate = self
    }
    
    // MARK: - Node Sync
    
    /// 从节点更新视图
    func updateFromNode() {
        frame = arrowNode.bounds
        updateArrowPath()
        updateSelectionAppearance()
    }
    
    /// 更新箭头路径
    private func updateArrowPath() {
        let path = UIBezierPath()
        
        // 转换坐标到视图本地坐标系
        let localStart = CGPoint(
            x: arrowNode.startPoint.x - arrowNode.bounds.minX,
            y: arrowNode.startPoint.y - arrowNode.bounds.minY
        )
        let localEnd = CGPoint(
            x: arrowNode.endPoint.x - arrowNode.bounds.minX,
            y: arrowNode.endPoint.y - arrowNode.bounds.minY
        )
        
        // 绘制箭头主线
        path.move(to: localStart)
        path.addLine(to: localEnd)
        
        // 计算箭头角度
        let angle = atan2(localEnd.y - localStart.y, localEnd.x - localStart.x)
        
        // 箭头大小
        let arrowLength: CGFloat = 20
        let arrowAngle: CGFloat = .pi / 6
        
        // 绘制箭头两侧
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
        
        arrowLayer.path = path.cgPath
    }
    
    /// 将当前状态同步回节点
    private func syncToNode() {
        onNodeUpdated?(arrowNode)
    }
    
    // MARK: - Gestures
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onSelected?(arrowNode.id)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            // 操作开始，保存初始状态
            onOperationStart?(arrowNode)
            
        case .changed:
            // 实时更新位置
            let translation = gesture.translation(in: superview)
            center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
            gesture.setTranslation(.zero, in: superview)
            
            // 更新箭头节点位置
            let offset = translation
            arrowNode = ArrowLayerNode(
                startPoint: CGPoint(x: arrowNode.startPoint.x + offset.x, y: arrowNode.startPoint.y + offset.y),
                endPoint: CGPoint(x: arrowNode.endPoint.x + offset.x, y: arrowNode.endPoint.y + offset.y),
                color: arrowNode.color,
                lineWidth: arrowNode.lineWidth,
                zIndex: arrowNode.zIndex
            )
            updateFromNode()
            onNodeUpdated?(arrowNode)
            
        case .ended:
            // 操作结束，记录最终状态
            syncToNode()
            onOperationEnd?(arrowNode, arrowNode)
            
        default:
            break
        }
    }
    
    // MARK: - Appearance

    private func updateSelectionAppearance() {
        selectionBorder.isHidden = !isSelected

        if isSelected {
            // 创建选中边框路径（使用本地坐标系，稍微扩大边界）
            let localBounds = bounds.insetBy(dx: -10, dy: -10)
            let path = UIBezierPath(rect: localBounds)
            selectionBorder.path = path.cgPath
        }
    }
    
    /// 确保箭头手势在选中模式下优先
    func enableArrowGestures() {
        isUserInteractionEnabled = true
        panGesture.isEnabled = true
        tapGesture.isEnabled = true
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        // 更新箭头和选中边框
        updateArrowPath()
        if isSelected {
            let localBounds = bounds.insetBy(dx: -10, dy: -10)
            let path = UIBezierPath(rect: localBounds)
            selectionBorder.path = path.cgPath
        }
    }

    // MARK: - Hit Testing

    /// 扩大点击区域，让细长的箭头更容易点击
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // 扩大点击区域 20 点
        let expandedBounds = bounds.insetBy(dx: -20, dy: -20)
        return expandedBounds.contains(point)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SelectableArrowView: UIGestureRecognizerDelegate {
    /// 确保箭头手势优先于其他手势
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 在选择模式下，所有箭头手势都应该可以开始
        return true
    }
    
    /// 防止其他手势识别器阻止箭头手势
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return false
    }
}