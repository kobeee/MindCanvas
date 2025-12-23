//
//  ControlHandle.swift
//  MindCanvas
//
//  Created by Elvis on 2025/12/23.
//

import UIKit

/// 控制点类型（通用）
enum ControlHandle: Int, CaseIterable {
    case topLeft = 0
    case topRight = 1
    case bottomRight = 2
    case bottomLeft = 3
    case rotation = 4
    
    /// 控制点相对于边界框的位置
    func position(in bounds: CGRect, rotationHandleOffset: CGFloat = 30) -> CGPoint {
        switch self {
        case .topLeft:
            return CGPoint(x: bounds.minX, y: bounds.minY)
        case .topRight:
            return CGPoint(x: bounds.maxX, y: bounds.minY)
        case .bottomRight:
            return CGPoint(x: bounds.maxX, y: bounds.maxY)
        case .bottomLeft:
            return CGPoint(x: bounds.minX, y: bounds.maxY)
        case .rotation:
            return CGPoint(x: bounds.midX, y: bounds.minY - rotationHandleOffset)
        }
    }
    
    /// 缩放时的锚点（对角点）
    var oppositeCorner: ControlHandle? {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomRight: return .topLeft
        case .bottomLeft: return .topRight
        case .rotation: return nil
        }
    }
}