import Foundation

/// 通知扩展
extension Notification.Name {
    /// 画布操作记录通知
    static let canvasActionRecorded = Notification.Name("CanvasActionRecorded")
    
    /// CanvasStateManager中选中状态变化通知
    static let selectionChangedInStateManager = Notification.Name("SelectionChangedInStateManager")
}