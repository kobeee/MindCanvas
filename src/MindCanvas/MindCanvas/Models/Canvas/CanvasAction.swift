import Foundation
import CoreGraphics
import PencilKit

/// 画布操作协议（Command Pattern）
/// 支持撤销/恢复的操作必须实现此协议
protocol CanvasAction {
    /// 执行操作
    func execute()
    
    /// 撤销操作
    func undo()
    
    /// 操作描述（用于调试和日志）
    var description: String { get }
}

// MARK: - 图层操作

/// 添加图层操作
struct AddLayerAction: CanvasAction {
    let layer: LayerNode
    weak var canvasView: NativeCanvasView?

    var description: String { "添加图层: \(layer.id)" }

    func execute() {
        canvasView?.addLayer(layer)
    }

    func undo() {
        canvasView?.removeLayer(id: layer.id, recordUndo: false)
    }
}

/// 移除图层操作
struct RemoveLayerAction: CanvasAction {
    let layer: LayerNode
    weak var canvasView: NativeCanvasView?

    var description: String { "移除图层: \(layer.id)" }

    func execute() {
        canvasView?.removeLayer(id: layer.id)
    }

    func undo() {
        canvasView?.addLayer(layer, recordUndo: false)
    }
}

/// 移动图层操作
struct MoveLayerAction: CanvasAction {
    let layerID: UUID
    let fromFrame: CGRect
    let toFrame: CGRect
    weak var canvasView: NativeCanvasView?
    
    var description: String { "移动图层: \(layerID)" }
    
    func execute() {
        guard var layer = canvasView?.getLayers().first(where: { $0.id == layerID }) else { return }
        layer.frame = toFrame
        canvasView?.updateLayer(layer)
    }
    
    func undo() {
        guard var layer = canvasView?.getLayers().first(where: { $0.id == layerID }) else { return }
        layer.frame = fromFrame
        canvasView?.updateLayer(layer)
    }
}

/// 缩放图层操作
struct ScaleLayerAction: CanvasAction {
    let layerID: UUID
    let fromFrame: CGRect
    let toFrame: CGRect
    weak var canvasView: NativeCanvasView?
    
    var description: String { "缩放图层: \(layerID)" }
    
    func execute() {
        guard var layer = canvasView?.getLayers().first(where: { $0.id == layerID }) else { return }
        layer.frame = toFrame
        canvasView?.updateLayer(layer)
    }
    
    func undo() {
        guard var layer = canvasView?.getLayers().first(where: { $0.id == layerID }) else { return }
        layer.frame = fromFrame
        canvasView?.updateLayer(layer)
    }
}

/// 旋转图层操作
struct RotateLayerAction: CanvasAction {
    let layerID: UUID
    let fromRotation: Double
    let toRotation: Double
    weak var canvasView: NativeCanvasView?
    
    var description: String { "旋转图层: \(layerID)" }
    
    func execute() {
        guard var layer = canvasView?.getLayers().first(where: { $0.id == layerID }) else { return }
        layer.rotation = toRotation
        canvasView?.updateLayer(layer)
    }
    
    func undo() {
        guard var layer = canvasView?.getLayers().first(where: { $0.id == layerID }) else { return }
        layer.rotation = fromRotation
        canvasView?.updateLayer(layer)
    }
}

/// 图层 Z-Index 操作
struct ZIndexLayerAction: CanvasAction {
    let layerID: UUID
    let fromZIndex: Int
    let toZIndex: Int
    weak var canvasView: NativeCanvasView?
    
    var description: String { "调整图层顺序: \(layerID)" }
    
    func execute() {
        guard var layer = canvasView?.getLayers().first(where: { $0.id == layerID }) else { return }
        layer.zIndex = toZIndex
        canvasView?.updateLayer(layer)
    }
    
    func undo() {
        guard var layer = canvasView?.getLayers().first(where: { $0.id == layerID }) else { return }
        layer.zIndex = fromZIndex
        canvasView?.updateLayer(layer)
    }
}

