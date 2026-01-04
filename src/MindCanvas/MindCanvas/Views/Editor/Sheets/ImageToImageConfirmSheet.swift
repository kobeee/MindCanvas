import SwiftUI

struct ImageToImageConfirmSheet: View {
    let previewImage: UIImage
    let prompt: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var showFullscreenPreview = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let safeHeight = proxy.size.height
                let safeWidth = proxy.size.width

                let fixedHeight: CGFloat = 318
                let availableHeight = max(250, safeHeight - fixedHeight)
                let previewMaxHeight = min(safeHeight * 0.55, availableHeight)

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.top, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.md)

                    Divider()

                    ScrollView {
                        VStack(spacing: Theme.Spacing.lg) {
                            previewSection(
                                maxHeight: previewMaxHeight,
                                containerWidth: safeWidth - Theme.Spacing.xxl * 2
                            )

                            promptBlock
                        }
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.vertical, Theme.Spacing.lg)
                    }

                    Divider()

                    actions
                        .padding(.horizontal, Theme.Spacing.xxl)
                        .padding(.vertical, Theme.Spacing.lg)
                }
            }
            .navigationBarHidden(true)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showFullscreenPreview) {
            FullscreenImagePreview(
                image: previewImage,
                onDismiss: { showFullscreenPreview = false }
            )
        }
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
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Theme.Colors.secondaryText.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            Text("请确认将作为参考的画布内容")
                .font(Theme.Fonts.subheadline)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }

    private func previewSection(maxHeight: CGFloat, containerWidth: CGFloat) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                showFullscreenPreview = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: containerWidth, maxHeight: maxHeight)
                        .background(
                            CheckerboardPattern()
                                .foregroundStyle(Color.gray.opacity(0.1))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)

                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                        .padding(Theme.Spacing.md)
                }
            }
            .buttonStyle(.plain)

            HStack {
                Text("选区预览")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Spacer()

                Text("点击放大查看")
                    .font(Theme.Fonts.caption2)
                    .foregroundStyle(Theme.Colors.brandBlue)

                Spacer()

                Text("\(Int(previewImage.size.width)) x \(Int(previewImage.size.height))")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.Colors.secondaryText.opacity(0.6))
            }
        }
    }

    private var promptBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("提示词")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)

            Text(prompt.isEmpty ? "无提示词" : prompt)
                .font(Theme.Fonts.body)
                .foregroundStyle(prompt.isEmpty ? Theme.Colors.secondaryText : Theme.Colors.primaryText)
                .lineLimit(3)
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

struct FullscreenImagePreview: View {
    let image: UIImage
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.9)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }

                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 0.5), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                offset = CGSize(
                                    width: lastOffset.width + value.translation.width,
                                    height: lastOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            if scale > 1.0 {
                                scale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.0
                            }
                        }
                    }

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            onDismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .padding(Theme.Spacing.xl)
                    }
                    Spacer()
                }

                VStack {
                    Spacer()
                    HStack {
                        Text("双指缩放 | 双击重置 | 点击背景关闭")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.bottom, Theme.Spacing.xxl)
                }
            }
        }
    }
}

private struct CheckerboardPattern: View {
    var body: some View {
        GeometryReader { geo in
            let size: CGFloat = 10
            let rows = Int(ceil(geo.size.height / size))
            let cols = Int(ceil(geo.size.width / size))

            Canvas { context, _ in
                for row in 0..<rows {
                    for col in 0..<cols {
                        if (row + col) % 2 == 0 {
                            let rect = CGRect(
                                x: CGFloat(col) * size,
                                y: CGFloat(row) * size,
                                width: size,
                                height: size
                            )
                            context.fill(Path(rect), with: .foreground)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ImageToImageConfirmSheet(
        previewImage: UIImage(systemName: "photo.artframe")!,
        prompt: "一只可爱的猫咪在草地上玩耍",
        onConfirm: { },
        onCancel: { }
    )
}


