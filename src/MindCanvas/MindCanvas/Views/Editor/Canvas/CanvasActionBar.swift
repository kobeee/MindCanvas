import SwiftUI

/// 左上角功能键组件
/// 提供撤销、恢复、复制、清屏等操作
struct CanvasActionBar: View {
    var canUndo: Bool
    var canRedo: Bool
    var hasSelection: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onDuplicate: () -> Void
    var onClear: () -> Void
    
    @State private var showClearConfirmation = false
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ActionButton(
                icon: "arrow.uturn.backward",
                enabled: canUndo,
                action: onUndo
            )
            .help("撤销")
            
            ActionButton(
                icon: "arrow.uturn.forward",
                enabled: canRedo,
                action: onRedo
            )
            .help("恢复")
            
            ActionButton(
                icon: "doc.on.doc",
                enabled: hasSelection,
                action: onDuplicate
            )
            .help("复制")
            
            ActionButton(
                icon: "trash",
                enabled: true,
                isDestructive: true,
                action: {
                    showClearConfirmation = true
                }
            )
            .help("清屏")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .alert("确认清屏", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) { }
            Button("清屏", role: .destructive) {
                onClear()
            }
        } message: {
            Text("此操作将清除画布上的所有内容，无法撤销。")
        }
    }
}

// MARK: - 动作按钮

private struct ActionButton: View {
    let icon: String
    let enabled: Bool
    var isDestructive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(buttonColor)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
    
    private var buttonColor: Color {
        if !enabled {
            return Theme.Colors.secondaryText.opacity(0.4)
        }
        if isDestructive {
            return Theme.Colors.destructive
        }
        return Theme.Colors.secondaryText
    }
}

// MARK: - Preview

#Preview {
    VStack {
        HStack {
            CanvasActionBar(
                canUndo: true,
                canRedo: false,
                hasSelection: true,
                onUndo: { print("Undo") },
                onRedo: { print("Redo") },
                onDuplicate: { print("Duplicate") },
                onClear: { print("Clear") }
            )
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.top, 16)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.1))
}

