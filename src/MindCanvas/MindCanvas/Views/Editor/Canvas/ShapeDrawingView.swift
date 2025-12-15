import SwiftUI

/// 形状绘制预览视图
struct ShapeDrawingView: View {
    let rect: CGRect
    let shapeType: ShapeType
    let color: Color
    let lineWidth: CGFloat
    let isFilled: Bool
    
    var body: some View {
        Path { path in
            switch shapeType {
            case .rectangle:
                path.addRect(rect)
                
            case .circle:
                let diameter = min(rect.width, rect.height)
                let circleRect = CGRect(
                    x: rect.midX - diameter/2,
                    y: rect.midY - diameter/2,
                    width: diameter,
                    height: diameter
                )
                path.addEllipse(in: circleRect)
                
            case .triangle:
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.closeSubpath()
                
            case .diamond:
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                path.closeSubpath()
                
            case .star:
                createStarPath(in: rect, points: 5, path: &path)
                
            case .hexagon:
                createPolygonPath(in: rect, sides: 6, path: &path)
            }
        }
        .fill(isFilled ? color : Color.clear)
        .overlay(
            Path { path in
                switch shapeType {
                case .rectangle:
                    path.addRect(rect)
                    
                case .circle:
                    let diameter = min(rect.width, rect.height)
                    let circleRect = CGRect(
                        x: rect.midX - diameter/2,
                        y: rect.midY - diameter/2,
                        width: diameter,
                        height: diameter
                    )
                    path.addEllipse(in: circleRect)
                    
                case .triangle:
                    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                    path.closeSubpath()
                    
                case .diamond:
                    path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                    path.closeSubpath()
                    
                case .star:
                    createStarPath(in: rect, points: 5, path: &path)
                    
                case .hexagon:
                    createPolygonPath(in: rect, sides: 6, path: &path)
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        )
        .position(x: rect.midX, y: rect.midY)
    }
    
    private func createStarPath(in rect: CGRect, points: Int, path: inout Path) {
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
        path.closeSubpath()
    }
    
    private func createPolygonPath(in rect: CGRect, sides: Int, path: inout Path) {
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
        path.closeSubpath()
    }
}

/// 形状绘制手势视图
struct ShapeDrawingGestureView: View {
    @Binding var isDrawing: Bool
    @Binding var startPoint: CGPoint?
    @Binding var endPoint: CGPoint?
    
    let shapeType: ShapeType
    let color: Color
    let lineWidth: CGFloat
    let isFilled: Bool
    
    let onShapeCreated: (CGRect) -> Void
    
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDrawing {
                                isDrawing = true
                                startPoint = value.startLocation
                            }
                            endPoint = value.location
                        }
                        .onEnded { value in
                            if isDrawing,
                               let start = startPoint,
                               let end = endPoint {
                                
                                // 计算矩形
                                let rect = CGRect(
                                    x: min(start.x, end.x),
                                    y: min(start.y, end.y),
                                    width: abs(end.x - start.x),
                                    height: abs(end.y - start.y)
                                )
                                
                                // 确保最小尺寸
                                if rect.width >= 10 && rect.height >= 10 {
                                    onShapeCreated(rect)
                                }
                            }
                            
                            // 重置状态
                            isDrawing = false
                            startPoint = nil
                            endPoint = nil
                        }
                )
        }
    }
}