import UIKit

/// 字体管理器 - 提供字体检测、分类和可用性检查
class FontManager {
    
    // MARK: - 字体分类
    
    enum FontCategory: String, CaseIterable {
        case system = "系统"
        case chinese = "中文"
        case sansSerif = "无衬线"
        case serif = "衬线"
        case handwritten = "手写"
        case monospaced = "等宽"
        case display = "展示"
        case artistic = "艺术"
    }
    
    // MARK: - 字体数据结构
    
    struct FontInfo: Hashable, Identifiable {
        let id = UUID()
        let name: String
        let displayName: String
        let category: FontCategory
        let isAvailable: Bool
        let supportsChinese: Bool
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(name)
        }
        
        static func == (lhs: FontInfo, rhs: FontInfo) -> Bool {
            return lhs.name == rhs.name
        }
    }
    
    // MARK: - 单例
    
    static let shared = FontManager()
    
    // MARK: - 字体列表
    
    private lazy var allFonts: [FontInfo] = {
        return loadFontList()
    }()
    
    // MARK: - 公共接口
    
    /// 获取所有可用字体
    func getAllFonts() -> [FontInfo] {
        return allFonts.filter { $0.isAvailable }
    }
    
    /// 根据分类获取字体
    func getFonts(for category: FontCategory) -> [FontInfo] {
        return getAllFonts().filter { $0.category == category }
    }
    
    /// 获取支持中文的字体
    func getChineseFonts() -> [FontInfo] {
        return getAllFonts().filter { $0.supportsChinese }
    }
    
    /// 检查字体是否可用
    func isFontAvailable(_ fontName: String) -> Bool {
        return FontAvailabilityDetector.shared.isFontAvailable(fontName)
    }
    
    /// 搜索字体
    func searchFonts(query: String) -> [FontInfo] {
        guard !query.isEmpty else { return getAllFonts() }
        
        return getAllFonts().filter { font in
            font.displayName.localizedCaseInsensitiveContains(query) ||
            font.name.localizedCaseInsensitiveContains(query) ||
            font.category.rawValue.localizedCaseInsensitiveContains(query)
        }
    }
    
    // MARK: - 私有方法
    
    private init() {}
    
    /// 加载字体列表
    private func loadFontList() -> [FontInfo] {
        var fonts: [FontInfo] = []
        
        // 系统字体
        fonts.append(contentsOf: loadSystemFonts())
        
        // 中文字体
        fonts.append(contentsOf: loadChineseFonts())
        
        // 英文字体
        fonts.append(contentsOf: loadEnglishFonts())
        
        // 使用可用性检测器检查字体可用性和中文支持
        let detector = FontAvailabilityDetector.shared
        for i in fonts.indices {
            let isAvailable = detector.isFontAvailable(fonts[i].name)
            let supportsChinese = isAvailable ? detector.checkChineseSupport(for: fonts[i].name) : fonts[i].supportsChinese
            
            fonts[i] = FontInfo(
                name: fonts[i].name,
                displayName: fonts[i].displayName,
                category: fonts[i].category,
                isAvailable: isAvailable,
                supportsChinese: supportsChinese
            )
        }
        
        return fonts
    }
    
    /// 加载系统字体
    private func loadSystemFonts() -> [FontInfo] {
        return [
            FontInfo(name: ".SF Pro Display", displayName: "SF Pro Display", category: .system, isAvailable: false, supportsChinese: true),
            FontInfo(name: ".SF Pro Text", displayName: "SF Pro Text", category: .system, isAvailable: false, supportsChinese: true),
            FontInfo(name: ".SF Compact Display", displayName: "SF Compact", category: .system, isAvailable: false, supportsChinese: true),
            FontInfo(name: ".AppleSystemUIFont", displayName: "Apple System", category: .system, isAvailable: false, supportsChinese: true),
            FontInfo(name: "San Francisco", displayName: "San Francisco", category: .system, isAvailable: false, supportsChinese: true),
        ]
    }
    
    /// 加载中文字体
    private func loadChineseFonts() -> [FontInfo] {
        return [
            // 苹果中文字体
            FontInfo(name: "PingFang SC", displayName: "PingFang SC", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "PingFang TC", displayName: "PingFang TC", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "PingFang HK", displayName: "PingFang HK", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "Hiragino Sans GB", displayName: "Hiragino Sans", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "STHeiti", displayName: "STHeiti", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "STHeitiSC-Light", displayName: "STHeiti Light", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "STHeitiSC-Medium", displayName: "STHeiti Medium", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "Heiti SC", displayName: "Heiti SC", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "Heiti TC", displayName: "Heiti TC", category: .chinese, isAvailable: false, supportsChinese: true),
            
            // 其他中文字体
            FontInfo(name: "WenQuanYi Micro Hei", displayName: "文泉驿微米黑", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "Microsoft YaHei", displayName: "微软雅黑", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "SimHei", displayName: "黑体", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "SimSun", displayName: "宋体", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "SimKai", displayName: "楷体", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "KaiTi", displayName: "楷体", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "FangSong", displayName: "仿宋", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "FangSong_GB2312", displayName: "仿宋_GB2312", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "LiSu", displayName: "隶书", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "YouYuan", displayName: "幼圆", category: .chinese, isAvailable: false, supportsChinese: true),
            
            // 艺术中文字体
            FontInfo(name: "STKaiti", displayName: "华文楷体", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "STSong", displayName: "华文宋体", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "STFangsong", displayName: "华文仿宋", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "STXihei", displayName: "华文细黑", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "STZhongsong", displayName: "华文中宋", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "STLiti", displayName: "华文隶书", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "STXingkai", displayName: "华文行楷", category: .chinese, isAvailable: false, supportsChinese: true),
            FontInfo(name: "STXinwei", displayName: "华文新魏", category: .chinese, isAvailable: false, supportsChinese: true),
        ]
    }
    
    /// 加载英文字体
    private func loadEnglishFonts() -> [FontInfo] {
        return [
            // 无衬线字体
            FontInfo(name: "Helvetica Neue", displayName: "Helvetica Neue", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Helvetica", displayName: "Helvetica", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Arial", displayName: "Arial", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Arial Rounded MT Bold", displayName: "Arial Rounded", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Avenir", displayName: "Avenir", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Avenir Next", displayName: "Avenir Next", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Avenir Next Condensed", displayName: "Avenir Condensed", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Futura", displayName: "Futura", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Gill Sans", displayName: "Gill Sans", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Optima", displayName: "Optima", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Trebuchet MS", displayName: "Trebuchet", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Verdana", displayName: "Verdana", category: .sansSerif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Geneva", displayName: "Geneva", category: .sansSerif, isAvailable: false, supportsChinese: false),
            
            // 衬线字体
            FontInfo(name: "Times New Roman", displayName: "Times New Roman", category: .serif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Times", displayName: "Times", category: .serif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Georgia", displayName: "Georgia", category: .serif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Baskerville", displayName: "Baskerville", category: .serif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Palatino", displayName: "Palatino", category: .serif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Didot", displayName: "Didot", category: .serif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Bodoni 72", displayName: "Bodoni", category: .serif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Bodoni 72 Oldstyle", displayName: "Bodoni Oldstyle", category: .serif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Bodoni 72 Smallcaps", displayName: "Bodoni Smallcaps", category: .serif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Iowan Old Style", displayName: "Iowan", category: .serif, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Seravek", displayName: "Seravek", category: .serif, isAvailable: false, supportsChinese: false),
            
            // 等宽字体
            FontInfo(name: "Courier New", displayName: "Courier New", category: .monospaced, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Courier", displayName: "Courier", category: .monospaced, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Menlo", displayName: "Menlo", category: .monospaced, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Monaco", displayName: "Monaco", category: .monospaced, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Consolas", displayName: "Consolas", category: .monospaced, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Andale Mono", displayName: "Andale Mono", category: .monospaced, isAvailable: false, supportsChinese: false),
            
            // 手写字体
            FontInfo(name: "Marker Felt", displayName: "Marker Felt", category: .handwritten, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Bradley Hand", displayName: "Bradley Hand", category: .handwritten, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Noteworthy", displayName: "Noteworthy", category: .handwritten, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Chalkduster", displayName: "Chalkduster", category: .handwritten, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Snell Roundhand", displayName: "Snell Roundhand", category: .handwritten, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Zapfino", displayName: "Zapfino", category: .handwritten, isAvailable: false, supportsChinese: false),
            FontInfo(name: "American Typewriter", displayName: "American Typewriter", category: .handwritten, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Avenir Next Condensed", displayName: "Avenir Condensed", category: .handwritten, isAvailable: false, supportsChinese: false),
            
            // 艺术字体
            FontInfo(name: "Papyrus", displayName: "Papyrus", category: .artistic, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Copperplate", displayName: "Copperplate", category: .artistic, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Rockwell", displayName: "Rockwell", category: .artistic, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Impact", displayName: "Impact", category: .artistic, isAvailable: false, supportsChinese: false),
            
            // 展示字体
            FontInfo(name: "Damascus", displayName: "Damascus", category: .display, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Farah", displayName: "Farah", category: .display, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Kefa", displayName: "Kefa", category: .display, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Savoye LET", displayName: "Savoye", category: .display, isAvailable: false, supportsChinese: false),
            FontInfo(name: "Zapfino", displayName: "Zapfino", category: .display, isAvailable: false, supportsChinese: false),
        ]
    }
}

// MARK: - 扩展：字体可用性检测

extension FontManager {
    
    /// 检查字体是否支持中文字符
    func checkChineseSupport(for fontName: String) -> Bool {
        return FontAvailabilityDetector.shared.checkChineseSupport(for: fontName)
    }
    
    /// 获取系统所有可用字体名称
    func getSystemFontNames() -> [String] {
        return UIFont.familyNames.sorted()
    }
    
    /// 获取指定字体族的所有字体名称
    func getFontNames(for familyName: String) -> [String] {
        return UIFont.fontNames(forFamilyName: familyName).sorted()
    }
}