/// 锁定/解锁图层操作
struct LockLayerAction: CanvasAction {
    let layerID: UUID
    let wasLocked: Bool
    weak var canvasView: NativeCanvasView?
    
    var description: String { "锁定/解锁图层: \(layerID)" }
    
    func execute() {
        canvasView?.toggleLayerLock(id: layerID)
    }
    
    func undo() {
        canvasView?.toggleLayerLock(id: layerID)
    }
}

// MARK: - 绘图操作

/// 绘图操作（整体快照）
struct DrawingAction: CanvasAction {
    let fromDrawingData: Data?
    let toDrawingData: Data?
    weak var canvasView: NativeCanvasView?

    var description: String { "绘图操作(from=\(fromDrawingData?.count ?? 0), to=\(toDrawingData?.count ?? 0))" }

    func execute() {
        if let data = toDrawingData {
            canvasView?.loadDrawing(from: data)
        }
    }

    func undo() {
        if let data = fromDrawingData {
            canvasView?.loadDrawing(from: data)
        } else {
            canvasView?.loadDrawing(from: Data())
        }
    }
}

// MARK: - 批量操作

/// 清屏操作
struct ClearCanvasAction: CanvasAction {
    let previousLayers: [LayerNode]
    let previousArrows: [ArrowLayerNode]
    let previousShapes: [ShapeLayerNode]
    let previousRectangles: [RectangleLayerNode]
    let previousTexts: [TextLayerNode]
    let previousAnnotations: [AnnotationLayerNode]
    let previousDrawingData: Data?
    weak var canvasView: NativeCanvasView?
    
    var description: String { "清屏操作(图层:\(previousLayers.count), 箭头:\(previousArrows.count), 形状:\(previousShapes.count), 矩形:\(previousRectangles.count), 文字:\(previousTexts.count), 标注:\(previousAnnotations.count))" }
    
    func execute() {
        canvasView?.clearCanvas()
    }
    
    func undo() {
        // 恢复图层
        if !previousLayers.isEmpty {
            canvasView?.setLayers(previousLayers)
        }
        
        // 恢复箭头
        if !previousArrows.isEmpty {
            previousArrows.forEach { arrow in
                canvasView?.addArrow(arrow, recordUndo: false)
            }
        }
        
        // 恢复形状
        if !previousShapes.isEmpty {
            previousShapes.forEach { shape in
                canvasView?.addShape(shape, recordUndo: false)
            }
        }
        
        // 恢复矩形
        if !previousRectangles.isEmpty {
            previousRectangles.forEach { rectangle in
                canvasView?.addRectangle(rectangle, recordUndo: false)
            }
        }
        
        // 恢复文字
        if !previousTexts.isEmpty {
            previousTexts.forEach { text in
                canvasView?.addText(text, recordUndo: false)
            }
        }
        
        // 恢复标注
        if !previousAnnotations.isEmpty {
            previousAnnotations.forEach { annotation in
                canvasView?.addAnnotation(annotation, recordUndo: false)
            }
        }
        
        // 恢复绘图
        if let data = previousDrawingData {
            canvasView?.loadDrawing(from: data)
        }
    }
}

/// 复制图层操作
struct DuplicateLayerAction: CanvasAction {
    let originalLayerID: UUID
    let duplicatedLayer: LayerNode
    weak var canvasView: NativeCanvasView?

    var description: String { "复制图层: \(originalLayerID)" }

    func execute() {
        canvasView?.addLayer(duplicatedLayer, recordUndo: false)
    }

    func undo() {
        canvasView?.removeLayer(id: duplicatedLayer.id, recordUndo: false)
    }
}

// MARK: - 箭头操作

