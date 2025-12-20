import SwiftUI

/// 字体管理面板
/// 提供完整的字体管理功能，包括浏览、搜索、筛选和预览
struct FontManagementPanel: View {
    @State private var selectedCategory: FontManager.FontCategory = .system
    @State private var searchText = ""
    @State private var showChineseOnly = false
    @State private var selectedFont: FontManager.FontInfo?
    @State private var showingComparison = false
    @State private var showingAvailabilityReport = false
    
    private let fontManager = FontManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 搜索和筛选区域
                searchAndFilterSection
                
                Divider()
                
                // 字体列表
                fontListSection
            }
            .navigationTitle("字体管理")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("字体对比") {
                            showingComparison = true
                        }
                        
                        Button("可用性报告") {
                            showingAvailabilityReport = true
                        }
                        
                        Button("刷新字体列表") {
                            refreshFontList()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $selectedFont) { fontInfo in
            FontDetailSheet(fontInfo: fontInfo)
        }
        .sheet(isPresented: $showingComparison) {
            FontComparisonSheet(fonts: filteredFonts)
        }
        .sheet(isPresented: $showingAvailabilityReport) {
            FontAvailabilityReportSheet()
        }
    }
    
    // MARK: - 搜索和筛选区域
    
    private var searchAndFilterSection: some View {
        VStack(spacing: 16) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("搜索字体名称...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // 分类选择器
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(FontManager.FontCategory.allCases, id: \.self) { category in
                        CategoryChip(
                            category: category,
                            isSelected: selectedCategory == category,
                            count: fontManager.getFonts(for: category).count,
                            action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = category
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal)
            }
            
            // 筛选选项
            HStack {
                Toggle("仅显示支持中文的字体", isOn: $showChineseOnly)
                    .font(.caption)
                
                Spacer()
                
                Text("\(filteredFonts.count) 个字体")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .background(Color(UIColor.systemBackground))
    }
    
    // MARK: - 字体列表区域
    
    private var fontListSection: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredFonts, id: \.name) { fontInfo in
                    FontListRow(
                        fontInfo: fontInfo,
                        onTap: {
                            selectedFont = fontInfo
                        }
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - 计算属性
    
    private var filteredFonts: [FontManager.FontInfo] {
        var fonts = fontManager.getFonts(for: selectedCategory)
        
        // 搜索筛选
        if !searchText.isEmpty {
            fonts = fonts.filter { font in
                font.displayName.localizedCaseInsensitiveContains(searchText) ||
                font.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // 中文支持筛选
        if showChineseOnly {
            fonts = fonts.filter { $0.supportsChinese }
        }
        
        // 排序：优先显示可用字体，然后按名称排序
        return fonts.sorted { font1, font2 in
            if font1.isAvailable != font2.isAvailable {
                return font1.isAvailable && !font2.isAvailable
            } else {
                return font1.displayName < font2.displayName
            }
        }
    }
    
    // MARK: - 方法
    
    private func refreshFontList() {
        // 触发字体列表刷新
        // 这里可以添加重新加载字体的逻辑
    }
}

// MARK: - 分类芯片组件

private struct CategoryChip: View {
    let category: FontManager.FontCategory
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: categoryIcon(for: category))
                    .font(.system(size: 12, weight: .medium))
                
                Text(category.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text("(\(count))")
                    .font(.caption2)
                    .opacity(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Theme.Colors.brandBlue : Color.gray.opacity(0.1))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
    
    private func categoryIcon(for category: FontManager.FontCategory) -> String {
        switch category {
        case .system: return "applelogo"
        case .chinese: return "character.textbox"
        case .sansSerif: return "textformat.alt"
        case .serif: return "textformat"
        case .handwritten: return "scribble"
        case .monospaced: return "textformat.abc"
        case .display: return "signpost.right"
        case .artistic: return "paintbrush"
        }
    }
}

// MARK: - 字体列表行组件

private struct FontListRow: View {
    let fontInfo: FontManager.FontInfo
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 字体预览
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aa")
                        .font(.custom(fontInfo.name, size: 20))
                        .foregroundColor(fontInfo.isAvailable ? .primary : .secondary)
                    
                    if fontInfo.supportsChinese {
                        Text("中文")
                            .font(.custom(fontInfo.name, size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 60, alignment: .leading)
                
                // 字体信息
                VStack(alignment: .leading, spacing: 4) {
                    Text(fontInfo.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 8) {
                        Text(fontInfo.category.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if fontInfo.supportsChinese {
                            Text("中文")
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(2)
                        }
                    }
                }
                
                Spacer()
                
                // 状态指示器
                Image(systemName: fontInfo.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(fontInfo.isAvailable ? .green : .red)
                    .font(.title3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .opacity(fontInfo.isAvailable ? 1.0 : 0.6)
    }
}

// MARK: - 字体详情表单

struct FontDetailSheet: View {
    let fontInfo: FontManager.FontInfo
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // 字体预览
                    FontPreviewView(
                        fontInfo: fontInfo,
                        fontSize: 32,
                        textColor: .primary
                    )
                    .padding()
                    
                    // 字体信息
                    VStack(alignment: .leading, spacing: 16) {
                        DetailRow(title: "字体名称", value: fontInfo.name)
                        DetailRow(title: "显示名称", value: fontInfo.displayName)
                        DetailRow(title: "分类", value: fontInfo.category.rawValue)
                        DetailRow(title: "可用性", value: fontInfo.isAvailable ? "可用" : "不可用")
                        DetailRow(title: "中文支持", value: fontInfo.supportsChinese ? "支持" : "不支持")
                    }
                    .padding()
                }
            }
            .navigationTitle(fontInfo.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - 字体对比表单

struct FontComparisonSheet: View {
    let fonts: [FontManager.FontInfo]
    @Environment(\.dismiss) private var dismiss
    @State private var testText = "The quick brown fox jumps over the lazy dog 快速的棕色狐狸跳过懒惰的狗"
    
    var body: some View {
        NavigationView {
            VStack {
                // 测试文本输入
                VStack(alignment: .leading, spacing: 8) {
                    Text("测试文本")
                        .font(.headline)
                    
                    TextField("输入要测试的文本...", text: $testText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                .padding()
                
                // 对比预览
                FontComparisonView(
                    fonts: Array(fonts.prefix(10)), // 限制显示数量
                    testText: testText,
                    fontSize: 18
                )
            }
            .navigationTitle("字体对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 可用性报告表单

struct FontAvailabilityReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var report = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(report)
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            .navigationTitle("可用性报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                generateReport()
            }
        }
    }
    
    private func generateReport() {
        report = FontAvailabilityDetector.shared.generateAvailabilityReport()
    }
}

#Preview {
    FontManagementPanel()
}