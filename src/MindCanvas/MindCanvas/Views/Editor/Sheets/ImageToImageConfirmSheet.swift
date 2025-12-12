import SwiftUI

struct ImageToImageConfirmSheet: View {
    let previewImage: UIImage
    let prompt: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                header
                preview
                promptBlock
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
                Text("确认生成")
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

            Text("请确认将作为参考的画布内容")
                .font(Theme.Fonts.subheadline)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    private var preview: some View {
        Image(uiImage: previewImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("提示词")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            Text(prompt)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.appBackground)
                .cornerRadius(Theme.Shapes.buttonCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .stroke(Color.gray.opacity(0.18), lineWidth: 1)
                )
        }
    }

    private var actions: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Button("取消", action: onCancel)
                .secondaryButtonStyle()

            Button {
                onConfirm()
            } label: {
                Label("确认生成", systemImage: "wand.and.stars")
            }
            .primaryButtonStyle()
        }
    }
}

#Preview {
    ImageToImageConfirmSheet(
        previewImage: UIImage(systemName: "photo") ?? UIImage(),
        prompt: "一个极简的未来主义画面，柔和光影，银灰配色",
        onConfirm: {},
        onCancel: {}
    )
}