/// 添加箭头操作
struct AddArrowAction: CanvasAction {
    let arrow: ArrowLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "添加箭头: \(arrow.id)" }
    
    func execute() {
        canvasView?.addArrow(arrow, recordUndo: false)
    }
    
    func undo() {
        canvasView?.removeArrow(id: arrow.id)
    }
}

/// 移除箭头操作
struct RemoveArrowAction: CanvasAction {
    let arrow: ArrowLayerNode
    weak var canvasView: NativeCanvasView?

    var description: String { "移除箭头: \(arrow.id)" }

    func execute() {
        canvasView?.removeArrow(id: arrow.id)
    }

    func undo() {
        canvasView?.addArrow(arrow, recordUndo: false)
    }
}

/// 移动箭头操作
struct MoveArrowAction: CanvasAction {
    let arrowID: UUID
    let fromArrow: ArrowLayerNode
    let toArrow: ArrowLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "移动箭头: \(arrowID)" }
    
    func execute() {
        canvasView?.updateArrow(toArrow)
        
        // 更新箭头视图
        if let arrowView = canvasView?.arrowViews[arrowID] {
            arrowView.arrowNode = toArrow
            arrowView.updateFromNode()
        }
    }
    
    func undo() {
        canvasView?.updateArrow(fromArrow)
        
        // 更新箭头视图
        if let arrowView = canvasView?.arrowViews[arrowID] {
            arrowView.arrowNode = fromArrow
            arrowView.updateFromNode()
        }
    }
}

/// 修改箭头操作
struct ModifyArrowAction: CanvasAction {
    let arrowID: UUID
    let fromArrow: ArrowLayerNode
    let toArrow: ArrowLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "修改箭头: \(arrowID)" }
    
    func execute() {
        canvasView?.updateArrow(toArrow)
    }
    
    func undo() {
        canvasView?.updateArrow(fromArrow)
    }
}

// MARK: - 箭头缩放操作
class ScaleArrowAction: CanvasAction {
    let arrowID: UUID
    let fromArrow: ArrowLayerNode
    let toArrow: ArrowLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "缩放箭头: \(arrowID)" }
    
    init(arrowID: UUID, fromArrow: ArrowLayerNode, toArrow: ArrowLayerNode, canvasView: NativeCanvasView) {
        self.arrowID = arrowID
        self.fromArrow = fromArrow
        self.toArrow = toArrow
        self.canvasView = canvasView
    }
    
    func execute() {
        canvasView?.updateArrow(toArrow)
    }
    
    func undo() {
        canvasView?.updateArrow(fromArrow)
    }
}

// MARK: - 箭头旋转操作
class RotateArrowAction: CanvasAction {
    let arrowID: UUID
    let fromArrow: ArrowLayerNode
    let toArrow: ArrowLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "旋转箭头: \(arrowID)" }
    
    init(arrowID: UUID, fromArrow: ArrowLayerNode, toArrow: ArrowLayerNode, canvasView: NativeCanvasView) {
        self.arrowID = arrowID
        self.fromArrow = fromArrow
        self.toArrow = toArrow
        self.canvasView = canvasView
    }
    
    func execute() {
        canvasView?.updateArrow(toArrow)
    }
    
    func undo() {
        canvasView?.updateArrow(fromArrow)
    }
}

// MARK: - 形状操作

/// 添加形状操作
class AddShapeAction: CanvasAction {
    let shape: ShapeLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "添加形状: \(shape.id)" }
    
    init(shape: ShapeLayerNode, canvasView: NativeCanvasView) {
        self.shape = shape
        self.canvasView = canvasView
    }
    
    func execute() {
        canvasView?.addShape(shape, recordUndo: false)
    }
    
    func undo() {
        canvasView?.removeShape(id: shape.id)
    }
}

/// 移除形状操作
struct RemoveShapeAction: CanvasAction {
    let shape: ShapeLayerNode
    weak var canvasView: NativeCanvasView?

    var description: String { "移除形状: \(shape.id)" }

