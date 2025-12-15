import SwiftUI

/// 直线预览视图
struct LinePreviewView: View {
    let startPoint: CGPoint
    let endPoint: CGPoint
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        Path { path in
            path.move(to: startPoint)
            path.addLine(to: endPoint)
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }
}
