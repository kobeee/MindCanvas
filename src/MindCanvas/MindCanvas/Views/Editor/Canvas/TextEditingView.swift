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
                    print("🟢 [TextEditingView] TextField onAppear - 位置: \(textFieldPosition)")
                    editingText = text
                    textFieldPosition = position
                    setupKeyboardNotifications()
                }
                .onDisappear {
                    print("🔴 [TextEditingView] TextField onDisappear")
                    removeKeyboardNotifications()
                }
                .onSubmit {
                    print("⌨️ [TextEditingView] onSubmit 被调用 - 文本: '\(editingText)'")
                    createText()
                }
                .onTapGesture {
                    print("👆 [TextEditingView] TextField 被点击")
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
                        print("👆 [TextEditingView] 画布点击 - 位置: \(value.location)")
                        position = value.location
                        textFieldPosition = value.location
                        editingText = ""
                        isEditing = true
                        print("⌨️ [TextEditingView] 激活文字编辑模式")
                    }
                }
        )
        .onAppear {
            print("🟢 [TextEditingView] 文字编辑视图出现")
        }
    }
    
    private func createText() {
        print("⌨️ [TextEditingView] createText 被调用 - 文本: '\(editingText)'")
        guard !editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ [TextEditingView] 文本为空，取消创建")
            isEditing = false
            return
        }
        
        onTextCreated?(position, editingText)
        isEditing = false
        text = ""
        print("✅ [TextEditingView] 文字创建完成")
    }
    
    // MARK: - 键盘调试方法
    
    private func setupKeyboardNotifications() {
        print("⌨️ [TextEditingView] 设置键盘通知监听")
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            print("⌨️ [TextEditingView] 键盘即将显示通知")
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height
                print("⌨️ [TextEditingView] 键盘高度: \(frame.height)")
            }
            if let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
                print("⌨️ [TextEditingView] 键盘动画时长: \(duration)")
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidShowNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("⌨️ [TextEditingView] 键盘已显示通知")
            checkFirstResponderStatus()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { notification in
            print("⌨️ [TextEditingView] 键盘即将隐藏通知")
            keyboardHeight = 0
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardDidHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("⌨️ [TextEditingView] 键盘已隐藏通知")
            checkFirstResponderStatus()
        }
    }
    
    private func removeKeyboardNotifications() {
        print("⌨️ [TextEditingView] 移除键盘通知监听")
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
                print("⌨️ [TextEditingView] \(firstResponderStatus)")
                
                // 如果是 UITextField 或 UITextView，输出详细信息
                if let textField = firstResponder as? UITextField {
                    print("⌨️ [TextEditingView] UITextField 详情 - 文本: '\(textField.text ?? "")', 是否编辑中: \(textField.isEditing)")
                } else if let textView = firstResponder as? UITextView {
                    print("⌨️ [TextEditingView] UITextView 详情 - 文本: '\(textView.text)', 是否编辑中: \(textView.isEditable)")
                }
            } else {
                firstResponderStatus = "无第一响应者"
                print("⌨️ [TextEditingView] 当前无第一响应者")
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