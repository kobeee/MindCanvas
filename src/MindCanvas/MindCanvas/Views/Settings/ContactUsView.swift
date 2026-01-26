import SwiftUI

struct InteractiveQRCodeImageView: UIViewRepresentable {
    let image: UIImage
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        
        let interaction = UIContextMenuInteraction(delegate: context.coordinator)
        imageView.addInteraction(interaction)
        
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        uiView.image = image
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(image: image)
    }
    
    class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        let image: UIImage
        
        init(image: UIImage) {
            self.image = image
        }
        
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                let saveAction = UIAction(title: "保存图片", image: UIImage(systemName: "square.and.arrow.down")) { _ in
                    UIImageWriteToSavedPhotosAlbum(self.image, nil, nil, nil)
                }
                return UIMenu(title: "", children: [saveAction])
            }
        }
        
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            guard let imageView = interaction.view as? UIImageView else { return nil }
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            return UITargetedPreview(view: imageView, parameters: parameters)
        }
    }
}

struct ContactUsView: View {
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                
                qrCodeSection
                
                Spacer()
                
                benefitPromptSection
                
                actionButtons
            }
            .background(Theme.Colors.appBackground)
            .navigationTitle("联系我们")
            .navigationBarTitleDisplayMode(.inline)
            .alert("提示", isPresented: $showingSaveAlert) {
                Button("确定", role: .cancel) { }
            } message: {
                Text(saveAlertMessage)
            }
        }
    }
    
    private var qrCodeSection: some View {
        VStack(spacing: Theme.Spacing.xl) {
            qrCodeImage
            
            VStack(spacing: Theme.Spacing.sm) {
                Text("逃离莫比乌斯")
                    .font(Theme.Fonts.title2)
                    .foregroundStyle(Theme.Colors.primaryText)
                
                Text("保存扫描二维码关注公众号")
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
                
                Text("私信留言，我们会尽快回复")
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .padding(Theme.Spacing.xl)
    }
    
    private var benefitPromptSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.Colors.goldGradient)

                Text("有福利")
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(Theme.Colors.goldGradient)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .fill(Theme.Colors.goldGradient.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .stroke(Theme.Colors.goldGradient.opacity(0.3), lineWidth: 1)
            )
            .padding(.horizontal, Theme.Spacing.xl)

            Text("关注后私信可领取免费使用额度")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.xl)
        }
        .padding(.bottom, Theme.Spacing.lg)
    }
    
    private var qrCodeImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                .fill(Theme.Colors.cardBackground)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            
            if let image = UIImage(named: "wechat_qrcode") {
                InteractiveQRCodeImageView(image: image)
                    .frame(width: 200, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                placeholderQRCode
            }
        }
        .frame(width: 220, height: 220)
    }
    
    private var placeholderQRCode: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "qrcode")
                .font(.system(size: 60))
                .foregroundStyle(Theme.Colors.brandBlue.opacity(0.3))
            
            Text("二维码图片")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button {
                saveQRCode()
            } label: {
                Text("保存二维码")
                    .font(Theme.Fonts.bodyBold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Sizes.buttonHeight)
                    .background(Theme.Colors.brandBlue)
                    .cornerRadius(Theme.Shapes.buttonCornerRadius)
            }
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .padding(.bottom, Theme.Spacing.xl)
    }
    
    private func saveQRCode() {
        guard let image = UIImage(named: "wechat_qrcode") else {
            saveAlertMessage = "二维码图片未找到，请联系开发者"
            showingSaveAlert = true
            return
        }
        
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        saveAlertMessage = "二维码已保存到相册"
        showingSaveAlert = true
    }
}

#Preview {
    NavigationStack {
        ContactUsView()
    }
}