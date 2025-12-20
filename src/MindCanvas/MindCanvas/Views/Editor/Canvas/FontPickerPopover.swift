import SwiftUI

/// 现代化字体选择弹窗
/// 提供优雅的字体、大小和颜色选择体验，支持中文和多种字体分类
struct FontPickerPopover: View {
    @Binding var selectedFont: String
    @Binding var fontSize: CGFloat
    @Binding var textColor: Color
    let onConfirm: () -> Void
    
    // 实时更新状态
    var onFontChanged: ((String, CGFloat, Color) -> Void)?
    
    // MARK: - 字体管理器
    private let fontManager = FontManager.shared
    
    // MARK: - 状态
    @State private var selectedCategory: FontManager.FontCategory = .system
    @State private var searchText = ""
    @State private var availableFonts: [FontManager.FontInfo] = []
    
    // MARK: - 初始化
    init(
        selectedFont: Binding<String>,
        fontSize: Binding<CGFloat>,
        textColor: Binding<Color>,
        onConfirm: @escaping () -> Void,
        onFontChanged: ((String, CGFloat, Color) -> Void)? = nil
    ) {
        self._selectedFont = selectedFont
        self._fontSize = fontSize
        self._textColor = textColor
        self.onConfirm = onConfirm
        self.onFontChanged = onFontChanged
        
        // 初始化时加载字体
        self._availableFonts = State(initialValue: FontManager.shared.getAllFonts())
    }
    
    private let fontSizes: [CGFloat] = [12, 14, 16, 18, 20, 24, 28, 32, 36, 42, 48, 56, 64]
    
    // 预设颜色方案
    private let presetColors: [Color] = [
        .black, .white, .red, .blue, .green, .orange, .purple, .pink,
        Color.fromHex("#007AFF") ?? .blue, // iOS蓝
        Color.fromHex("#34C759") ?? .green, // iOS绿
        Color.fromHex("#FF3B30") ?? .red, // iOS红
        Color.fromHex("#FF9500") ?? .orange, // iOS橙
        Color.fromHex("#AF52DE") ?? .purple, // iOS紫
        Color.fromHex("#FF2D92") ?? .pink, // iOS粉
        Color.fromHex("#5AC8FA") ?? .blue, // iOS浅蓝
        Color.fromHex("#FFCC00") ?? .yellow, // iOS黄
    ]
    
    @State private var customColor: Color = .black
    @State private var showingCustomColorPicker = false
    @State private var previewText = "预览文字 Preview Text 123"
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 预览区域
                previewSection
                
                Divider()
                    .padding(.horizontal, -Theme.Spacing.lg)
                
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.lg) {
                        fontCategorySection
                        fontSelectionSection
                        fontSizeSection
                        colorSelectionSection
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                }
            }
            .navigationTitle("文字设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        // 关闭弹窗逻辑由外部处理
                    }
                    .foregroundColor(Theme.Colors.secondaryText)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        onConfirm()
                    }
                    .foregroundColor(Theme.Colors.brandBlue)
                    .fontWeight(.semibold)
                }
            }
        }
        .frame(width: 420, height: 650)
        .background(Theme.Colors.appBackground)
        .cornerRadius(Theme.Shapes.largeCardCornerRadius)
        .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 8)
        .onAppear {
            loadAvailableFonts()
        }
        .onChange(of: selectedFont) { _, newFont in
            onFontChanged?(newFont, fontSize, textColor)
        }
        .onChange(of: fontSize) { _, newSize in
            onFontChanged?(selectedFont, newSize, textColor)
        }
        .onChange(of: textColor) { _, newColor in
            onFontChanged?(selectedFont, fontSize, newColor)
        }
    }
    
    // MARK: - 预览区域
    
    private var previewSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text("预览效果")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                    .fill(Theme.Colors.cardBackground)
                
                Text(previewText)
                    .font(.custom(selectedFont, size: fontSize))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.lg)
            }
            .frame(height: 100)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(Theme.Spacing.lg)
    }
    
    // MARK: - 字体分类区域
    
    private var fontCategorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(title: "分类", icon: "folder")
            
            // 分类选择器
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(FontManager.FontCategory.allCases, id: \.self) { category in
                        CategoryButton(
                            category: category,
                            isSelected: selectedCategory == category,
                            action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedCategory = category
                                    searchText = ""
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
            }
        }
    }
    
    // MARK: - 字体选择区域
    
    private var fontSelectionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(title: "字体", icon: "textformat")
            
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.Colors.secondaryText)
                    .font(.system(size: 14))
                
                TextField("搜索字体...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.body)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .fill(Color.gray.opacity(0.1))
            )
            
            // 字体列表
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Theme.Spacing.sm) {
                ForEach(displayedFonts, id: \.name) { font in
                    EnhancedFontButton(
                        fontInfo: font,
                        isSelected: selectedFont == font.name,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedFont = font.name
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - 字体大小区域
    
    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(title: "大小", icon: "textformat.size")
            
            // 滑块控制
            HStack {
                Text("\(Int(fontSize))")
                    .font(Theme.Fonts.bodyBold)
                    .foregroundColor(Theme.Colors.brandBlue)
                    .frame(width: 40, alignment: .leading)
                
                Slider(value: Binding(
                    get: { fontSize },
                    set: { newValue in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            fontSize = newValue
                        }
                    }
                ), in: 12...64, step: 1)
                
                Text("pt")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            
            // 快速选择按钮
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Theme.Spacing.xs) {
                ForEach([12, 16, 20, 24, 32, 48], id: \.self) { size in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            fontSize = CGFloat(size)
                        }
                    } label: {
                        Text("\(size)")
                            .font(Theme.Fonts.caption)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(fontSize == CGFloat(size) ? Theme.Colors.brandBlue : Theme.Colors.cardBackground)
                            )
                            .foregroundColor(fontSize == CGFloat(size) ? .white : Theme.Colors.primaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 颜色选择区域
    
    private var colorSelectionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionHeader(title: "颜色", icon: "paintpalette")
            
            // 预设颜色网格
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Theme.Spacing.sm) {
                ForEach(presetColors, id: \.self) { color in
                    ColorButton(
                        color: color,
                        isSelected: textColor == color,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                textColor = color
                            }
                        }
                    )
                }
                
                // 自定义颜色按钮
                Button {
                    showingCustomColorPicker.toggle()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.red, .orange, .yellow, .green, .blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Image(systemName: "plus")
                            .foregroundColor(.white)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
            }
            
            // 当前颜色显示
            HStack {
                Text("当前颜色")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                
                Spacer()
                
                HStack(spacing: Theme.Spacing.sm) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(textColor)
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    
                    Text(colorToHex(textColor))
                        .font(Theme.Fonts.monospacedSmall)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            .padding(.top, Theme.Spacing.sm)
        }
        .sheet(isPresented: $showingCustomColorPicker) {
            NavigationView {
                VStack {
                    ColorPicker("自定义颜色", selection: Binding(
                        get: { textColor },
                        set: { newColor in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                textColor = newColor
                            }
                        }
                    ))
                    .labelsHidden()
                    .frame(height: 200)
                    .padding()
                    
                    Spacer()
                }
                .navigationTitle("自定义颜色")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") {
                            showingCustomColorPicker = false
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(Theme.Colors.brandBlue)
                .font(.system(size: 14, weight: .medium))
            
            Text(title)
                .font(Theme.Fonts.bodyBold)
                .foregroundColor(Theme.Colors.primaryText)
        }
    }
    
    /// 加载可用字体
    private func loadAvailableFonts() {
        availableFonts = fontManager.getAllFonts()
        
        // 如果当前选择的字体不可用，选择一个默认字体
        if !availableFonts.contains(where: { $0.name == selectedFont }) {
            selectedFont = ".SF Pro Display"
        }
    }
    
    /// 显示的字体列表
    private var displayedFonts: [FontManager.FontInfo] {
        var fonts: [FontManager.FontInfo]
        
        if searchText.isEmpty {
            fonts = fontManager.getFonts(for: selectedCategory)
        } else {
            fonts = fontManager.searchFonts(query: searchText)
        }
        
        // 优先显示支持中文的字体
        return fonts.sorted { font1, font2 in
            if font1.supportsChinese && !font2.supportsChinese {
                return true
            } else if !font1.supportsChinese && font2.supportsChinese {
                return false
            } else {
                return font1.displayName < font2.displayName
            }
        }
    }
    
    private func colorToHex(_ color: Color) -> String {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        return String(format: "#%02X%02X%02X",
                     Int(red * 255),
                     Int(green * 255),
                     Int(blue * 255))
    }
}

