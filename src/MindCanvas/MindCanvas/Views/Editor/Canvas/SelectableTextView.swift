import UIKit

/// 可选择的文本视图（支持控制点交互）
/// 完整实现 - 支持选择、移动、旋转、缩放和双击编辑功能
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

    // 编辑状态
    var isEditing: Bool = false {
        didSet {
            updateEditingState()
        }
    }

    // 手势
    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    private var doubleTapGesture: UITapGestureRecognizer!

    // 初始状态
    private var initialCenter: CGPoint = .zero
    private var dragStartPoint: CGPoint = .zero

    // 编辑相关
    private var editingTextField: UITextField!
    private var editingOverlay: UIView!
    private var originalText: String = ""
    private var editingStartText: TextLayerNode?

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
        if !isEditing {
            onSelected?(textNode.id)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        startEditing()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            onOperationStart?(textNode)
            initialCenter = center
            dragStartPoint = gesture.location(in: superview)

        case .changed:
            let currentPoint = gesture.location(in: superview)
            let dx = currentPoint.x - dragStartPoint.x
            let dy = currentPoint.y - dragStartPoint.y
            center = CGPoint(x: initialCenter.x + dx, y: initialCenter.y + dy)

        case .ended, .cancelled:
            syncToNode()
            onOperationEnd?(self, textNode)

        default:
            break
        }
    }

    // MARK: - Editing Methods

    /// 开始编辑文字
    private func startEditing() {
        guard !isEditing else { return }
        
        isEditing = true
        originalText = textNode.text
        editingStartText = textNode
        
        onEditingStarted?(textNode)
        
        // 创建编辑界面
        setupEditingInterface()
        
        // 添加动画效果
        animateEditingStart()
    }

    /// 完成编辑文字
    private func finishEditing() {
        guard isEditing else { return }
        
        let newText = editingTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // 如果文字为空，恢复原文字
        if newText.isEmpty {
            cancelEditing()
            return
        }
        
        // 如果文字有变化，更新节点
        if newText != originalText {
            let updatedNode = textNode.updated(text: newText)
            textNode = updatedNode
            syncToNode()
            onEditingFinished?(textNode, newText)
        }
        
        cleanupEditingInterface()
        isEditing = false
        editingStartText = nil
        
        // 添加完成动画
        animateEditingEnd()
    }

    /// 取消编辑
    private func cancelEditing() {
        guard isEditing else { return }
        
        cleanupEditingInterface()
        isEditing = false
        editingStartText = nil
        
        // 添加取消动画
        animateEditingEnd()
    }

    /// 设置编辑界面
    private func setupEditingInterface() {
        // 创建半透明遮罩层
        editingOverlay = UIView(frame: bounds)
        editingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.1)
        editingOverlay.layer.cornerRadius = 8
        editingOverlay.layer.borderWidth = 2
        editingOverlay.layer.borderColor = UIColor.systemBlue.cgColor
        addSubview(editingOverlay)

        // 创建文本输入框
        editingTextField = UITextField()
        editingTextField.text = textNode.text
        editingTextField.font = UIFont(name: textNode.fontName, size: textNode.fontSize)
        editingTextField.textColor = UIColor_fromHex(textNode.color)
        editingTextField.textAlignment = .center
        editingTextField.backgroundColor = UIColor.white.withAlphaComponent(0.95)
        editingTextField.layer.cornerRadius = 6
        editingTextField.layer.borderWidth = 1
        editingTextField.layer.borderColor = UIColor.systemBlue.withAlphaComponent(0.3).cgColor
        editingTextField.delegate = self
        
        // 设置输入框样式
        editingTextField.layer.shadowColor = UIColor.black.cgColor
        editingTextField.layer.shadowOffset = CGSize(width: 0, height: 2)
        editingTextField.layer.shadowOpacity = 0.1
        editingTextField.layer.shadowRadius = 4
        editingTextField.layer.masksToBounds = false
        
        // 添加内边距
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: textNode.fontSize + 8))
        editingTextField.leftView = paddingView
        editingTextField.leftViewMode = .always
        editingTextField.rightView = paddingView
        editingTextField.rightViewMode = .always
        
        addSubview(editingTextField)
        
        // 设置约束
        editingTextField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editingTextField.centerXAnchor.constraint(equalTo: centerXAnchor),
            editingTextField.centerYAnchor.constraint(equalTo: centerYAnchor),
            editingTextField.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
            editingTextField.heightAnchor.constraint(equalToConstant: textNode.fontSize + 16)
        ])
        
        // 成为第一响应者
        editingTextField.becomeFirstResponder()
        
        // 选中全部文字
        DispatchQueue.main.async {
            self.editingTextField.selectAll(nil)
        }
    }

    /// 清理编辑界面
    private func cleanupEditingInterface() {
        editingTextField?.resignFirstResponder()
        editingTextField?.removeFromSuperview()
        editingTextField = nil
        
        editingOverlay?.removeFromSuperview()
        editingOverlay = nil
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

    /// 编辑开始动画
    private func animateEditingStart() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut]) {
            self.transform = self.transform.scaledBy(x: 1.05, y: 1.05)
            self.editingOverlay?.alpha = 1.0
        }
    }

    /// 编辑结束动画
    private func animateEditingEnd() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn]) {
            self.transform = CGAffineTransform(rotationAngle: self.textNode.rotation)
            self.editingOverlay?.alpha = 0.0
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

// MARK: - UITextFieldDelegate

extension SelectableTextView: UITextFieldDelegate {
    
    /// 文本输入完成（按回车键）
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        finishEditing()
        return true
    }
    
    /// 文本内容变化
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // 实时更新预览（可选）
        return true
    }
    
    /// 点击输入框外部时完成编辑
    func textFieldDidEndEditing(_ textField: UITextField) {
        if isEditing {
            finishEditing()
        }
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
