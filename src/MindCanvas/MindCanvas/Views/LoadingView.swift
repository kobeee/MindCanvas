import SwiftUI

struct LoadingView: View {
    var body: some View {
        ZStack {
            Theme.Colors.appBackground
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                // 添加应用Logo，便于识别
                Image(systemName: Theme.Icons.creationsFill)
                    .font(.system(size: 60))
                    .foregroundStyle(Theme.Colors.goldGradient)

                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Theme.Colors.brandBlue)

                Text("正在加载 MindCanvas...")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }
}

#Preview {
    LoadingView()
}