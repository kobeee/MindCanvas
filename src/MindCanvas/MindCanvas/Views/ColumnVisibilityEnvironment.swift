import SwiftUI

private struct ColumnVisibilityBindingKey: EnvironmentKey {
    static let defaultValue: Binding<NavigationSplitViewVisibility>? = nil
}

extension EnvironmentValues {
    var columnVisibilityBinding: Binding<NavigationSplitViewVisibility>? {
        get { self[ColumnVisibilityBindingKey.self] }
        set { self[ColumnVisibilityBindingKey.self] = newValue }
    }
}

