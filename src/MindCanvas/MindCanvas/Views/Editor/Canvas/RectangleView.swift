import SwiftUI
import CoreGraphics

/// 矩形视图
/// 用于在画布上绘制矩形
struct RectangleShapeView: View {
    let rect: CGRect
    let color: Color
    let lineWidth: CGFloat
    let isFilled: Bool
    
    var body: some View {
        Path { path in
            path.addRect(rect)
        }
        .stroke(
            isFilled ? color : Color.clear,
            lineWidth: isFilled ? 0 : lineWidth
        )
        .background(
            isFilled ? color : Color.clear
        )
        .overlay(
            // 如果是空心矩形，添加边框
            isFilled ? nil : Rectangle()
                .stroke(color, lineWidth: lineWidth)
        )
    }
}

/// 矩形绘制工具视图
/// 处理矩形绘制的手势和状态
struct RectangleDrawingView: UIViewRepresentable {
    @Binding var isDrawing: Bool
    @Binding var startPoint: CGPoint?
    @Binding var endPoint: CGPoint?
    let color: Color
    let lineWidth: CGFloat
    let isFilled: Bool
    let onRectangleCreated: ((CGRect) -> Void)?
    
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
        let parent: RectangleDrawingView
        
        init(_ parent: RectangleDrawingView) {
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
                    let rect = CGRect(
                        x: min(start.x, end.x),
                        y: min(start.y, end.y),
                        width: abs(end.x - start.x),
                        height: abs(end.y - start.y)
                    )
                    
                    // 只有当矩形有一定大小时才创建
                    if rect.width > 5 && rect.height > 5 {
                        parent.onRectangleCreated?(rect)
                    }
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
        RectangleShapeView(
            rect: CGRect(x: 20, y: 20, width: 100, height: 60),
            color: .blue,
            lineWidth: 3,
            isFilled: false
        )
        .frame(width: 150, height: 100)
        .border(Color.gray)
        
        RectangleShapeView(
            rect: CGRect(x: 20, y: 20, width: 100, height: 60),
            color: .red.opacity(0.3),
            lineWidth: 0,
            isFilled: true
        )
        .frame(width: 150, height: 100)
        .border(Color.gray)
    }
}