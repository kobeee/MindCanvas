import SwiftUI

/// 形状选择弹出框
struct ShapePickerPopover: View {
    let shapes: [ShapeType]
    let onShapeSelected: (ShapeType) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // 标题
            Text("选择形状")
                .font(.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .padding(.top, 8)
                .padding(.bottom, 4)

            Divider()

            // 形状网格
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(shapes) { shape in
                    ShapeButton(shape: shape) {
                        onShapeSelected(shape)
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 180)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 4)
    }
}

/// 形状按钮
private struct ShapeButton: View {
    let shape: ShapeType
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: shape.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(Theme.Colors.primaryText)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )

                Text(shape.displayName)
                    .font(.caption2)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ShapePickerPopover(shapes: ShapeType.primaryShapes) { shape in
        print("Selected: \(shape.displayName)")
    }
    .padding()
    .background(Color.gray.opacity(0.2))
}