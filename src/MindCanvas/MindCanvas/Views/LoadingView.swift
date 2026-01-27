import SwiftUI

struct LoadingView: View {
    var body: some View {
        ZStack {
            Theme.Colors.appBackground
                .ignoresSafeArea()

            VStack(spacing: Theme.Spacing.lg) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Theme.Colors.brandBlue)

                Text("正在加载...")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
    }
}

#Preview {
    LoadingView()
}