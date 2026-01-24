import SwiftUI

struct SecureAPIKeyField: View {
    @Binding var apiKey: String
    @State private var isSecure: Bool = true
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "key.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.Colors.brandBlue)

            if isSecure {
                SecureField("请输入 API Key", text: $apiKey)
                    .focused($isFocused)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.primaryText)
            } else {
                TextField("请输入 API Key", text: $apiKey)
                    .focused($isFocused)
                    .textContentType(.password)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.primaryText)
            }

            Button {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSecure.toggle()
                }
            } label: {
                Image(systemName: isSecure ? "eye.slash" : "eye")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .padding()
        .frame(height: Theme.Sizes.buttonHeight)
        .background(Theme.Colors.cardBackground)
        .cornerRadius(Theme.Shapes.buttonCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                .stroke(isFocused ? Theme.Colors.brandBlue : Color.clear, lineWidth: 2)
        )
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.lg) {
        SecureAPIKeyField(apiKey: .constant(""))
        SecureAPIKeyField(apiKey: .constant("AIzaSyExampleApiKeyForTesting1234567890"))
    }
    .padding()
    .background(Theme.Colors.appBackground)
}