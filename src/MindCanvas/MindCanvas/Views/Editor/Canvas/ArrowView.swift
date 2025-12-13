import SwiftUI
import CoreGraphics

/// 箭头视图
/// 用于在画布上绘制箭头
struct ArrowView: View {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let color: Color
    let lineWidth: CGFloat
    
    var body: some View {
        Path { path in
            // 绘制箭头主线
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            
            // 计算箭头角度
            let angle = atan2(endPoint.y - startPoint.y, endPoint.x - startPoint.x)
            
            // 箭头大小
            let arrowLength: CGFloat = 20
            let arrowAngle: CGFloat = .pi / 6
            
            // 绘制箭头两侧
            let arrowPoint1 = CGPoint(
                x: endPoint.x - arrowLength * cos(angle - arrowAngle),
                y: endPoint.y - arrowLength * sin(angle - arrowAngle)
            )
            
            let arrowPoint2 = CGPoint(
                x: endPoint.x - arrowLength * cos(angle + arrowAngle),
                y: endPoint.y - arrowLength * sin(angle + arrowAngle)
            )
            
            path.move(to: endPoint)
            path.addLine(to: arrowPoint1)
            
            path.move(to: endPoint)
            path.addLine(to: arrowPoint2)
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }
}

/// 箭头绘制工具视图
/// 处理箭头绘制的手势和状态
struct ArrowDrawingView: UIViewRepresentable {
    @Binding var isDrawing: Bool
    @Binding var startPoint: CGPoint?
    @Binding var endPoint: CGPoint?
    let color: Color
    let lineWidth: CGFloat
    let onArrowCreated: ((CGPoint, CGPoint) -> Void)?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        // 添加拖拽手势
        let panGesture = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        view.addGestureRecognizer(panGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // 不需要更新
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: ArrowDrawingView
        
        init(_ parent: ArrowDrawingView) {
            self.parent = parent
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            
            switch gesture.state {
            case .began:
                parent.isDrawing = true
                parent.startPoint = point
                parent.endPoint = point
                
            case .changed:
                parent.endPoint = point
                
            case .ended, .cancelled:
                parent.isDrawing = false
                if let start = parent.startPoint, let end = parent.endPoint {
                    parent.onArrowCreated?(start, end)
                }
                parent.startPoint = nil
                parent.endPoint = nil
                
            default:
                break
            }
        }
    }
}

#Preview {
    VStack {
        ArrowView(
            startPoint: CGPoint(x: 50, y: 50),
            endPoint: CGPoint(x: 200, y: 100),
            color: .blue,
            lineWidth: 3
        )
        .frame(width: 250, height: 150)
        .border(Color.gray)
        
        ArrowView(
            startPoint: CGPoint(x: 50, y: 100),
            endPoint: CGPoint(x: 200, y: 50),
            color: .red,
            lineWidth: 2
        )
        .frame(width: 250, height: 150)
        .border(Color.gray)
    }
}