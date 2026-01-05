import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.lastModified, order: .reverse) private var projects: [Project]
    @State private var selectedProject: Project?
    @State private var projectToDelete: Project?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(projects) { project in
                    Button {
                        selectedProject = project
                    } label: {
                        ProjectCard(project: project)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            projectToDelete = project
                            showDeleteConfirmation = true
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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
            .fullScreenCover(item: $selectedProject) { project in
                NativeEditorView(project: project)
            }
            .alert("确认删除", isPresented: $showDeleteConfirmation) {
                Button("取消", role: .cancel) {
                    projectToDelete = nil
                }
                Button("删除", role: .destructive) {
                    if let project = projectToDelete {
                        deleteProject(project)
                    }
                    projectToDelete = nil
                }
            } message: {
                Text("不可恢复，确认删除？")
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
    
    private func deleteProject(_ project: Project) {
        modelContext.delete(project)
        try? modelContext.save()
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