    func execute() {
        canvasView?.removeShape(id: shape.id)
    }

    func undo() {
        canvasView?.addShape(shape, recordUndo: false)
    }
}

/// 移动形状操作
class MoveShapeAction: CanvasAction {
    let shapeID: UUID
    let fromShape: ShapeLayerNode
    let toShape: ShapeLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "移动形状: \(shapeID)" }
    
    init(shapeID: UUID, fromShape: ShapeLayerNode, toShape: ShapeLayerNode, canvasView: NativeCanvasView) {
        self.shapeID = shapeID
        self.fromShape = fromShape
        self.toShape = toShape
        self.canvasView = canvasView
    }
    
    func execute() {
        canvasView?.updateShape(toShape)
    }
    
    func undo() {
        canvasView?.updateShape(fromShape)
    }
}

/// 缩放形状操作
class ScaleShapeAction: CanvasAction {
    let shapeID: UUID
    let fromShape: ShapeLayerNode
    let toShape: ShapeLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "缩放形状: \(shapeID)" }
    
    init(shapeID: UUID, fromShape: ShapeLayerNode, toShape: ShapeLayerNode, canvasView: NativeCanvasView) {
        self.shapeID = shapeID
        self.fromShape = fromShape
        self.toShape = toShape
        self.canvasView = canvasView
    }
    
    func execute() {
        canvasView?.updateShape(toShape)
    }
    
    func undo() {
        canvasView?.updateShape(fromShape)
    }
}

/// 旋转形状操作
class RotateShapeAction: CanvasAction {
    let shapeID: UUID
    let fromShape: ShapeLayerNode
    let toShape: ShapeLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "旋转形状: \(shapeID)" }
    
    init(shapeID: UUID, fromShape: ShapeLayerNode, toShape: ShapeLayerNode, canvasView: NativeCanvasView) {
        self.shapeID = shapeID
        self.fromShape = fromShape
        self.toShape = toShape
        self.canvasView = canvasView
    }
    
    func execute() {
        canvasView?.updateShape(toShape)
    }
    
    func undo() {
        canvasView?.updateShape(fromShape)
    }
}

// MARK: - 矩形操作

/// 添加矩形操作
struct AddRectangleAction: CanvasAction {
    let rectangle: RectangleLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "添加矩形: \(rectangle.id)" }
    
    func execute() {
        canvasView?.addRectangle(rectangle, recordUndo: false)
    }
    
    func undo() {
        canvasView?.removeRectangle(id: rectangle.id)
    }
}

/// 移除矩形操作
struct RemoveRectangleAction: CanvasAction {
    let rectangle: RectangleLayerNode
    weak var canvasView: NativeCanvasView?

    var description: String { "移除矩形: \(rectangle.id)" }

    func execute() {
        canvasView?.removeRectangle(id: rectangle.id)
    }

    func undo() {
        canvasView?.addRectangle(rectangle, recordUndo: false)
    }
}

/// 修改矩形操作
struct ModifyRectangleAction: CanvasAction {
    let rectangleID: UUID
    let fromRectangle: RectangleLayerNode
    let toRectangle: RectangleLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "修改矩形: \(rectangleID)" }
    
    func execute() {
        canvasView?.updateRectangle(toRectangle)
    }
    
    func undo() {
        canvasView?.updateRectangle(fromRectangle)
    }
}

// MARK: - 文字操作

