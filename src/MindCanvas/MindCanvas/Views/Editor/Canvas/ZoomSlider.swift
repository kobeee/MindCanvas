import SwiftUI

/// 缩放滑动条组件
/// 替代原来的 +/- 按钮，提供更直观的缩放控制
struct ZoomSlider: View {
    @Binding var zoomScale: CGFloat
    var onZoomChanged: (CGFloat) -> Void
    
    @State private var zoomPercentDraft: String = "100"
    @FocusState private var isEditing: Bool
    
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
                    if !isEditing {
                        zoomPercentDraft = "\(Int((newValue * 100).rounded()))"
                    }
                }
            
            // 百分比显示/编辑
            TextField("", text: $zoomPercentDraft)
                .frame(width: 44)
                .multilineTextAlignment(.center)
                .font(Theme.Fonts.monospacedSmall)
                .textFieldStyle(.plain)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isEditing ? Color.white : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isEditing ? Theme.Colors.brandBlue : Color.clear, lineWidth: 1)
                        )
                )
                .focused($isEditing)
                .keyboardType(.numberPad)
                .onSubmit {
                    applyZoomDraft()
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") {
                            applyZoomDraft()
                            isEditing = false
                        }
                    }
                }
            
            Text("%")
                .font(Theme.Fonts.monospacedSmall)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .onChange(of: zoomScale) { _, newValue in
            guard !isEditing else { return }
            zoomPercentDraft = "\(Int((newValue * 100).rounded()))"
        }
    }
    
    private func applyZoomDraft() {
        let trimmed = zoomPercentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let percent = Double(trimmed) else {
            // 输入非法：回滚到真实缩放值
            zoomPercentDraft = "\(zoomPercent)"
            return
        }
        let scale = max(minScale, min(maxScale, percent / 100.0))
        zoomScale = scale
        onZoomChanged(scale)
        zoomPercentDraft = "\(Int((scale * 100).rounded()))"
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

