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
    
    // 键盘调试状态
    @State private var keyboardHeight: CGFloat = 0
    @State private var firstResponderStatus: String = "未知"
    
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
                    editingText = text
                    textFieldPosition = position
                    setupKeyboardNotifications()
                }
                .onDisappear {
                    removeKeyboardNotifications()
                }
                .onSubmit {
                    createText()
                }
                .onTapGesture {
                    // 点击输入框内部时不处理，避免与背景手势冲突
                    checkFirstResponderStatus()
                }
            }
        }
        .gesture(
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
    
    // MARK: - 键盘调试方法
    
    private func setupKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { _ in
            checkFirstResponderStatus()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            keyboardHeight = 0
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            checkFirstResponderStatus()
        }
    }
    
    private func removeKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
    }
    
    private func checkFirstResponderStatus() {
        // 检查当前第一响应者
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            if let firstResponder = findFirstResponder(in: window) {
                let className = String(describing: type(of: firstResponder))
                firstResponderStatus = "第一响应者: \(className)"
            } else {
                firstResponderStatus = "无第一响应者"
            }
        }
    }
    
    private func findFirstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder {
            return view
        }
        
        for subview in view.subviews {
            if let responder = findFirstResponder(in: subview) {
                return responder
            }
        }
        
        return nil
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