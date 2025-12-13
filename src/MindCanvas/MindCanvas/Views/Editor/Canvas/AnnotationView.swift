import SwiftUI
import CoreGraphics

/// 标注视图
/// 用于在画布上绘制标注（矩形框+文字）
struct AnnotationView: View {
    let annotation: AnnotationLayerNode
    
    var body: some View {
        ZStack {
            // 矩形框
            Rectangle()
                .stroke(Color.fromHex(annotation.color) ?? .blue, lineWidth: annotation.lineWidth)
                .frame(width: annotation.rect.width, height: annotation.rect.height)
                .position(x: annotation.rect.midX, y: annotation.rect.midY)
            
            // 文字（在矩形框下方）
            Text(annotation.text)
                .font(.system(size: annotation.fontSize))
                .foregroundColor(Color.fromHex(annotation.color) ?? .blue)
                .position(annotation.textPosition)
                .multilineTextAlignment(.center)
        }
    }
}

/// 标注绘制工具视图
/// 处理标注绘制的手势和状态
struct AnnotationDrawingView: UIViewRepresentable {
    @Binding var isDrawing: Bool
    @Binding var startPoint: CGPoint?
    @Binding var endPoint: CGPoint?
    let color: Color
    let lineWidth: CGFloat
    let fontSize: CGFloat
    let onAnnotationCreated: ((CGRect, String) -> Void)?
    
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
        let parent: AnnotationDrawingView
        
        init(_ parent: AnnotationDrawingView) {
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
                    if rect.width > 20 && rect.height > 20 {
                        // 显示文字输入对话框
                        showTextInputAlert(for: rect)
                    }
                }
                parent.startPoint = nil
                parent.endPoint = nil
                
            default:
                break
            }
        }
        
        private func showTextInputAlert(for rect: CGRect) {
            let alert = UIAlertController(
                title: "添加标注",
                message: "请输入标注文字",
                preferredStyle: .alert
            )
            
            alert.addTextField { textField in
                textField.placeholder = "标注内容"
            }
            
            let confirmAction = UIAlertAction(title: "确定", style: .default) { _ in
                if let textField = alert.textFields?.first,
                   let text = textField.text,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.parent.onAnnotationCreated?(rect, text)
                }
            }
            
            let cancelAction = UIAlertAction(title: "取消", style: .cancel)
            
            alert.addAction(confirmAction)
            alert.addAction(cancelAction)
            
            // 获取当前的视图控制器并显示警告
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                rootViewController.present(alert, animated: true)
            }
        }
    }
}

#Preview {
    VStack {
        AnnotationView(
            annotation: AnnotationLayerNode(
                rect: CGRect(x: 20, y: 20, width: 100, height: 80),
                text: "重要标注",
                fontSize: 14,
                color: "#007AFF"
            )
        )
        .frame(width: 150, height: 150)
        .border(Color.gray)
        
        AnnotationView(
            annotation: AnnotationLayerNode(
                rect: CGRect(x: 50, y: 50, width: 120, height: 60),
                text: "注意这里",
                fontSize: 16,
                color: "#FF3B30"
            )
        )
        .frame(width: 200, height: 150)
        .border(Color.gray)
    }
}