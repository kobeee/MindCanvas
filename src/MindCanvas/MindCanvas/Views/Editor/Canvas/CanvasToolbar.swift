import SwiftUI

/// 底部工具栏
/// 参考 Figma/Canva 的工具栏设计，工具切换入口
struct CanvasToolbar: View {
    @Bindable var stateManager: CanvasStateManager
    var onImageImport: () -> Void
    var onShapeSelected: ((ShapeType) -> Void)?  // 形状选择回调
    var onToolChanged: ((CanvasTool) -> Void)?   // 工具切换回调
    
    // 画笔设置
    @Binding var penColor: Color
    @Binding var penWidth: CGFloat
    
    // 形状选择器弹出状态
    @State private var showShapePicker = false
    @State private var showPenSettings = false
    @State private var showFontSettings = false
    
    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(CanvasTool.mainToolbarTools, id: \.self) { tool in
                switch tool {
                case .rectangle:
                    // 图形工具特殊处理 - 弹出选择器
                    ShapeToolButton(
                        tool: tool,
                        isSelected: stateManager.currentTool == tool,
                        showPicker: $showShapePicker,
                        onShapeSelected: { shape in
                            showShapePicker = false
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                if shape.isLineType {
                                    stateManager.currentTool = .arrow
                                } else {
                                    stateManager.currentTool = .rectangle
                                }
                                onToolChanged?(stateManager.currentTool)
                            }
                            onShapeSelected?(shape)
                        }
                    )
                    
                case .pen:
                    // 画笔工具特殊处理 - 弹出设置面板
                    PenToolButton(
                        tool: tool,
                        isSelected: stateManager.currentTool == tool,
                        showSettings: $showPenSettings,
                        onSelect: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                stateManager.currentTool = tool
                                onToolChanged?(tool)
                            }
                        },
                        penColor: $penColor,
                        penWidth: $penWidth
                    )
                    
                case .text:
                    // 文字工具 - 点击选中，长按/再次点击显示设置
                    TextToolButtonView(
                        tool: tool,
                        isSelected: stateManager.currentTool == tool,
                        showSettings: $showFontSettings,
                        onSelect: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                stateManager.currentTool = tool
                                onToolChanged?(tool)
                            }
                        },
                        stateManager: stateManager
                    )
                    
                default:
                    // 其他工具 - 普通按钮
                    ToolButton(
                        tool: tool,
                        isSelected: stateManager.currentTool == tool,
                        action: {
                            if tool == .image {
                                onImageImport()
                            } else if stateManager.currentTool != tool {
                                // 切换工具时清除选中状态
                                stateManager.clearSelection()

                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    stateManager.currentTool = tool
                                    onToolChanged?(tool)
                                }
                            }
                        }
                    )
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Shapes.cardCornerRadius))
        .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}

// MARK: - 工具按钮

private struct ToolButton: View {
    let tool: CanvasTool
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: tool.iconName)
                .font(.system(size: 22))
                .foregroundColor(isSelected ? .white : Theme.Colors.secondaryText)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .fill(isSelected ? Theme.Colors.brandBlue : Color.clear)
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .help(tool.displayName)
    }
}

// MARK: - 形状工具按钮（带弹出选择器）

private struct ShapeToolButton: View {
    let tool: CanvasTool
    let isSelected: Bool
    @Binding var showPicker: Bool
    let onShapeSelected: (ShapeType) -> Void

    var body: some View {
        Button {
            showPicker.toggle()
        } label: {
            Image(systemName: tool.iconName)
                .font(.system(size: 22))
                .foregroundColor(isSelected ? .white : Theme.Colors.secondaryText)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .fill(isSelected ? Theme.Colors.brandBlue : Color.clear)
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .help(tool.displayName)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            ShapePickerPopover(shapes: ShapeType.popoverShapes) { shape in
                onShapeSelected(shape)
            }
        }
    }
}

// MARK: - 画笔工具按钮（带弹出设置）

private struct PenToolButton: View {
    let tool: CanvasTool
    let isSelected: Bool
    @Binding var showSettings: Bool
    let onSelect: () -> Void

    // 绑定画笔属性
    @Binding var penColor: Color
    @Binding var penWidth: CGFloat

    var body: some View {
        Button {
            if isSelected {
                // 已选中时，点击弹出设置
                showSettings.toggle()
            } else {
                // 未选中时，先选中工具
                onSelect()
            }
        } label: {
            Image(systemName: tool.iconName)
                .font(.system(size: 22))
                .foregroundColor(isSelected ? .white : Theme.Colors.secondaryText)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .fill(isSelected ? Theme.Colors.brandBlue : Color.clear)
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .help(tool.displayName)
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            PenSettingsPopover(
                penColor: $penColor,
                penWidth: $penWidth
            )
        }
    }
}

// MARK: - 文字工具按钮（带弹出设置面板）

private struct TextToolButtonView: View {
    let tool: CanvasTool
    let isSelected: Bool
    @Binding var showSettings: Bool
    let onSelect: () -> Void
    let stateManager: CanvasStateManager

    var body: some View {
        Button {
            if isSelected {
                // 已选中时，点击弹出设置
                showSettings.toggle()
            } else {
                // 未选中时，先选中工具
                onSelect()
            }
        } label: {
            Image(systemName: tool.iconName)
                .font(.system(size: 22))
                .foregroundColor(isSelected ? .white : Theme.Colors.secondaryText)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Shapes.buttonCornerRadius)
                        .fill(isSelected ? Theme.Colors.brandBlue : Color.clear)
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
        .help(tool.displayName)
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            SimpleFontPickerPopover(stateManager: stateManager, onConfirm: {
                showSettings = false
            })
        }
    }
}



// MARK: - Preview

#Preview {
    VStack {
        Spacer()
        CanvasToolbar(
            stateManager: CanvasStateManager(),
            onImageImport: { print("Import image") },
            onShapeSelected: { shape in print("Selected shape: \(shape.displayName)") },
            penColor: .constant(.black),
            penWidth: .constant(2.0)
        )
        .padding()
    }
    .background(Color.gray.opacity(0.1))
}