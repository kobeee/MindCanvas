import SwiftUI

struct TextToImageSheet: View {
    @State private var prompt: String = ""
    @State private var selectedRatio: ImageAspectRatio = .square

    let onGenerate: (String, ImageAspectRatio) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                header
                promptEditor
                ratioPicker
                actions
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.xxl)
            .navigationBarHidden(true)
        }
        .presentationDetents([.medium, .large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("文生图")
                    .font(Theme.Fonts.title3)
                    .foregroundStyle(Theme.Colors.primaryText)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            Text("生成独立的图片素材，可拖入画布使用")
                .font(Theme.Fonts.subheadline)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("提示词")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            TextEditor(text: $prompt)
                .frame(height: 120)
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.appBackground)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                )
        }
    }

    private var ratioPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("尺寸")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: Theme.Spacing.md),
                GridItem(.flexible(), spacing: Theme.Spacing.md),
                GridItem(.flexible(), spacing: Theme.Spacing.md)
            ], spacing: Theme.Spacing.md) {
                ForEach(ImageAspectRatio.allCases) { ratio in
                    ratioButton(ratio)
                }
            }
        }
    }

    private func ratioButton(_ ratio: ImageAspectRatio) -> some View {
        Button {
            selectedRatio = ratio
        } label: {
            VStack(spacing: 6) {
                Text(ratio.rawValue)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(ratio.displayName)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .fill(selectedRatio == ratio ? Theme.Colors.brandBlue.opacity(0.12) : Theme.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .stroke(selectedRatio == ratio ? Theme.Colors.brandBlue.opacity(0.6) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button("取消", action: onCancel)
                .secondaryButtonStyle()

            Button {
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                onGenerate(trimmed, selectedRatio)
            } label: {
                Label("生成资源", systemImage: "wand.and.stars")
            }
            .primaryButtonStyle()
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
        }
    }
}

#Preview {
    TextToImageSheet(onGenerate: { _, _ in }, onCancel: {})
}


