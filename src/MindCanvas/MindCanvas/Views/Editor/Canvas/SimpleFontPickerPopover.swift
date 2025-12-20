import SwiftUI

/// 简化版字体选择弹窗
/// 直接操作 CanvasStateManager，无中间状态
struct SimpleFontPickerPopover: View {
    let stateManager: CanvasStateManager
    let onConfirm: () -> Void

    // 本地预览状态（仅用于实时预览，不影响全局）
    @State private var previewFontName: String = ".SF Pro Display"
    @State private var previewFontSize: CGFloat = 24
    @State private var previewTextColor: Color = .black

    // 字体分类
    @State private var selectedCategory: FontCategory = .system
    @State private var searchText: String = ""

    // 预设颜色
    private let presetColors: [Color] = [
        .black, .white,
        Color(hex: "#FF3B30") ?? .red,      // iOS红
        Color(hex: "#FF9500") ?? .orange,   // iOS橙
        Color(hex: "#FFCC00") ?? .yellow,   // iOS黄
        Color(hex: "#34C759") ?? .green,    // iOS绿
        Color(hex: "#007AFF") ?? .blue,     // iOS蓝
        Color(hex: "#5856D6") ?? .purple,   // iOS紫
        Color(hex: "#AF52DE") ?? .purple,   // iOS浅紫
        Color(hex: "#FF2D55") ?? .pink,     // iOS粉
        Color(hex: "#A2845E") ?? .brown,    // 棕色
        Color(hex: "#8E8E93") ?? .gray,     // iOS灰
    ]

    // 字体大小选项
    private let fontSizes: [CGFloat] = [12, 16, 20, 24, 32, 48, 64]

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Button("取消") {
                    onConfirm()
                }
                .foregroundColor(Theme.Colors.secondaryText)

                Spacer()

                Text("文字设置")
                    .font(Theme.Fonts.headline)

                Spacer()

                Button("完成") {
                    // 确认时同步到全局状态
                    stateManager.setTextFontName(previewFontName)
                    stateManager.setTextFontSize(previewFontSize)
                    stateManager.setTextColor(previewTextColor.toHex() ?? "#000000")
                    onConfirm()
                }
                .foregroundColor(Theme.Colors.brandBlue)
                .fontWeight(.semibold)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // 预览区域
                    previewSection

                    // 字体分类
                    categorySection

                    // 字体列表
                    fontListSection

                    // 字体大小
                    fontSizeSection