// MARK: - 分类按钮

private struct CategoryButton: View {
    let category: FontManager.FontCategory
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                // 分类图标
                Image(systemName: categoryIcon(for: category))
                    .font(.system(size: 12, weight: .medium))
                
                Text(category.rawValue)
                    .font(Theme.Fonts.caption)
                    .fontWeight(.medium)
                
                // 字体数量
                Text("(\(categoryFontCount(for: category)))")
                    .font(Theme.Fonts.caption2)
                    .opacity(0.7)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .fill(isSelected ? Theme.Colors.brandBlue : Theme.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                            .stroke(isSelected ? Theme.Colors.brandBlue : Color.gray.opacity(0.2), lineWidth: isSelected ? 0 : 1)
                    )
            )
            .foregroundColor(isSelected ? .white : Theme.Colors.primaryText)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
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
    
    private func categoryFontCount(for category: FontManager.FontCategory) -> Int {
        return FontManager.shared.getFonts(for: category).count
    }
}

// MARK: - 增强字体按钮

private struct EnhancedFontButton: View {
    let fontInfo: FontManager.FontInfo
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        // 字体名称
                        Text(fontInfo.displayName)
                            .font(.custom(fontInfo.name, size: 14))
                            .foregroundColor(isSelected ? .white : Theme.Colors.primaryText)
                            .lineLimit(1)
                        
                        // 分类标签
                        HStack(spacing: 4) {
                            Text(fontInfo.category.rawValue)
                                .font(Theme.Fonts.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(isSelected ? .white.opacity(0.2) : Color.gray.opacity(0.1))
                                )
                                .foregroundColor(isSelected ? .white.opacity(0.9) : Theme.Colors.secondaryText)
                            
                            // 中文支持标识
                            if fontInfo.supportsChinese {
                                Text("中")
                                    .font(Theme.Fonts.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.red.opacity(isSelected ? 0.8 : 0.6))
                                    )
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 14))
                    }
                }
                
                // 预览文字
                Text(fontInfo.supportsChinese ? "预览文字" : "Preview")
                    .font(.custom(fontInfo.name, size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : Theme.Colors.secondaryText)
                    .lineLimit(1)
            }
            .padding(Theme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                    .fill(isSelected ? Theme.Colors.brandBlue : Theme.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                            .stroke(isSelected ? Theme.Colors.brandBlue : Color.gray.opacity(0.2), lineWidth: isSelected ? 0 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .opacity(fontInfo.isAvailable ? 1.0 : 0.5)
        .disabled(!fontInfo.isAvailable)
    }
}

// MARK: - 颜色按钮

private struct ColorButton: View {
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
                    .frame(width: 32, height: 32)
                
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .font(.system(size: 12, weight: .bold))
                        .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