/// 添加文字操作
/// 线程安全的文字添加操作，支持完整的撤销/恢复生命周期
struct AddTextAction: CanvasAction {
    let text: TextLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "添加文字: \(text.id) [\(text.text.prefix(20))]" }
    
    func execute() {
        guard let canvasView = canvasView else {
            print("⚠️ [AddTextAction] CanvasView is nil, cannot execute")
            return
        }
        
        // 验证文字节点有效性
        guard isValidTextNode(text) else {
            print("⚠️ [AddTextAction] Invalid text node: \(text.id)")
            return
        }
        
        canvasView.addText(text, recordUndo: false)
    }
    
    func undo() {
        guard let canvasView = canvasView else {
            print("⚠️ [AddTextAction] CanvasView is nil, cannot undo")
            return
        }
        
        canvasView.removeText(id: text.id)
    }
    
    /// 验证文字节点的有效性
    private func isValidTextNode(_ text: TextLayerNode) -> Bool {
        return !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               text.fontSize > 0 &&
               text.scale > 0 &&
               !text.color.isEmpty
    }
}

/// 移除文字操作
/// 安全的文字移除操作，支持恢复已删除的文字
struct RemoveTextAction: CanvasAction {
    let text: TextLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "移除文字: \(text.id) [\(text.text.prefix(20))]" }
    
    func execute() {
        guard let canvasView = canvasView else {
            print("⚠️ [RemoveTextAction] CanvasView is nil, cannot execute")
            return
        }
        
        canvasView.removeText(id: text.id)
    }
    
    func undo() {
        guard let canvasView = canvasView else {
            print("⚠️ [RemoveTextAction] CanvasView is nil, cannot undo")
            return
        }
        
        // 恢复时需要确保不重复记录撤销操作
        canvasView.addText(text, recordUndo: false)
    }
}

/// 修改文字操作
/// 支持文字内容、样式、位置等所有属性的修改撤销
struct ModifyTextAction: CanvasAction {
    let textID: UUID
    let fromText: TextLayerNode
    let toText: TextLayerNode
    weak var canvasView: NativeCanvasView?
    
    /// 检测哪些属性发生了变化，用于更精确的描述
    private var changedProperties: [String] {
        var properties: [String] = []
        
        if fromText.text != toText.text {
            properties.append("内容")
        }
        if fromText.fontSize != toText.fontSize {
            properties.append("字号")
        }
        if fromText.color != toText.color {
            properties.append("颜色")
        }
        if fromText.fontName != toText.fontName {
            properties.append("字体")
        }
        if fromText.position != toText.position {
            properties.append("位置")
        }
        if abs(fromText.rotation - toText.rotation) > 0.001 {
            properties.append("旋转")
        }
        if abs(fromText.scale - toText.scale) > 0.01 {
            properties.append("缩放")
        }
        
        return properties.isEmpty ? ["未知"] : properties
    }
    
    var description: String { 
        let changes = changedProperties.joined(separator: ",")
        return "修改文字: \(textID) [\(changes)]"
    }
    
    func execute() {
        guard let canvasView = canvasView else {
            print("⚠️ [ModifyTextAction] CanvasView is nil, cannot execute")
            return
        }
        
        // 验证目标文字节点的有效性
        guard isValidTextNode(toText) else {
            print("⚠️ [ModifyTextAction] Invalid target text node: \(textID)")
            return
        }
        
        canvasView.updateText(toText)
    }
    
    func undo() {
        guard let canvasView = canvasView else {
            print("⚠️ [ModifyTextAction] CanvasView is nil, cannot undo")
            return
        }
        
        canvasView.updateText(fromText)
    }
    
    /// 验证文字节点的有效性
    private func isValidTextNode(_ text: TextLayerNode) -> Bool {
        return !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               text.fontSize > 0 &&
               text.scale > 0 &&
               !text.color.isEmpty
    }
}

/// 移动文字操作
/// 专门处理文字位置移动的撤销操作
struct MoveTextAction: CanvasAction {
    let textID: UUID
    let fromText: TextLayerNode
    let toText: TextLayerNode
    weak var canvasView: NativeCanvasView?
    
    /// 计算移动距离
    private var movementDelta: CGPoint {
        CGPoint(
            x: toText.position.x - fromText.position.x,
            y: toText.position.y - fromText.position.y
        )
    }
    
