import Foundation
import CoreGraphics
import Observation

/// 画布状态管理器
/// 负责管理工具模式、选中状态、Magic Frame 等
@Observable
class CanvasStateManager {
    // MARK: - 工具模式
    
    /// 当前工具模式
    var currentMode: CanvasToolMode = .objectMode
    
    /// 切换工具模式
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
    
    // MARK: - 绘图工具
    
    /// 当前绘图工具 (画笔/橡皮擦)
    var isUsingPen = true
    
    /// 切换绘图工具
    func toggleDrawingTool() {
        isUsingPen.toggle()
    }
    
    /// 设置为画笔
    func selectPen() {
        isUsingPen = true
    }
    
    /// 设置为橡皮擦
    func selectEraser() {
        isUsingPen = false
    }
    
    // MARK: - 状态重置
    
    /// 重置所有状态
    func reset() {
        currentMode = .objectMode
        selectedNodeID = nil
        isMagicFrameVisible = false
        isUsingPen = true
    }
}
