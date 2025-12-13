import Foundation
import CoreGraphics
import Observation
import Combine

/// 画布状态管理器
/// 负责管理工具状态、选中状态、Magic Frame、撤销/恢复等
@Observable
class CanvasStateManager {
    // MARK: - Properties
    
    /// 用于监听通知的订阅集合
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - 工具状态
    
    /// 当前选中的工具
    var currentTool: CanvasTool = .select
    
    /// 初始化
    init() {
        setupNotifications()
    }
    
    /// 设置通知监听
    private func setupNotifications() {
        // 监听画布操作记录通知
        NotificationCenter.default.publisher(for: .canvasActionRecorded)
            .sink { [weak self] notification in
                if let action = notification.object as? any CanvasAction {
                    print("📝 接收到撤销操作：\(action.description)")
                    self?.recordAction(action)
                }
            }
            .store(in: &cancellables)
    }
    
    /// 切换工具
    func selectTool(_ tool: CanvasTool) {
        currentTool = tool
    }
    
    // MARK: - 兼容性属性（向后兼容旧代码）
    
    /// 当前工具模式（兼容旧代码，将被移除）
    @available(*, deprecated, message: "使用 currentTool 代替")
    var currentMode: CanvasToolMode {
        get {
            switch currentTool {
            case .select, .pan, .image:
                return .objectMode
            case .pen, .eraser, .arrow, .text, .annotation, .rectangle:
                return .drawingMode
            }
        }
        set {
            switch newValue {
            case .objectMode:
                currentTool = .select
            case .drawingMode:
                currentTool = .pen
            }
        }
    }
    
    /// 切换工具模式（兼容旧代码）
    @available(*, deprecated, message: "使用 selectTool(_:) 代替")
    func switchMode(to mode: CanvasToolMode) {
        currentMode = mode
    }
    
    // MARK: - 选中状态
    
    /// 当前选中的节点 ID
    var selectedNodeID: UUID?
    
    /// 是否有选中的节点
    var hasSelection: Bool {
        selectedNodeID != nil
    }
    
    /// 选中节点
    func selectNode(_ id: UUID?) {
        selectedNodeID = id
    }
    
    /// 取消选中
    func clearSelection() {
        selectedNodeID = nil
    }
    
    // MARK: - Magic Frame
    
    /// Magic Frame 是否可见
    var isMagicFrameVisible = false
    
    /// Magic Frame 的位置和尺寸
    var magicFrame: CGRect = CGRect(
        origin: CGPoint(x: 200, y: 200),
        size: CGSize(width: 400, height: 300)
    )
    
    /// 显示 Magic Frame
    func showMagicFrame() {
        isMagicFrameVisible = true
    }
    
    /// 隐藏 Magic Frame
    func hideMagicFrame() {
        isMagicFrameVisible = false
    }
    
    /// 切换 Magic Frame 显示状态
    func toggleMagicFrame() {
        isMagicFrameVisible.toggle()
    }
    
    /// 重置 Magic Frame 到默认位置
    func resetMagicFrame(canvasSize: CGSize) {
        let width: CGFloat = 400
        let height: CGFloat = 300
        magicFrame = CGRect(
            x: (canvasSize.width - width) / 2,
            y: (canvasSize.height - height) / 2,
            width: width,
            height: height
        )
    }

    // MARK: - 视口缩放

    /// 当前画布缩放比例（由 NativeCanvasView 回传）
    var zoomScale: CGFloat = 1.0
    
    // MARK: - 绘图工具（兼容旧代码，将被移除）
    
    /// 当前绘图工具 (画笔/橡皮擦)
    @available(*, deprecated, message: "使用 currentTool == .pen / .eraser 代替")
    var isUsingPen: Bool {
        get { currentTool == .pen }
        set { currentTool = newValue ? .pen : .eraser }
    }
    
    /// 切换绘图工具
    @available(*, deprecated, message: "在 .pen 和 .eraser 之间切换 currentTool")
    func toggleDrawingTool() {
        currentTool = (currentTool == .pen) ? .eraser : .pen
    }
    
    /// 设置为画笔
    @available(*, deprecated, message: "使用 selectTool(.pen) 代替")
    func selectPen() {
        currentTool = .pen
    }
    
    /// 设置为橡皮擦
    @available(*, deprecated, message: "使用 selectTool(.eraser) 代替")
    func selectEraser() {
        currentTool = .eraser
    }
    
    // MARK: - 撤销/恢复系统
    
    /// 撤销栈
    private var undoStack: [any CanvasAction] = []
    
    /// 恢复栈
    private var redoStack: [any CanvasAction] = []
    
    /// 最大撤销步数
    private let maxUndoSteps = 50
    
    /// 是否可撤销
    var canUndo: Bool { !undoStack.isEmpty }
    
    /// 是否可恢复
    var canRedo: Bool { !redoStack.isEmpty }
    
