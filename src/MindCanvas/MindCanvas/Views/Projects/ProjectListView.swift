import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.lastModified, order: .reverse) private var projects: [Project]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    ForEach(projects) { project in
                        NavigationLink(destination: EditorView(project: project)) {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.appBackground)
            .navigationTitle("我的创作")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createNewProject()
                    } label: {
                        Label("新建项目", systemImage: Theme.Icons.add)
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

struct ProjectCard: View {
    let project: Project
    
    var body: some View {
        HStack(spacing: 16) {
            thumbnailView
            
            VStack(alignment: .leading, spacing: 8) {
                Text(project.name)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.Colors.primaryText)
                    .lineLimit(2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("修改于 \(project.lastModified.formatted(date: .abbreviated, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("0 张图片")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(Theme.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
    }
    
    private var thumbnailView: some View {
        Group {
            if let thumbnailUrl = project.thumbnailUrl {
                AsyncImage(url: URL(string: thumbnailUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderView
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: 120, height: 90)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var placeholderView: some View {
        ZStack {
            Color(uiColor: .systemGray6)
            
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 24, weight: .thin))
                .foregroundStyle(.secondary.opacity(0.3))
        }
    }
}

#Preview {
    ProjectListView()
        .modelContainer(for: Project.self, inMemory: true)
}

