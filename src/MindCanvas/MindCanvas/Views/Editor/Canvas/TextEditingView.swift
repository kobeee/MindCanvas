import SwiftUI

/// 文字编辑视图
/// 处理文字的输入和编辑
struct TextEditingView: View {
    @Binding var isEditing: Bool
    @Binding var position: CGPoint
    @Binding var text: String
    let fontSize: CGFloat
    let color: Color
    let onTextCreated: ((CGPoint, String) -> Void)?
    
    @State private var editingText: String = ""
    @State private var textFieldPosition: CGPoint = .zero
    
    var body: some View {
        ZStack {
            // 透明背景层，用于捕获点击事件
            if isEditing {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 点击背景时完成文字输入
                        createText()
                    }
            }
            
            // 文字输入框
            if isEditing {
                TextField("输入文字", text: $editingText, onCommit: {
                    createText()
                })
                .font(.system(size: fontSize))
                .foregroundColor(color)
                .position(textFieldPosition)
                .textFieldStyle(.plain)
                .background(Color.clear)
                .padding(8)
                .background(Color.white.opacity(0.9))
                .cornerRadius(4)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                .onAppear {
                    print("🔧 [TextEditingView] 文字输入框出现，位置: \(textFieldPosition)")
                    editingText = text
                    textFieldPosition = position
                }
                .onSubmit {
                    createText()
                }
                .onTapGesture {
                    // 点击输入框内部时不处理，避免与背景手势冲突
                }
            }
        }
        .gesture(
            // 点击画布时创建文字输入框
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    print("🔧 [TextEditingView] 画布点击，位置: \(value.location)")
                    if !isEditing {
                        position = value.location
                        textFieldPosition = value.location
                        editingText = ""
                        isEditing = true
                        print("🔧 [TextEditingView] 开始编辑文字: \(value.location)")
                    }
                }
        )
        .onAppear {
            print("🔧 [TextEditingView] 文字编辑视图出现")
        }
    }
    
    private func createText() {
        print("🔧 [TextEditingView] 创建文字: '\(editingText)' 在位置: \(position)")
        guard !editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("🔧 [TextEditingView] 文字为空，取消创建")
            isEditing = false
            return
        }
        
        onTextCreated?(position, editingText)
        isEditing = false
        text = ""
        print("🔧 [TextEditingView] 文字创建完成")
    }
}

/// 文字显示视图
/// 用于显示已创建的文字
struct TextDisplayView: View {
    let textLayer: TextLayerNode
    
    var body: some View {
        Text(textLayer.text)
            .font(.custom(textLayer.fontName, size: textLayer.fontSize))
            .foregroundColor(Color.fromHex(textLayer.color) ?? .black)
            .position(textLayer.position)
            .multilineTextAlignment(.center)
    }
}

#Preview {
    ZStack {
        TextDisplayView(
            textLayer: TextLayerNode(
                position: CGPoint(x: 100, y: 100),
                text: "示例文字",
                fontSize: 20,
                color: "#007AFF"
            )
        )
        
        TextDisplayView(
            textLayer: TextLayerNode(
                position: CGPoint(x: 200, y: 200),
                text: "Custom Font",
                fontSize: 24,
                color: "#FF3B30",
                fontName: "Arial"
            )
        )
    }
    .frame(width: 300, height: 300)
    .border(Color.gray)
}