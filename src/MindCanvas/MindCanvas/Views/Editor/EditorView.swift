import SwiftUI
import SwiftData

struct EditorView: View {
    let project: Project
    @State private var viewModel: EditorViewModel
    @Environment(\.columnVisibilityBinding) private var columnVisibility
    
    init(project: Project) {
        self.project = project
        self._viewModel = State(initialValue: EditorViewModel(project: project))
    }
    
    var body: some View {
        HStack(spacing: 0) {
            AssetLibraryView(viewModel: viewModel)
                .frame(width: 300)
            
            Divider()
            
            CanvasContainerView(viewModel: viewModel)
            
            Divider()
            
            ControlPanelView(viewModel: viewModel)
                .frame(width: 320)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                TextField("项目名称", text: $viewModel.projectName)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .onAppear {
            columnVisibility?.wrappedValue = .detailOnly
        }
        .onDisappear {
            columnVisibility?.wrappedValue = .all
        }
    }
}

#Preview {
    @Previewable @State var project = Project(name: "示例项目")
    
    NavigationStack {
        EditorView(project: project)
    }
    .modelContainer(for: [Project.self, Asset.self])
}

