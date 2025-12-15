import UIKit
import SwiftUI

/// 可选择的通用形状视图
/// 支持选择、拖拽、缩放和旋转
class SelectableShapeView: UIView {

    // MARK: - Properties

    var shapeNode: ShapeLayerNode {
        didSet {
            updateFromNode()
        }
    }

    private let shapeLayer = CAShapeLayer()
    private let selectionBorder = CAShapeLayer()

    var isSelected: Bool = false {
        didSet {
            updateSelectionAppearance()
        }
    }

    // 手势识别器
    private var tapGesture: UITapGestureRecognizer!
    private var panGesture: UIPanGestureRecognizer!
    private var pinchGesture: UIPinchGestureRecognizer!
    private var rotateGesture: UIRotationGestureRecognizer!

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
        backgroundColor = .clear
        clipsToBounds = false

        // 形状图层
        shapeLayer.fillColor = shapeNode.isFilled ? UIColor(Color.fromHex(shapeNode.color) ?? .black).cgColor : UIColor.clear.cgColor
        shapeLayer.strokeColor = UIColor(Color.fromHex(shapeNode.color) ?? .black).cgColor
        shapeLayer.lineWidth = shapeNode.lineWidth
        layer.addSublayer(shapeLayer)

        // 选中边框
        selectionBorder.strokeColor = UIColor.systemBlue.cgColor
        selectionBorder.fillColor = UIColor.clear.cgColor
        selectionBorder.lineWidth = 2
        selectionBorder.lineDashPattern = [6, 3]
        selectionBorder.isHidden = true
        layer.addSublayer(selectionBorder)
    }

    private func setupGestures() {
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(panGesture)

        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        addGestureRecognizer(pinchGesture)

        rotateGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        addGestureRecognizer(rotateGesture)

        panGesture.delegate = self
        pinchGesture.delegate = self
        rotateGesture.delegate = self
    }

    // MARK: - Node Sync

    func updateFromNode() {
        frame = shapeNode.frame
        transform = CGAffineTransform(rotationAngle: shapeNode.rotation)
        updateShapePath()
        updateSelectionAppearance()
    }

    private func updateShapePath() {
        let rect = bounds
        let path: UIBezierPath

        switch shapeNode.shapeType {
        case .rectangle:
            path = UIBezierPath(roundedRect: rect, cornerRadius: 4)

        case .circle:
            let diameter = min(rect.width, rect.height)
            let circleRect = CGRect(
                x: (rect.width - diameter) / 2,
                y: (rect.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            path = UIBezierPath(ovalIn: circleRect)

        case .triangle:
            path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: 0, y: rect.maxY))
            path.close()

        case .diamond:
            path = UIBezierPath()
            path.move(to: CGPoint(x: rect.midX, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: 0, y: rect.midY))
            path.close()

        case .star:
            path = createStarPath(in: rect, points: 5)

        case .hexagon:
            path = createPolygonPath(in: rect, sides: 6)
        }

        shapeLayer.path = path.cgPath
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onSelected?(shapeNode.id)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            onOperationStart?(shapeNode)
        case .changed:
            let translation = gesture.translation(in: superview)
            center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
            gesture.setTranslation(.zero, in: superview)
        case .ended:
            syncToNode()
            onOperationEnd?(shapeNode, shapeNode)
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            onOperationStart?(shapeNode)
        case .changed:
            transform = transform.scaledBy(x: gesture.scale, y: gesture.scale)
            gesture.scale = 1.0
        case .ended:
            // 更新 frame 尺寸
            let newWidth = bounds.width * abs(transform.a)
            let newHeight = bounds.height * abs(transform.d)
            bounds.size = CGSize(width: newWidth, height: newHeight)
            transform = CGAffineTransform(rotationAngle: shapeNode.rotation)
            syncToNode()
            onOperationEnd?(shapeNode, shapeNode)
        default:
            break
        }
    }

    @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            onOperationStart?(shapeNode)
        case .changed:
            transform = transform.rotated(by: gesture.rotation)
            gesture.rotation = 0
        case .ended:
            syncToNode()
            onOperationEnd?(shapeNode, shapeNode)
        default:
            break
        }
    }

    private func syncToNode() {
        shapeNode = shapeNode.updated(
            frame: frame,
            rotation: atan2(transform.b, transform.a)
        )
        onNodeUpdated?(shapeNode)
    }

    // MARK: - Appearance

    private func updateSelectionAppearance() {
        selectionBorder.isHidden = !isSelected
        if isSelected {
            let borderRect = bounds.insetBy(dx: -8, dy: -8)
            selectionBorder.path = UIBezierPath(rect: borderRect).cgPath
        }
    }

    func enableShapeGestures() {
        isUserInteractionEnabled = true
        panGesture.isEnabled = true
        tapGesture.isEnabled = true
        pinchGesture.isEnabled = true
        rotateGesture.isEnabled = true
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
            let borderRect = bounds.insetBy(dx: -8, dy: -8)
            selectionBorder.path = UIBezierPath(rect: borderRect).cgPath
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension SelectableShapeView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // 允许缩放和旋转同时进行
        if (gestureRecognizer == pinchGesture && otherGestureRecognizer == rotateGesture) ||
           (gestureRecognizer == rotateGesture && otherGestureRecognizer == pinchGesture) {
            return true
        }
        return false
    }
}