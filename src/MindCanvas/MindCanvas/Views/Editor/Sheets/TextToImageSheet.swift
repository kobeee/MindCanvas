import SwiftUI

struct TextToImageSheet: View {
    @State private var prompt: String = ""
    @FocusState private var isPromptFocused: Bool
    let onGenerate: (String, ImageAspectRatio) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶部：Header（固定）
                header
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.top, Theme.Spacing.xxl)
                    .padding(.bottom, Theme.Spacing.lg)

                Divider()

                // 中部：Tips卡片（可滚动，高度受限）
                ScrollView {
                    tipsSection
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.vertical, Theme.Spacing.lg)
                }
                .frame(maxHeight: 120)

                // 提示词输入区域（独立，不在ScrollView中）
                promptEditor
                    .padding(.horizontal, Theme.Spacing.xxl)
                    .padding(.vertical, Theme.Spacing.lg)

                Divider()

                // 底部：按钮（固定）
                actions
                    .padding(Theme.Spacing.xxl)
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header
    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("文生图")
                    .font(Theme.Fonts.title3)
                    .foregroundStyle(Theme.Colors.primaryText)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            Text("输入提示词直接生成图片素材")
                .font(Theme.Fonts.subheadline)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Tips Section
    private var tipsSection: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.Colors.brandBlue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("快速提示")
                    .font(Theme.Fonts.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.primaryText)

                Text("默认生成 1:1 正方形图片。可在提示词中指定尺寸，如\"1920x1080 宽屏\"或\"竖屏手机壁纸\"")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.brandBlue.opacity(0.08))
        .cornerRadius(Theme.Shapes.buttonCornerRadius)
    }

    // MARK: - Prompt Editor（独立于ScrollView）
    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("提示词")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            TextEditor(text: $prompt)
                .focused($isPromptFocused)
                .frame(minHeight: 120, maxHeight: 200)
                .padding(Theme.Spacing.md)
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.appBackground)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .stroke(
                            isPromptFocused ? Theme.Colors.brandBlue : Color.gray.opacity(0.2),
                            lineWidth: isPromptFocused ? 2 : 1
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: isPromptFocused)
        }
    }

    // MARK: - Actions
    private var actions: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button("取消", action: onCancel)
                .secondaryButtonStyle()

            Button {
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                onGenerate(trimmed, .square)
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                    Text("确定生成")
                }
            }
            .primaryButtonStyle()
            .disabled(isGenerateDisabled)
            .opacity(isGenerateDisabled ? 0.5 : 1.0)
        }
    }

    private var isGenerateDisabled: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    TextToImageSheet(
        onGenerate: { prompt, ratio in
            print("Generate: \(prompt), ratio: \(ratio)")
        },
        onCancel: {
            print("Cancel")
        }
    )
}