    /// 记录操作（用于撤销）
    func recordAction(_ action: any CanvasAction) {
        undoStack.append(action)
        // 清空恢复栈（新操作后无法恢复之前撤销的内容）
        let redoCount = redoStack.count
        redoStack.removeAll()
        // 限制撤销栈大小
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
        print("[DEBUG] recordAction: \(action.description), undoStack=\(undoStack.count), cleared redoStack(\(redoCount))")
    }

    /// 撤销
    func undo() {
        guard let action = undoStack.popLast() else {
            print("[DEBUG] undo: failed (empty stack)")
            return
        }
        print("[DEBUG] undo: \(action.description), undoStack=\(undoStack.count)")
        action.undo()
        redoStack.append(action)
        print("[DEBUG] undo: done, redoStack=\(redoStack.count)")
    }

    /// 恢复
    func redo() {
        guard let action = redoStack.popLast() else {
            print("[DEBUG] redo: failed (empty stack)")
            return
        }
        print("[DEBUG] redo: \(action.description), redoStack=\(redoStack.count)")
        action.execute()
        undoStack.append(action)
        print("[DEBUG] redo: done, undoStack=\(undoStack.count)")
    }
    
    /// 清空撤销/恢复栈
    func clearUndoRedoStacks() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
    
    // MARK: - 画布操作
    
    /// 清屏回调（由外部设置）
    var onClearCanvas: (() -> Void)?
    
    /// 复制选中对象回调（由外部设置）
    var onDuplicateSelected: (() -> Void)?
    
    /// 清屏
    func clearCanvas() {
        onClearCanvas?()
    }
    
    /// 复制选中对象
    func duplicateSelected() {
        guard hasSelection else { return }
        onDuplicateSelected?()
    }
    
    // MARK: - 状态重置
    
    /// 重置所有状态
    func reset() {
        currentTool = .select
        selectedNodeID = nil
        isMagicFrameVisible = false
        zoomScale = 1.0
        clearUndoRedoStacks()
    }
    
    // MARK: - 箭头工具
    
    /// 箭头颜色
    var arrowColor: String = "#007AFF"
    
    /// 箭头线宽
    var arrowLineWidth: CGFloat = 3
    
    /// 设置箭头颜色
    func setArrowColor(_ color: String) {
        arrowColor = color
    }
    
    /// 设置箭头线宽
    func setArrowLineWidth(_ width: CGFloat) {
        arrowLineWidth = width
    }
    
    /// 删除所有箭头（支持撤销）
    func clearAllArrows() {
        // TODO: 实现删除所有箭头的撤销支持
    }
    
    // MARK: - 矩形工具
    
    /// 矩形颜色
    var rectangleColor: String = "#007AFF"
    
    /// 矩形线宽
    var rectangleLineWidth: CGFloat = 3
    
    /// 矩形是否填充
    var rectangleIsFilled: Bool = false
    
    /// 设置矩形颜色
    func setRectangleColor(_ color: String) {
        rectangleColor = color
    }
    
    /// 设置矩形线宽
    func setRectangleLineWidth(_ width: CGFloat) {
        rectangleLineWidth = width
    }
    
    /// 设置矩形是否填充
    func setRectangleIsFilled(_ filled: Bool) {
        rectangleIsFilled = filled
    }
    
    /// 删除所有矩形（支持撤销）
    func clearAllRectangles() {
        // TODO: 实现删除所有矩形的撤销支持
    }
    
    // MARK: - 文字工具
    
    /// 文字颜色
    var textColor: String = "#000000"
    
    /// 文字大小
    var textFontSize: CGFloat = 16
    
    /// 文字字体
    var textFontName: String? = nil
    
    /// 设置文字颜色
    func setTextColor(_ color: String) {
        textColor = color
    }
    
    /// 设置文字大小
    func setTextFontSize(_ size: CGFloat) {
        textFontSize = size
    }
    
    /// 设置文字字体
    func setTextFontName(_ name: String?) {
        textFontName = name
    }
    
    /// 删除所有文字（支持撤销）
    func clearAllTexts() {
        // TODO: 实现删除所有文字的撤销支持
    }
    
    // MARK: - 标注工具
    
    /// 标注颜色
    var annotationColor: String = "#007AFF"
    
    /// 标注线宽
    var annotationLineWidth: CGFloat = 2
    
    /// 标注文字大小
    var annotationFontSize: CGFloat = 14
    
    /// 设置标注颜色
    func setAnnotationColor(_ color: String) {
        annotationColor = color
    }
    
    /// 设置标注线宽
    func setAnnotationLineWidth(_ width: CGFloat) {
        annotationLineWidth = width
    }
    
    /// 设置标注文字大小
    func setAnnotationFontSize(_ size: CGFloat) {
        annotationFontSize = size
    }
    
    /// 删除所有标注（支持撤销）
    func clearAllAnnotations() {
        // TODO: 实现删除所有标注的撤销支持
    }
}
