import SwiftUI

/// 字体选择弹窗
struct FontPickerPopover: View {
    @Binding var selectedFont: String
    @Binding var fontSize: CGFloat
    @Binding var textColor: Color
    let onConfirm: () -> Void

    // 推荐字体列表
    private let recommendedFonts: [(name: String, displayName: String)] = [
        (".SF Pro Display", "SF Pro"),
        ("Helvetica Neue", "Helvetica"),
        ("Times New Roman", "Times"),
        ("Georgia", "Georgia"),
        ("Courier New", "Courier"),
    ]

    // 字体大小选项
    private let fontSizes: [CGFloat] = [16, 20, 24, 32, 48, 64]

    var body: some View {
        VStack(spacing: 16) {
            // 标题
            Text("文字设置")
                .font(.headline)
                .padding(.top, 8)

            Divider()

            // 字体选择
            VStack(alignment: .leading, spacing: 8) {
                Text("字体")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recommendedFonts, id: \.name) { font in
                            FontButton(
                                fontName: font.name,
                                displayName: font.displayName,
                                isSelected: selectedFont == font.name,
                                action: {
                                    selectedFont = font.name
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            // 字体大小
            VStack(alignment: .leading, spacing: 8) {
                Text("大小")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(fontSizes, id: \.self) { size in
                            Button {
                                fontSize = size
                            } label: {
                                Text("\(Int(size))")
                                    .font(.system(size: 14))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(fontSize == size ? Color.blue : Color.gray.opacity(0.1))
                                    )
                                    .foregroundColor(fontSize == size ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            // 颜色选择
            VStack(alignment: .leading, spacing: 8) {
                Text("颜色")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ColorPicker("", selection: $textColor)
                    .labelsHidden()
            }

            Divider()

            // 确认按钮
            Button {
                onConfirm()
            } label: {
                Text("添加文字")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .frame(width: 320)
    }
}

// MARK: - 字体按钮

private struct FontButton: View {
    let fontName: String
    let displayName: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(displayName)
                .font(.custom(fontName, size: 14))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.1))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
