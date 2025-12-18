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
        canvasView?.removeLayer(id: layer.id)
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
        canvasView?.addLayer(layer)
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
    let previousDrawingData: Data?
    weak var canvasView: NativeCanvasView?
    
    var description: String { "清屏操作" }
    
    func execute() {
        canvasView?.clearCanvas()
    }
    
    func undo() {
        // 恢复图层
        canvasView?.setLayers(previousLayers)
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
        canvasView?.addLayer(duplicatedLayer)
    }
    
    func undo() {
        canvasView?.removeLayer(id: duplicatedLayer.id)
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
        canvasView?.addArrow(arrow)
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
        canvasView?.addRectangle(rectangle)
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
/// TODO: 待文本工具完整实现后启用
struct AddTextAction: CanvasAction {
    let text: TextLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "添加文字: \(text.id)" }
    
    func execute() {
        // TODO: 实现文本添加逻辑
        // canvasView?.addText(text, recordUndo: false)
    }
    
    func undo() {
        // TODO: 实现文本移除逻辑
        // canvasView?.removeText(id: text.id)
    }
}

/// 移除文字操作
/// TODO: 待文本工具完整实现后启用
struct RemoveTextAction: CanvasAction {
    let text: TextLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "移除文字: \(text.id)" }
    
    func execute() {
        // TODO: 实现文本移除逻辑
        // canvasView?.removeText(id: text.id)
    }
    
    func undo() {
        // TODO: 实现文本添加逻辑
        // canvasView?.addText(text)
    }
}

/// 修改文字操作
/// TODO: 待文本工具完整实现后启用
struct ModifyTextAction: CanvasAction {
    let textID: UUID
    let fromText: TextLayerNode
    let toText: TextLayerNode
    weak var canvasView: NativeCanvasView?
    
    var description: String { "修改文字: \(textID)" }
    
    func execute() {
        // TODO: 实现文本更新逻辑
        // canvasView?.updateText(toText)
    }
    
    func undo() {
        // TODO: 实现文本更新逻辑
        // canvasView?.updateText(fromText)
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
        canvasView?.addAnnotation(annotation)
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