    var description: String { 
        let delta = movementDelta
        return "移动文字: \(textID) [Δx: \(String(format: "%.1f", delta.x)), Δy: \(String(format: "%.1f", delta.y))]"
    }
    
    func execute() {
        guard let canvasView = canvasView else {
            print("⚠️ [MoveTextAction] CanvasView is nil, cannot execute")
            return
        }
        
        canvasView.updateText(toText)
    }
    
    func undo() {
        guard let canvasView = canvasView else {
            print("⚠️ [MoveTextAction] CanvasView is nil, cannot undo")
            return
        }
        
        canvasView.updateText(fromText)
    }
}

/// 缩放文字操作
/// 专门处理文字缩放操作的撤销，支持精确的缩放比例追踪
struct ScaleTextAction: CanvasAction {
    let textID: UUID
    let fromText: TextLayerNode
    let toText: TextLayerNode
    weak var canvasView: NativeCanvasView?
    
    /// 计算缩放比例变化
    private var scaleRatio: CGFloat {
        guard fromText.scale > 0 else { return 1.0 }
        return toText.scale / fromText.scale
    }
    
    var description: String { 
        return "缩放文字: \(textID) [\(String(format: "%.2f", scaleRatio))x]"
    }
    
    func execute() {
        guard let canvasView = canvasView else {
            print("⚠️ [ScaleTextAction] CanvasView is nil, cannot execute")
            return
        }
        
        // 验证缩放值的有效性
        guard toText.scale > 0 && toText.scale <= 10.0 else {
            print("⚠️ [ScaleTextAction] Invalid scale value: \(toText.scale)")
            return
        }
        
        canvasView.updateText(toText)
    }
    
    func undo() {
        guard let canvasView = canvasView else {
            print("⚠️ [ScaleTextAction] CanvasView is nil, cannot undo")
            return
        }
        
        canvasView.updateText(fromText)
    }
}

/// 旋转文字操作
/// 专门处理文字旋转操作的撤销，支持角度变化的精确追踪
struct RotateTextAction: CanvasAction {
    let textID: UUID
    let fromText: TextLayerNode
    let toText: TextLayerNode
    weak var canvasView: NativeCanvasView?
    
    /// 计算旋转角度变化（转换为度数）
    private var rotationDelta: CGFloat {
        let delta = toText.rotation - fromText.rotation
        return delta * 180.0 / CGFloat.pi
    }
    
    var description: String { 
        return "旋转文字: \(textID) [\(String(format: "%.1f", rotationDelta))°]"
    }
    
    func execute() {
        guard let canvasView = canvasView else {
            print("⚠️ [RotateTextAction] CanvasView is nil, cannot execute")
            return
        }
        
        canvasView.updateText(toText)
    }
    
    func undo() {
        guard let canvasView = canvasView else {
            print("⚠️ [RotateTextAction] CanvasView is nil, cannot undo")
            return
        }
        
        canvasView.updateText(fromText)
    }
}

// MARK: - 标注操作

/// 添加标注操作
struct AddAnnotationAction: CanvasAction {
    let annotation: AnnotationLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "添加标注: \(annotation.id)" }
    
    func execute() {
        canvasView?.addAnnotation(annotation, recordUndo: false)
    }
    
    func undo() {
        canvasView?.removeAnnotation(id: annotation.id)
    }
}

/// 移除标注操作
struct RemoveAnnotationAction: CanvasAction {
    let annotation: AnnotationLayerNode
    weak var canvasView: NativeCanvasView?

    var description: String { "移除标注: \(annotation.id)" }

    func execute() {
        canvasView?.removeAnnotation(id: annotation.id)
    }

    func undo() {
        canvasView?.addAnnotation(annotation, recordUndo: false)
    }
}

/// 修改标注操作
struct ModifyAnnotationAction: CanvasAction {
    let annotationID: UUID
    let fromAnnotation: AnnotationLayerNode
    let toAnnotation: AnnotationLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "修改标注: \(annotationID)" }
    
    func execute() {
        canvasView?.updateAnnotation(toAnnotation)
    }
    
    func undo() {
        canvasView?.updateAnnotation(fromAnnotation)
    }
}

