import UIKit

/// 字体可用性检测工具
/// 用于检测iOS系统中实际可用的字体
class FontAvailabilityDetector {
    
    static let shared = FontAvailabilityDetector()
    
    private init() {}
    
    /// 检测所有系统可用字体
    func detectAvailableFonts() -> [String: Bool] {
        var availability: [String: Bool] = [:]
        
        // 需要检测的字体列表
        let fontsToCheck = [
            // 系统字体
            ".SF Pro Display",
            ".SF Pro Text",
            ".SF Compact Display",
            ".AppleSystemUIFont",
            "San Francisco",
            
            // 中文字体
            "PingFang SC",
            "PingFang TC",
            "PingFang HK",
            "Hiragino Sans GB",
            "STHeiti",
            "STHeitiSC-Light",
            "STHeitiSC-Medium",
            "Heiti SC",
            "Heiti TC",
            "STKaiti",
            "STSong",
            "STFangsong",
            "STXihei",
            "STZhongsong",
            "STLiti",
            "STXingkai",
            "STXinwei",
            "KaiTi",
            "FangSong",
            "FangSong_GB2312",
            "LiSu",
            "YouYuan",
            "SimHei",
            "SimSun",
            "SimKai",
            
            // 英文字体
            "Helvetica Neue",
            "Helvetica",
            "Arial",
            "Arial Rounded MT Bold",
            "Avenir",
            "Avenir Next",
            "Avenir Next Condensed",
            "Times New Roman",
            "Times",
            "Georgia",
            "Baskerville",
            "Palatino",
            "Didot",
            "Bodoni 72",
            "Bodoni 72 Oldstyle",
            "Bodoni 72 Smallcaps",
            "Iowan Old Style",
            "Seravek",
            "Courier New",
            "Courier",
            "Menlo",
            "Monaco",
            "Consolas",
            "Andale Mono",
            "Marker Felt",
            "Bradley Hand",
            "Noteworthy",
            "Chalkduster",
            "Snell Roundhand",
            "Zapfino",
            "American Typewriter",
            "Papyrus",
            "Copperplate",
            "Rockwell",
            "Impact",
            "Damascus",
            "Farah",
            "Kefa",
            "Savoye LET",
            "Verdana",
            "Geneva",
            "Trebuchet MS",
            "Futura",
            "Gill Sans",
            "Optima"
        ]
        
        for fontName in fontsToCheck {
            availability[fontName] = isFontAvailable(fontName)
        }
        
        return availability
    }
    
    /// 检查单个字体是否可用
    func isFontAvailable(_ fontName: String) -> Bool {
        return UIFont(name: fontName, size: 12) != nil
    }
    
    /// 检查字体是否支持中文
    func checkChineseSupport(for fontName: String) -> Bool {
        guard let font = UIFont(name: fontName, size: 12) else { return false }
        
        let testString = "中文测试"
        let attributes = [NSAttributedString.Key.font: font]
        let attributedString = NSAttributedString(string: testString, attributes: attributes)
        
        let boundingRect = attributedString.boundingRect(
            with: CGSize(width: 100, height: 100),
            options: .usesLineFragmentOrigin,
            context: nil
        )
        
        return boundingRect.width > 0
    }
    
    /// 获取字体族的详细信息
    func getFontFamilyDetails() -> [(familyName: String, fontNames: [String])] {
        let familyNames = UIFont.familyNames.sorted()
        var details: [(familyName: String, fontNames: [String])] = []
        
        for familyName in familyNames {
            let fontNames = UIFont.fontNames(forFamilyName: familyName).sorted()
            details.append((familyName: familyName, fontNames: fontNames))
        }
        
        return details
    }
    
    /// 生成字体可用性报告
    func generateAvailabilityReport() -> String {
        var report = "=== 字体可用性检测报告 ===\n"
        report += "检测时间: \(Date())\n\n"
        
        let availability = detectAvailableFonts()
        
        report += "可用字体统计:\n"
        report += "- 总检测字体数: \(availability.count)\n"
        report += "- 可用字体数: \(availability.values.filter { $0 }.count)\n"
        report += "- 不可用字体数: \(availability.values.filter { !$0 }.count)\n\n"
        
        report += "按分类统计:\n"
        
        let categories = [
            ("系统字体", [".SF Pro Display", ".SF Pro Text", ".SF Compact Display", ".AppleSystemUIFont", "San Francisco"]),
            ("中文字体", ["PingFang SC", "PingFang TC", "PingFang HK", "Hiragino Sans GB", "STHeiti", "Heiti SC", "Heiti TC", "STKaiti", "STSong", "STFangsong"]),
            ("无衬线字体", ["Helvetica Neue", "Helvetica", "Arial", "Avenir", "Avenir Next", "Futura", "Verdana"]),
            ("衬线字体", ["Times New Roman", "Times", "Georgia", "Baskerville", "Palatino", "Didot"]),
            ("等宽字体", ["Courier New", "Courier", "Menlo", "Monaco", "Consolas"]),
            ("手写字体", ["Marker Felt", "Bradley Hand", "Noteworthy", "Chalkduster", "Snell Roundhand"]),
            ("艺术字体", ["Papyrus", "Copperplate", "Rockwell", "Impact", "Zapfino"])
        ]
        
        for (categoryName, fontNames) in categories {
            let availableCount = fontNames.filter { availability[$0] == true }.count
            let totalCount = fontNames.count
            report += "- \(categoryName): \(availableCount)/\(totalCount) 可用\n"
        }
        
        report += "\n详细可用性列表:\n"
        for (fontName, isAvailable) in availability.sorted(by: { $0.key < $1.key }) {
            let status = isAvailable ? "✅" : "❌"
            report += "\(status) \(fontName)\n"
        }
        
        report += "\n=== 字体族详细信息 ===\n"
        let familyDetails = getFontFamilyDetails()
        for detail in familyDetails {
            report += "\n\(detail.familyName) (\(detail.fontNames.count) 个字体):\n"
            for fontName in detail.fontNames {
                let chineseSupport = checkChineseSupport(for: fontName) ? " [中文]" : ""
                report += "  - \(fontName)\(chineseSupport)\n"
            }
        }
        
        return report
    }
}