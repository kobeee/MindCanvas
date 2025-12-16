import SwiftUI

/// 画笔设置弹出框
struct PenSettingsPopover: View {
    @Binding var penColor: Color
    @Binding var penWidth: CGFloat
    @Environment(\.dismiss) private var dismiss

    // 预设颜色
    private let presetColors: [Color] = [
        .black, .red, .blue, .green, .orange, .purple, .brown, .gray
    ]

    // 线宽范围
    private let minWidth: CGFloat = 1
    private let maxWidth: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            Text("笔触设置")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.top, 16)
                .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 16) {
                // 大小调节
                sizeSection

                // 颜色选择
                colorSection
            }
            .padding(16)
        }
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        )
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - 大小调节区

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("大小")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(penWidth))pt")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
            }

            // 自定义滑块样式
            HStack(spacing: 12) {
                // 最小预览圆
                Circle()
                    .fill(penColor)
                    .frame(width: 4, height: 4)

                Slider(value: $penWidth, in: minWidth...maxWidth, step: 1)
                    .tint(Theme.Colors.brandBlue)

                // 最大预览圆
                Circle()
                    .fill(penColor)
                    .frame(width: 16, height: 16)
            }

            // 实时预览线条
            penPreview
        }
    }

    // MARK: - 线条预览

    private var penPreview: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: penWidth / 2)
                .fill(penColor)
                .frame(width: 80, height: penWidth)
            Spacer()
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(uiColor: .systemGray6))
        )
    }

    // MARK: - 颜色选择区

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("颜色")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(presetColors, id: \.self) { color in
                    ColorButton(
                        color: color,
                        isSelected: penColor == color,
                        action: { penColor = color }
                    )
                }

                // 自定义颜色按钮
                CustomColorButton(selectedColor: $penColor)
            }
        }
    }
}

// MARK: - 颜色按钮

private struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 32, height: 32)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 32, height: 32)

                    Circle()
                        .strokeBorder(Theme.Colors.brandBlue, lineWidth: 2)
                        .frame(width: 38, height: 38)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
    }
}

// MARK: - 自定义颜色按钮

private struct CustomColorButton: View {
    @Binding var selectedColor: Color

    var body: some View {
        ColorPicker("", selection: $selectedColor, supportsOpacity: false)
            .labelsHidden()
            .frame(width: 32, height: 32)
            .background(
                Circle()
                    .strokeBorder(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .frame(width: 44, height: 44)
    }
}

// MARK: - Preview

#Preview {
    PenSettingsPopover(
        penColor: .constant(.black),
        penWidth: .constant(4)
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}