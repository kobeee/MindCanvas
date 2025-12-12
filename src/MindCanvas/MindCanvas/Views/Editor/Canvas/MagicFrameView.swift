import SwiftUI

/// Magic Frame - AI 生成选框视图
/// 用户拖动此选框来定义 AI 生成的区域
struct MagicFrameView: View {
    @Binding var frame: CGRect
    @Binding var isVisible: Bool
    
    @State private var isDragging = false
    @State private var isResizing = false
    
    /// 最小尺寸
    private let minSize: CGFloat = 100
    
    var body: some View {
        if isVisible {
            ZStack {
                // 主选框
                Rectangle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 3
                    )
                    .background(Color.blue.opacity(0.05))
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .gesture(dragGesture)
                
                // 四个角的控制手柄
                cornerHandle(at: .topLeading)
                cornerHandle(at: .topTrailing)
                cornerHandle(at: .bottomLeading)
                cornerHandle(at: .bottomTrailing)
                
                // 顶部标签
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text("AI 生成区域")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .position(x: frame.midX, y: frame.minY - 20)
                
                // 尺寸标签
                Text("\(Int(frame.width)) × \(Int(frame.height))")
                    .font(.caption2)
                    .monospacedDigit()
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(4)
                    .position(x: frame.midX, y: frame.maxY + 15)
            }
        }
    }
    
    // MARK: - 拖拽手势 (移动选框)
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                
                let newX = frame.origin.x + value.translation.width
                let newY = frame.origin.y + value.translation.height
                
                frame.origin = CGPoint(x: newX, y: newY)
            }
            .onEnded { _ in
                isDragging = false
            }
    }
    
    // MARK: - 角落控制手柄
    
    private func cornerHandle(at corner: Corner) -> some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 24, height: 24)
            .overlay(
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
            )
            .position(cornerPosition(for: corner))
            .gesture(resizeGesture(for: corner))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
    }
    
    // MARK: - 缩放手势
    
    private func resizeGesture(for corner: Corner) -> some Gesture {
        DragGesture()
            .onChanged { value in
                isResizing = true
                
                var newFrame = frame
                
                switch corner {
                case .topLeading:
                    // 左上角：调整 x, y, width, height
                    newFrame.origin.x += value.translation.width
                    newFrame.origin.y += value.translation.height
                    newFrame.size.width -= value.translation.width
                    newFrame.size.height -= value.translation.height
                    
                case .topTrailing:
                    // 右上角：调整 y, width, height
                    newFrame.origin.y += value.translation.height
                    newFrame.size.width += value.translation.width
                    newFrame.size.height -= value.translation.height
                    
                case .bottomLeading:
                    // 左下角：调整 x, width, height
                    newFrame.origin.x += value.translation.width
                    newFrame.size.width -= value.translation.width
                    newFrame.size.height += value.translation.height
                    
                case .bottomTrailing:
                    // 右下角：调整 width, height
                    newFrame.size.width += value.translation.width
                    newFrame.size.height += value.translation.height
                }
                
                // 限制最小尺寸
                if newFrame.width >= minSize && newFrame.height >= minSize {
                    frame = newFrame
                }
            }
            .onEnded { _ in
                isResizing = false
            }
    }
    
    // MARK: - 辅助方法
    
    private func cornerPosition(for corner: Corner) -> CGPoint {
        switch corner {
        case .topLeading:
            return CGPoint(x: frame.minX, y: frame.minY)
        case .topTrailing:
            return CGPoint(x: frame.maxX, y: frame.minY)
        case .bottomLeading:
            return CGPoint(x: frame.minX, y: frame.maxY)
        case .bottomTrailing:
            return CGPoint(x: frame.maxX, y: frame.maxY)
        }
    }
    
    private enum Corner {
        case topLeading
        case topTrailing
        case bottomLeading
        case bottomTrailing
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.gray.opacity(0.1)
        
        MagicFrameView(
            frame: .constant(CGRect(x: 100, y: 100, width: 300, height: 200)),
            isVisible: .constant(true)
        )
    }
    .frame(width: 500, height: 400)
}

