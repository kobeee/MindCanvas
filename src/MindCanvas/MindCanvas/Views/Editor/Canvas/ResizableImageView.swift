import UIKit

/// 可调整大小和旋转的图片视图
/// 代表画布上的一个可操控图片对象
class ResizableImageView: UIView {
    // MARK: - Properties
    
    /// 关联的图层节点
    var node: LayerNode {
        didSet {
            updateFromNode()
        }
    }
    
    /// 图片视图
    private let imageView: UIImageView = {
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.clipsToBounds = true
        return view
    }()
    
    /// 选中状态
    var isSelected: Bool = false {
        didSet {
            updateSelectionAppearance()
        }
    }
    
    /// 选中边框
    private let selectionBorder: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.strokeColor = UIColor.systemBlue.cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = 3
        layer.lineDashPattern = [6, 3]
        layer.isHidden = true
        return layer
    }()
    
    /// 手势识别器
    private var panGesture: UIPanGestureRecognizer!
    private var pinchGesture: UIPinchGestureRecognizer!
    private var rotateGesture: UIRotationGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    
    /// 节点更新回调
    var onNodeUpdated: ((LayerNode) -> Void)?
    
    /// 选中回调
    var onSelected: ((UUID) -> Void)?
    
    // MARK: - Initialization
    
    init(node: LayerNode) {
        self.node = node
        super.init(frame: node.frame)
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
        backgroundColor = .clear
        
        // 添加图片视图
        addSubview(imageView)
        imageView.frame = bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // 添加选中边框
        layer.addSublayer(selectionBorder)
        
        // 锁定标识 (小锁图标)
        if node.isLocked {
            addLockIndicator()
        }
    }
    
    private func setupGestures() {
        // 点击选中
        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
        
        // 拖拽
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        addGestureRecognizer(panGesture)
        
        // 缩放
        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        addGestureRecognizer(pinchGesture)
        
        // 旋转
        rotateGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        addGestureRecognizer(rotateGesture)
        
        // 允许手势同时识别
        panGesture.delegate = self
        pinchGesture.delegate = self
        rotateGesture.delegate = self
    }
    
    // MARK: - Image Loading
    
    private func loadImage() {
        guard let urlString = node.url else { return }
        
        // 本地图片
        if let url = URL(string: urlString), url.isFileURL {
            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                imageView.image = image
            }
        }
        // 远程图片 (简单实现，生产环境应使用 Kingfisher 等库)
        else if let url = URL(string: urlString) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    self?.imageView.image = image
                }
            }.resume()
        }
    }
    
    // MARK: - Node Sync
    
    /// 从节点更新视图
    private func updateFromNode() {
        frame = node.frame
        transform = CGAffineTransform(rotationAngle: node.rotation)
        alpha = node.opacity
        isUserInteractionEnabled = !node.isLocked
        
        updateSelectionAppearance()
    }
    
    /// 将当前状态同步回节点
    private func syncToNode() {
        node.frame = frame
        node.rotation = atan2(transform.b, transform.a)
        node.opacity = Double(alpha)
        
        onNodeUpdated?(node)
    }
    
    // MARK: - Gestures
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        onSelected?(node.id)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !node.isLocked else { return }
        
        let translation = gesture.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)
        
        if gesture.state == .ended {
            syncToNode()
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard !node.isLocked else { return }
        
        let scale = gesture.scale
        transform = transform.scaledBy(x: scale, y: scale)
        gesture.scale = 1.0
        
        if gesture.state == .ended {
            // 更新 frame 以反映新尺寸
            let newWidth = bounds.width * transform.a
            let newHeight = bounds.height * transform.d
            bounds.size = CGSize(width: newWidth, height: newHeight)
            transform = CGAffineTransform(rotationAngle: node.rotation)
            syncToNode()
        }
    }
    
    @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        guard !node.isLocked else { return }
        
        transform = transform.rotated(by: gesture.rotation)
        gesture.rotation = 0
        
        if gesture.state == .ended {
            syncToNode()
        }
    }
    
    // MARK: - Appearance
    
    private func updateSelectionAppearance() {
        selectionBorder.isHidden = !isSelected
        
        if isSelected {
            let path = UIBezierPath(roundedRect: bounds, cornerRadius: 8)
            selectionBorder.path = path.cgPath
        }
        
        // 更新锁定标识
        viewWithTag(999)?.removeFromSuperview()
        if node.isLocked {
            addLockIndicator()
        }
    }
    
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
        
        // 更新选中边框路径
        if isSelected {
            let path = UIBezierPath(roundedRect: bounds, cornerRadius: 8)
            selectionBorder.path = path.cgPath
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension ResizableImageView: UIGestureRecognizerDelegate {
    /// 允许多个手势同时识别
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // 缩放和旋转可以同时进行
        if (gestureRecognizer == pinchGesture && otherGestureRecognizer == rotateGesture) ||
           (gestureRecognizer == rotateGesture && otherGestureRecognizer == pinchGesture) {
            return true
        }
        return false
    }
}

