import SwiftUI

struct ImageToImageConfirmSheet: View {
    let previewImage: UIImage
    let prompt: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: Theme.Spacing.xl) {
                    header

                    Divider()

                    preview(availableHeight: proxy.size.height)

                    promptBlock

                    Spacer(minLength: Theme.Spacing.lg)

                    actions
                }
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
                Text("确认生成")
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
            Text("请确认将作为参考的画布内容")
                .font(Theme.Fonts.subheadline)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    // MARK: - Preview (动态高度)
    private func preview(availableHeight: CGFloat) -> some View {
        let previewHeight = min(450, max(240, availableHeight * 0.35))

        return VStack(spacing: Theme.Spacing.sm) {
            Text("选区预览")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(uiImage: previewImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: previewHeight)
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 4)
        }
    }

    // MARK: - Prompt Block
    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("提示词")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            Text(prompt.isEmpty ? "无提示词" : prompt)
                .font(Theme.Fonts.body)
                .foregroundStyle(prompt.isEmpty ? Theme.Colors.secondaryText : Theme.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.appBackground)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
        }
    }

    // MARK: - Actions
    private var actions: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button("取消", action: onCancel)
                .secondaryButtonStyle()

            Button {
                onConfirm()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "wand.and.stars")
                    Text("确认生成")
                }
            }
            .primaryButtonStyle()
        }
    }
}

#Preview {
    ImageToImageConfirmSheet(
        previewImage: UIImage(systemName: "photo")!,
        prompt: "a beautiful sunset",
        onConfirm: { print("Confirm") },
        onCancel: { print("Cancel") }
    )
}


