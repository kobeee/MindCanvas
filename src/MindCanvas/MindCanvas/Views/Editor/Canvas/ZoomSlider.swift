import SwiftUI

/// 缩放滑动条组件
/// 替代原来的 +/- 按钮，提供更直观的缩放控制
struct ZoomSlider: View {
    @Binding var zoomScale: CGFloat
    var onZoomChanged: (CGFloat) -> Void

    private let minScale: CGFloat = 0.3
    private let maxScale: CGFloat = 3.0

    private var zoomPercent: Int {
        Int((zoomScale * 100).rounded())
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // 缩放滑动条
            Slider(value: $zoomScale, in: minScale...maxScale)
                .frame(width: 120)
                .tint(Theme.Colors.brandBlue)
                .onChange(of: zoomScale) { _, newValue in
                    onZoomChanged(newValue)
                }

            // 百分比显示（只读，不支持编辑）
            Text("\(zoomPercent)%")
                .font(Theme.Fonts.monospacedSmall)
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(width: 44, alignment: .center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        HStack {
            ZoomSlider(
                zoomScale: .constant(1.0),
                onZoomChanged: { _ in }
            )
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.bottom, 16)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.1))
}

