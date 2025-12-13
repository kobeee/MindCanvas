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
                .onAppear {
                    editingText = text
                    textFieldPosition = position
                }
                .onTapGesture {
                    // 点击输入框外部时完成输入
                    createText()
                }
            }
        }
        . gesture(
            // 点击画布时创建文字输入框
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    if !isEditing {
                        position = value.location
                        textFieldPosition = value.location
                        editingText = ""
                        isEditing = true
                    }
                }
        )
    }
    
    private func createText() {
        guard !editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isEditing = false
            return
        }
        
        onTextCreated?(position, editingText)
        isEditing = false
        text = ""
    }
}

/// 文字显示视图
/// 用于显示已创建的文字
struct TextDisplayView: View {
    let textLayer: TextLayerNode
    
    var body: some View {
        Text(textLayer.text)
            .font(
                textLayer.fontName != nil 
                    ? .custom(textLayer.fontName!, size: textLayer.fontSize)
                    : .system(size: textLayer.fontSize)
            )
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