// MARK: - 文字批量操作

/// 批量添加文字操作
/// 原子性地添加多个文字对象，要么全部成功要么全部失败
struct BatchAddTextsAction: CanvasAction {
    let texts: [TextLayerNode]
    weak var canvasView: NativeCanvasView?
    
    var description: String { "批量添加文字: \(texts.count)个" }
    
    func execute() {
        guard let canvasView = canvasView else {
            print("⚠️ [BatchAddTextsAction] CanvasView is nil, cannot execute")
            return
        }
        
        // 验证所有文字节点的有效性
        let validTexts = texts.filter { text in
            !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            text.fontSize > 0 &&
            text.scale > 0 &&
            !text.color.isEmpty
        }
        
        if validTexts.count != texts.count {
            print("⚠️ [BatchAddTextsAction] \(texts.count - validTexts.count) 个文字节点无效")
        }
        
        // 批量添加，不记录单独的撤销操作
        validTexts.forEach { text in
            canvasView.addText(text, recordUndo: false)
        }
    }
    
    func undo() {
        guard let canvasView = canvasView else {
            print("⚠️ [BatchAddTextsAction] CanvasView is nil, cannot undo")
            return
        }
        
        // 批量移除所有添加的文字
        texts.forEach { text in
            canvasView.removeText(id: text.id)
        }
    }
}

/// 批量删除文字操作
/// 原子性地删除多个文字对象
struct BatchRemoveTextsAction: CanvasAction {
    let texts: [TextLayerNode]
    weak var canvasView: NativeCanvasView?
    
    var description: String { "批量删除文字: \(texts.count)个" }
    
    func execute() {
        guard let canvasView = canvasView else {
            print("⚠️ [BatchRemoveTextsAction] CanvasView is nil, cannot execute")
            return
        }
        
        texts.forEach { text in
            canvasView.removeText(id: text.id)
        }
    }
    
    func undo() {
        guard let canvasView = canvasView else {
            print("⚠️ [BatchRemoveTextsAction] CanvasView is nil, cannot undo")
            return
        }
        
        // 批量恢复所有删除的文字
        texts.forEach { text in
            canvasView.addText(text, recordUndo: false)
        }
    }
}

/// 批量修改文字样式操作
/// 同时修改多个文字的样式属性（字体、颜色、字号等）
struct BatchModifyTextsStyleAction: CanvasAction {
    let textIDs: [UUID]
    let fromTexts: [TextLayerNode]
    let toTexts: [TextLayerNode]
    weak var canvasView: NativeCanvasView?
    
    init(textIDs: [UUID], fromTexts: [TextLayerNode], toTexts: [TextLayerNode], canvasView: NativeCanvasView) {
        self.textIDs = textIDs
        self.fromTexts = fromTexts
        self.toTexts = toTexts
        self.canvasView = canvasView
    }
    
    var description: String { "批量修改文字样式: \(textIDs.count)个" }
    
    func execute() {
        guard let canvasView = canvasView else {
            print("⚠️ [BatchModifyTextsStyleAction] CanvasView is nil, cannot execute")
            return
        }
        
        guard textIDs.count == fromTexts.count && fromTexts.count == toTexts.count else {
            print("⚠️ [BatchModifyTextsStyleAction] 数据不一致")
            return
        }
        
        toTexts.forEach { text in
            canvasView.updateText(text)
        }
    }
    
    func undo() {
        guard let canvasView = canvasView else {
            print("⚠️ [BatchModifyTextsStyleAction] CanvasView is nil, cannot undo")
            return
        }
        
        fromTexts.forEach { text in
            canvasView.updateText(text)
        }
    }
}

