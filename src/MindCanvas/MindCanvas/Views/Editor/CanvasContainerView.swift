import SwiftUI

struct CanvasContainerView: View {
    @Bindable var viewModel: EditorViewModel
    
    var body: some View {
        ZStack {
            Color.gray.opacity(0.05)
            
            CanvasWebView(viewModel: viewModel)
                .padding()
            
            VStack {
                HStack {
                    Spacer()
                    helpButton
                }
                Spacer()
            }
            .padding()
        }
    }
    
    private var helpButton: some View {
        Button {
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("画布帮助")
    }
}

#Preview {
    CanvasContainerView(viewModel: EditorViewModel(project: Project(name: "示例")))
}

