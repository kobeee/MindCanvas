import SwiftUI

/// Magic Frame - AI 生成选框视图
/// 用户拖动此选框来定义 AI 生成的区域
struct MagicFrameView: View {
    @Binding var frame: CGRect
    @Binding var isVisible: Bool

    /// 视口尺寸（屏幕坐标系），用于边界约束
    let viewportSize: CGSize

    /// 选框在视口内的最小边距（避免贴边难以操作）
    private let viewportInset: CGFloat = 8
    
    @State private var isDragging = false
    @State private var isResizing = false

    @State private var dragStartFrame: CGRect?
    @State private var resizeStartFrame: CGRect?
    
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
                .position(x: frame.midX, y: max(12, frame.minY - 20))
                
                // 尺寸标签
                Text("\(Int(frame.width)) × \(Int(frame.height))")
                    .font(.caption2)
                    .monospacedDigit()
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .cornerRadius(4)
                    .position(x: frame.midX, y: min(viewportSize.height - 12, frame.maxY + 15))
            }
        }
    }
    
    // MARK: - 拖拽手势 (移动选框)
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true

                if dragStartFrame == nil {
                    dragStartFrame = frame
                }
                guard let start = dragStartFrame else { return }

                var newFrame = start
                newFrame.origin.x = start.origin.x + value.translation.width
                newFrame.origin.y = start.origin.y + value.translation.height

                frame = clampToViewport(newFrame)
            }
            .onEnded { _ in
                isDragging = false
                dragStartFrame = nil
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

                if resizeStartFrame == nil {
                    resizeStartFrame = frame
                }
                guard let start = resizeStartFrame else { return }

                var newFrame = start
                
                switch corner {
                case .topLeading:
                    // 左上角：调整 x, y, width, height
                    newFrame.origin.x = start.origin.x + value.translation.width
                    newFrame.origin.y = start.origin.y + value.translation.height
                    newFrame.size.width = start.size.width - value.translation.width
                    newFrame.size.height = start.size.height - value.translation.height
                    
                case .topTrailing:
                    // 右上角：调整 y, width, height
                    newFrame.origin.y = start.origin.y + value.translation.height
                    newFrame.size.width = start.size.width + value.translation.width
                    newFrame.size.height = start.size.height - value.translation.height
                    
                case .bottomLeading:
                    // 左下角：调整 x, width, height
                    newFrame.origin.x = start.origin.x + value.translation.width
                    newFrame.size.width = start.size.width - value.translation.width
                    newFrame.size.height = start.size.height + value.translation.height
                    
                case .bottomTrailing:
                    // 右下角：调整 width, height
                    newFrame.size.width = start.size.width + value.translation.width
                    newFrame.size.height = start.size.height + value.translation.height
                }
                
                // 限制最小尺寸
                newFrame.size.width = max(minSize, newFrame.size.width)
                newFrame.size.height = max(minSize, newFrame.size.height)

                // 限制最大尺寸（不超过视口）
                newFrame.size.width = min(newFrame.size.width, max(1, viewportSize.width - 2 * viewportInset))
                newFrame.size.height = min(newFrame.size.height, max(1, viewportSize.height - 2 * viewportInset))

                frame = clampToViewport(newFrame)
            }
            .onEnded { _ in
                isResizing = false
                resizeStartFrame = nil
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

    // MARK: - Viewport Clamp

    private func clampToViewport(_ input: CGRect) -> CGRect {
        var rect = input

        // 宽高兜底
        rect.size.width = max(minSize, rect.size.width)
        rect.size.height = max(minSize, rect.size.height)

        let maxX = max(viewportInset, viewportSize.width - viewportInset - rect.size.width)
        let maxY = max(viewportInset, viewportSize.height - viewportInset - rect.size.height)

        rect.origin.x = min(max(rect.origin.x, viewportInset), maxX)
        rect.origin.y = min(max(rect.origin.y, viewportInset), maxY)

        return rect
    }
}

// MARK: - 预览

#Preview {
    ZStack {
        Color.gray.opacity(0.1)
        
        MagicFrameView(
            frame: .constant(CGRect(x: 100, y: 100, width: 300, height: 200)),
            isVisible: .constant(true),
            viewportSize: CGSize(width: 500, height: 400)
        )
    }
    .frame(width: 500, height: 400)
}

