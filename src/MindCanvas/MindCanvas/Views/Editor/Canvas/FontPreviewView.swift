import SwiftUI

/// 字体预览组件
/// 提供丰富的字体预览效果，支持中英文混合预览
struct FontPreviewView: View {
    let fontInfo: FontManager.FontInfo
    let fontSize: CGFloat
    let textColor: Color
    
    private let previewTexts = [
        "中文预览文字效果",
        "English Preview Text",
        "1234567890!@#$%",
        "AaBbCcDdEeFfGg",
        "字体设计 Typography"
    ]
    
    @State private var currentPreviewIndex = 0
    
    var body: some View {
        VStack(spacing: 12) {
            // 主预览区域
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                
                VStack(spacing: 8) {
                    Text(currentPreviewText)
                        .font(.custom(fontInfo.name, size: fontSize))
                        .foregroundColor(textColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    
                    // 字体信息
                    HStack(spacing: 12) {
                        Label(fontInfo.displayName, systemImage: "textformat")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Label(fontInfo.category.rawValue, systemImage: "folder")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if fontInfo.supportsChinese {
                            Label("中文", systemImage: "character.textbox")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .frame(height: 120)
            
            // 预览文本选择器
            HStack {
                ForEach(0..<previewTexts.count, id: \.self) { index in
                    Circle()
                        .fill(currentPreviewIndex == index ? Theme.Colors.brandBlue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentPreviewIndex = index
                            }
                        }
                }
            }
            
            // 自动切换预览
            .onAppear {
                startAutoPreview()
            }
        }
    }
    
    private var currentPreviewText: String {
        return previewTexts[currentPreviewIndex]
    }
    
    private func startAutoPreview() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentPreviewIndex = (currentPreviewIndex + 1) % previewTexts.count
            }
        }
    }
}

/// 字体对比预览视图
/// 用于对比多个字体的效果
struct FontComparisonView: View {
    let fonts: [FontManager.FontInfo]
    let testText: String
    let fontSize: CGFloat
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(fonts, id: \.name) { fontInfo in
                    FontComparisonRow(
                        fontInfo: fontInfo,
                        testText: testText,
                        fontSize: fontSize
                    )
                }
            }
            .padding()
        }
    }
}

private struct FontComparisonRow: View {
    let fontInfo: FontManager.FontInfo
    let testText: String
    let fontSize: CGFloat
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 字体信息头部
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fontInfo.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Text(fontInfo.category.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(4)
                        
                        if fontInfo.supportsChinese {
                            Text("支持中文")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                // 可用性状态
                Image(systemName: fontInfo.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(fontInfo.isAvailable ? .green : .red)
                    .font(.title3)
            }
            
            // 预览区域
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.05))
                .overlay(
                    Text(testText)
                        .font(.custom(fontInfo.name, size: fontSize))
                        .foregroundColor(fontInfo.isAvailable ? .primary : .secondary)
                        .padding()
                        .multilineTextAlignment(.center)
                )
                .opacity(fontInfo.isAvailable ? 1.0 : 0.6)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

#Preview {
    VStack {
        FontPreviewView(
            fontInfo: FontManager.FontInfo(
                name: "PingFang SC",
                displayName: "PingFang SC",
                category: .chinese,
                isAvailable: true,
                supportsChinese: true
            ),
            fontSize: 24,
            textColor: .blue
        )
        .padding()
    }
}