                    // 颜色选择
                    colorSection
                }
                .padding()
            }
        }
        .frame(width: 380, height: 580)
        .background(Theme.Colors.appBackground)
        .onAppear {
            // 初始化预览状态
            previewFontName = stateManager.textFontName ?? ".SF Pro Display"
            previewFontSize = stateManager.textFontSize
            previewTextColor = Color(hex: stateManager.textColor) ?? .black
        }
    }

    // MARK: - 预览区域

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("预览")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.secondaryText)

            ZStack {
                RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                    .fill(Theme.Colors.cardBackground)

                Text("预览文字 AaBbCc 123")
                    .font(.custom(previewFontName, size: min(previewFontSize, 32)))
                    .foregroundColor(previewTextColor)
            }
            .frame(height: 80)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - 分类选择

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("分类")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.secondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(FontCategory.allCases, id: \.self) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            Text(category.displayName)
                                .font(Theme.Fonts.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedCategory == category
                                              ? Theme.Colors.brandBlue
                                              : Theme.Colors.cardBackground)
                                )
                                .foregroundColor(selectedCategory == category ? .white : Theme.Colors.primaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - 字体列表

    private var fontListSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("字体")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.secondaryText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(filteredFonts, id: \.name) { font in
                    Button {
                        previewFontName = font.name
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(font.displayName)
                                    .font(.custom(font.name, size: 13))
                                    .lineLimit(1)

                                if font.supportsChinese {
                                    Text("支持中文")
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.red.opacity(0.15))
                                        .foregroundColor(.red)
                                        .cornerRadius(2)
                                }
                            }

                            Spacer()

                            if previewFontName == font.name {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.Colors.brandBlue)
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(previewFontName == font.name
                                      ? Theme.Colors.brandBlue.opacity(0.1)
                                      : Theme.Colors.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(previewFontName == font.name
                                        ? Theme.Colors.brandBlue
                                        : Color.gray.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.Colors.primaryText)
                }
            }
        }
    }

    // MARK: - 字体大小

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text("大小")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.secondaryText)

                Spacer()

                Text("\(Int(previewFontSize)) pt")
                    .font(Theme.Fonts.bodyBold)
                    .foregroundColor(Theme.Colors.brandBlue)
            }

            Slider(value: $previewFontSize, in: 12...72, step: 1)
                .tint(Theme.Colors.brandBlue)

            HStack(spacing: 8) {
                ForEach(fontSizes, id: \.self) { size in
                    Button {
                        previewFontSize = size
                    } label: {
                        Text("\(Int(size))")
                            .font(Theme.Fonts.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(previewFontSize == size
                                          ? Theme.Colors.brandBlue
                                          : Theme.Colors.cardBackground)
                            )
                            .foregroundColor(previewFontSize == size ? .white : Theme.Colors.primaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 颜色选择

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("颜色")
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.secondaryText)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                ForEach(presetColors, id: \.self) { color in
                    Button {
                        previewTextColor = color
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(color)
                                .frame(width: 36, height: 36)

                            if previewTextColor == color {
                                Image(systemName: "checkmark")
                                    .foregroundColor(color == .white ? .black : .white)
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(previewTextColor == color
                                        ? Theme.Colors.brandBlue
                                        : Color.gray.opacity(0.3), lineWidth: previewTextColor == color ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - 过滤后的字体列表

    private var filteredFonts: [FontInfo] {
        let fonts = selectedCategory.fonts
        if searchText.isEmpty {
            return fonts
        }
        return fonts.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - 字体分类

enum FontCategory: CaseIterable {
    case system
    case chinese
    case sansSerif
    case serif
    case handwritten
    case monospaced

    var displayName: String {
        switch self {
        case .system: return "系统"
        case .chinese: return "中文"
        case .sansSerif: return "无衬线"
        case .serif: return "衬线"
        case .handwritten: return "手写"
        case .monospaced: return "等宽"
        }
    }

    var fonts: [FontInfo] {
        switch self {
        case .system:
            return [
                FontInfo(name: ".SF Pro Display", displayName: "SF Pro", supportsChinese: false),
                FontInfo(name: ".SF Pro Rounded", displayName: "SF Rounded", supportsChinese: false),
                FontInfo(name: ".SF Compact Display", displayName: "SF Compact", supportsChinese: false),
            ]
        case .chinese:
            return [
                FontInfo(name: "PingFang SC", displayName: "苹方-简", supportsChinese: true),
                FontInfo(name: "PingFang TC", displayName: "苹方-繁", supportsChinese: true),
                FontInfo(name: "Heiti SC", displayName: "黑体-简", supportsChinese: true),
                FontInfo(name: "STHeitiSC-Light", displayName: "华文黑体", supportsChinese: true),
                FontInfo(name: "STSongti-SC-Regular", displayName: "华文宋体", supportsChinese: true),
                FontInfo(name: "STKaiti", displayName: "华文楷体", supportsChinese: true),
                FontInfo(name: "STFangsong", displayName: "华文仿宋", supportsChinese: true),
            ]
        case .sansSerif:
            return [
                FontInfo(name: "Helvetica Neue", displayName: "Helvetica Neue", supportsChinese: false),
                FontInfo(name: "Arial", displayName: "Arial", supportsChinese: false),
                FontInfo(name: "Avenir Next", displayName: "Avenir Next", supportsChinese: false),
                FontInfo(name: "Futura", displayName: "Futura", supportsChinese: false),
                FontInfo(name: "Gill Sans", displayName: "Gill Sans", supportsChinese: false),
            ]
        case .serif:
            return [
                FontInfo(name: "Times New Roman", displayName: "Times New Roman", supportsChinese: false),
                FontInfo(name: "Georgia", displayName: "Georgia", supportsChinese: false),
                FontInfo(name: "Baskerville", displayName: "Baskerville", supportsChinese: false),
                FontInfo(name: "Palatino", displayName: "Palatino", supportsChinese: false),
                FontInfo(name: "Didot", displayName: "Didot", supportsChinese: false),
            ]
        case .handwritten:
            return [
                FontInfo(name: "Bradley Hand", displayName: "Bradley Hand", supportsChinese: false),
                FontInfo(name: "Marker Felt", displayName: "Marker Felt", supportsChinese: false),
                FontInfo(name: "Noteworthy", displayName: "Noteworthy", supportsChinese: false),
                FontInfo(name: "Snell Roundhand", displayName: "Snell Roundhand", supportsChinese: false),
                FontInfo(name: "Zapfino", displayName: "Zapfino", supportsChinese: false),
            ]
        case .monospaced:
            return [
                FontInfo(name: "Menlo", displayName: "Menlo", supportsChinese: false),
                FontInfo(name: "Monaco", displayName: "Monaco", supportsChinese: false),
                FontInfo(name: "Courier New", displayName: "Courier New", supportsChinese: false),
                FontInfo(name: "SF Mono", displayName: "SF Mono", supportsChinese: false),
            ]
        }
    }
}

// MARK: - 字体信息

struct FontInfo {
    let name: String
    let displayName: String
    let supportsChinese: Bool
}