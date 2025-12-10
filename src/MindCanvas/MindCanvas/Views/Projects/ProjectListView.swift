import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.lastModified, order: .reverse) private var projects: [Project]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.md) {
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
        HStack(spacing: Theme.Spacing.lg) {
            thumbnailView
            
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(project.name)
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Colors.primaryText)
                    .lineLimit(2)
                
                HStack(spacing: Theme.Spacing.xs) {
                    Text(project.lastModified, style: .relative)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    
                    Text("·")
                        .foregroundStyle(Theme.Colors.secondaryText)
                    
                    Text("0 张图片")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBackground)
        .cornerRadius(Theme.Shapes.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
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
        .frame(width: Theme.Sizes.thumbnailLarge, height: Theme.Sizes.thumbnailLarge)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius))
    }
    
    private var placeholderView: some View {
        ZStack {
            projectGradient
            
            VStack(spacing: Theme.Spacing.xs) {
                Text(projectInitials)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
    
    private var projectGradient: some View {
        let gradients: [LinearGradient] = [
            LinearGradient(colors: [Color(hex: "#667EEA"), Color(hex: "#764BA2")], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [Color(hex: "#F093FB"), Color(hex: "#F5576C")], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [Color(hex: "#4FACFE"), Color(hex: "#00F2FE")], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [Color(hex: "#43E97B"), Color(hex: "#38F9D7")], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [Color(hex: "#FA709A"), Color(hex: "#FEE140")], startPoint: .topLeading, endPoint: .bottomTrailing),
        ]
        
        let hash = abs(project.name.hashValue)
        let index = hash % gradients.count
        return gradients[index]
    }
    
    private var projectInitials: String {
        let words = project.name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1)) + String(words[1].prefix(1))
        } else if let firstWord = words.first {
            return String(firstWord.prefix(2))
        }
        return "📝"
    }
}

#Preview {
    ProjectListView()
        .modelContainer(for: Project.self, inMemory: true)
}

