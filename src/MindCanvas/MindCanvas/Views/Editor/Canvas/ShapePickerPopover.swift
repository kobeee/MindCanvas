import SwiftUI

/// 形状选择弹出框
struct ShapePickerPopover: View {
    let shapes: [ShapeType]
    let onShapeSelected: (ShapeType) -> Void
    @Environment(\.dismiss) private var dismiss

    private var lineShapes: [ShapeType] {
        shapes.filter { $0.isLineType }
    }

    private var basicShapes: [ShapeType] {
        shapes.filter { !$0.isLineType }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !lineShapes.isEmpty {
                HStack(spacing: 12) {
                    ForEach(lineShapes) { shape in
                        ShapePickerButton(shape: shape) {
                            onShapeSelected(shape)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                Divider()
                    .padding(.horizontal, 12)
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(basicShapes) { shape in
                    ShapePickerButton(shape: shape) {
                        onShapeSelected(shape)
                        dismiss()
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 200)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 8)
        )
        .presentationCompactAdaptation(.popover)
    }
}

/// 形状按钮
private struct ShapePickerButton: View {
    let shape: ShapeType
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isPressed ? Color.blue.opacity(0.15) : Color.clear)
                        .frame(width: 48, height: 48)

                    Image(systemName: shape.iconName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.primary, Color.primary.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text(shape.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(ShapePickerButtonStyle(isPressed: $isPressed))
    }
}

/// 自定义按钮样式
private struct ShapePickerButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                isPressed = newValue
            }
    }
}

#Preview {
    ShapePickerPopover(shapes: ShapeType.popoverShapes) { shape in
        print("Selected: \(shape.displayName)")
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}