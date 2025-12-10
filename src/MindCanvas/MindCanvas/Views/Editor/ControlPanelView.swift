import SwiftUI

struct ControlPanelView: View {
    @Bindable var viewModel: EditorViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            configSection
            Divider()
            promptSection
            Spacer()
        }
    }
    
    private var headerSection: some View {
        HStack {
            Text("控制面板")
                .font(.headline)
            Spacer()
        }
        .padding()
    }
    
    private var configSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("API 配置")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Text("使用官方服务")
                        .font(.body)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("生成模型")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nano Banana Pro")
                            .font(.body)
                        Text("Gemini 3 Pro Image")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
    }
    
    private var promptSection: some View {
        VStack(spacing: 16) {
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("提示词")
                        .font(.headline)
                    Spacer()
                    if viewModel.hasSelection {
                        Label("已选择区域", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                
                TextEditor(text: $viewModel.prompt)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                if viewModel.prompt.isEmpty {
                    Text("描述你想要生成的图像...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .offset(x: 12, y: -130)
                        .allowsHitTesting(false)
                }
                
                Button {
                    Task {
                        await viewModel.generate()
                    }
                } label: {
                    if viewModel.isGenerating {
                        HStack {
                            ProgressView()
                                .tint(.white)
                            Text("生成中...")
                        }
                    } else {
                        Text("生成图像")
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .controlSize(.large)
                .disabled(viewModel.prompt.isEmpty || viewModel.isGenerating)
            }
            .padding()
        }
    }
}

#Preview {
    ControlPanelView(viewModel: EditorViewModel(project: Project(name: "示例")))
        .frame(width: 320, height: 600)
}

