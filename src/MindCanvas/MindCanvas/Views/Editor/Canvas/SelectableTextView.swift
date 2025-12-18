import UIKit

/// 可选择的文本视图（支持控制点交互）
/// 简化实现 - 当前版本仅支持基础的选择、移动、旋转功能
/// TODO: 后续版本添加缩放和双击编辑功能
class SelectableTextView: UIView {

    // MARK: - Properties

    var textNode: TextLayerNode {
        didSet {
            updateFromNode()
        }
    }

    // 文本图层
    private let textLayer = CATextLayer()

    // 选中边框
    private let selectionBorder = CAShapeLayer()

    // 选中状态
    var isSelected: Bool = false {
        didSet {
            updateSelectionAppearance()
        }
    }

    // 手势
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    // 初始状态
    private var initialCenter: CGPoint = .zero
    private var dragStartPoint: CGPoint = .zero

    // 回调
    var onNodeUpdated: ((TextLayerNode) -> Void)?
    var onSelected: ((UUID) -> Void)?

    // MARK: - Initialization

    init(textNode: TextLayerNode) {
        self.textNode = textNode
        let bounds = textNode.bounds
        super.init(frame: bounds)
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

        // 配置文本图层
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.alignmentMode = .center
        textLayer.isWrapped = true
        layer.addSublayer(textLayer)

        // 添加选中边框
        layer.addSublayer(selectionBorder)

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
    }

    // MARK: - Update Methods

    func updateFromNode() {
        transform = .identity

        // 更新文本图层
        textLayer.string = textNode.text

        let font = UIFont(name: textNode.fontName, size: textNode.fontSize * textNode.scale)
            ?? UIFont.systemFont(ofSize: textNode.fontSize * textNode.scale)
        textLayer.font = font.fontName as CFString
        textLayer.fontSize = font.pointSize
        textLayer.foregroundColor = UIColor_fromHex(textNode.color).cgColor

        // 计算边界
        let textBounds = textNode.bounds
        bounds = CGRect(origin: .zero, size: textBounds.size)
        center = textNode.position

        // 更新文本图层位置
        textLayer.frame = bounds

        // 应用旋转
        transform = CGAffineTransform(rotationAngle: textNode.rotation)

        updateSelectionAppearance()
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
        selectionBorder.isHidden = !isSelected

        guard isSelected else { return }

        // 更新选中边框
        selectionBorder.path = UIBezierPath(rect: bounds).cgPath
    }

    // MARK: - Gesture Handlers

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onSelected?(textNode.id)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            initialCenter = center
            dragStartPoint = gesture.location(in: superview)

        case .changed:
            let currentPoint = gesture.location(in: superview)
            let dx = currentPoint.x - dragStartPoint.x
            let dy = currentPoint.y - dragStartPoint.y
            center = CGPoint(x: initialCenter.x + dx, y: initialCenter.y + dy)

        case .ended, .cancelled:
            syncToNode()

        default:
            break
        }
    }

    // MARK: - Helper Methods

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

// MARK: - UIGestureRecognizerDelegate

extension SelectableTextView: UIGestureRecognizerDelegate {}
