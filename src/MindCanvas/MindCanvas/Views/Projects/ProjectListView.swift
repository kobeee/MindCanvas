import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.lastModified, order: .reverse) private var projects: [Project]
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(projects) { project in
                    NavigationLink(destination: EditorView(project: project)) {
                        ProjectRow(project: project)
                    }
                }
                .onDelete(perform: deleteProjects)
            }
            .navigationTitle("我的创作")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createNewProject()
                    } label: {
                        Label("新建项目", systemImage: "plus")
                    }
                }
            }
            .onAppear {
                if projects.isEmpty {
                    createSampleProjects()
                }
            }
        }
    }
    
    private func createNewProject() {
        let newProject = Project(name: "未命名项目 \(projects.count + 1)")
        modelContext.insert(newProject)
    }
    
    private func deleteProjects(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(projects[index])
        }
    }
    
    private func createSampleProjects() {
        let samples = [
            Project(name: "示例项目 1"),
            Project(name: "示例项目 2"),
            Project(name: "AI 艺术创作")
        ]
        
        samples.forEach { modelContext.insert($0) }
    }
}

struct ProjectRow: View {
    let project: Project
    
    var body: some View {
        HStack {
            if let thumbnailUrl = project.thumbnailUrl {
                AsyncImage(url: URL(string: thumbnailUrl)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.headline)
                
                Text(project.lastModified, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ProjectListView()
        .modelContainer(for: Project.self, inMemory: true)
}