/// 文字图层排序操作
/// 调整多个文字图层的Z-Index顺序
struct ReorderTextsAction: CanvasAction {
    let textIDs: [UUID]
    let fromZIndexes: [Int]
    let toZIndexes: [Int]
    weak var canvasView: NativeCanvasView?
    
    init(textIDs: [UUID], fromZIndexes: [Int], toZIndexes: [Int], canvasView: NativeCanvasView) {
        self.textIDs = textIDs
        self.fromZIndexes = fromZIndexes
        self.toZIndexes = toZIndexes
        self.canvasView = canvasView
    }
    
    var description: String { "重排序文字图层: \(textIDs.count)个" }
    
    func execute() {
        guard let canvasView = canvasView else {
            print("⚠️ [ReorderTextsAction] CanvasView is nil, cannot execute")
            return
        }
        
        guard textIDs.count == fromZIndexes.count && fromZIndexes.count == toZIndexes.count else {
            print("⚠️ [ReorderTextsAction] 数据不一致")
            return
        }
        
        // 更新每个文字的Z-Index
        for (index, textID) in textIDs.enumerated() {
            guard var text = canvasView.getTextLayerManager().getText(id: textID) else { continue }
            text = text.updated(zIndex: toZIndexes[index])
            canvasView.updateText(text)
        }
    }
    
    func undo() {
        guard let canvasView = canvasView else {
            print("⚠️ [ReorderTextsAction] CanvasView is nil, cannot undo")
            return
        }
        
        // 恢复原始Z-Index
        for (index, textID) in textIDs.enumerated() {
            guard var text = canvasView.getTextLayerManager().getText(id: textID) else { continue }
            text = text.updated(zIndex: fromZIndexes[index])
            canvasView.updateText(text)
        }
    }
}

// MARK: - 复合操作

/// 复合操作（将多个操作打包为一个）
struct CompoundAction: CanvasAction {
    let actions: [any CanvasAction]
    let name: String
    
    var description: String { name }
    
    func execute() {
        actions.forEach { $0.execute() }
    }
    
    func undo() {
        actions.reversed().forEach { $0.undo() }
    }
}

// MARK: - 文字操作工具类

/// 文字操作工具类
/// 提供便捷的批量操作创建和执行方法
class TextActionHelper {
    
    /// 创建批量添加文字操作
    static func createBatchAddAction(texts: [TextLayerNode], canvasView: NativeCanvasView) -> BatchAddTextsAction {
        return BatchAddTextsAction(texts: texts, canvasView: canvasView)
    }
    
    /// 创建批量删除文字操作
    static func createBatchRemoveAction(texts: [TextLayerNode], canvasView: NativeCanvasView) -> BatchRemoveTextsAction {
        return BatchRemoveTextsAction(texts: texts, canvasView: canvasView)
    }
    
    /// 创建批量样式修改操作
    static func createBatchStyleModifyAction(
        textIDs: [UUID],
        fromTexts: [TextLayerNode],
        toTexts: [TextLayerNode],
        canvasView: NativeCanvasView
    ) -> BatchModifyTextsStyleAction {
        return BatchModifyTextsStyleAction(
            textIDs: textIDs,
            fromTexts: fromTexts,
            toTexts: toTexts,
            canvasView: canvasView
        )
    }
    
    /// 创建文字重排序操作
    static func createReorderAction(
        textIDs: [UUID],
        fromZIndexes: [Int],
        toZIndexes: [Int],
        canvasView: NativeCanvasView
    ) -> ReorderTextsAction {
        return ReorderTextsAction(
            textIDs: textIDs,
            fromZIndexes: fromZIndexes,
            toZIndexes: toZIndexes,
            canvasView: canvasView
        )
    }
    
    /// 创建复合操作（用于复杂的多步骤操作）
    static func createCompoundAction(actions: [any CanvasAction], name: String) -> CompoundAction {
        return CompoundAction(actions: actions, name: name)
    }
}

