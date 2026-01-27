import SwiftUI

struct SettingsIcon: View {
    let systemName: String
    let backgroundColor: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 27, height: 27)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension SettingsIcon {
    static func account(_ systemName: String) -> SettingsIcon {
        SettingsIcon(systemName: systemName, backgroundColor: .blue)
    }

    static func app(_ systemName: String) -> SettingsIcon {
        SettingsIcon(systemName: systemName, backgroundColor: .purple)
    }

    static func help(_ systemName: String) -> SettingsIcon {
        SettingsIcon(systemName: systemName, backgroundColor: .green)
    }

    static func contact(_ systemName: String) -> SettingsIcon {
        SettingsIcon(systemName: systemName, backgroundColor: .orange)
    }

    static func rating(_ systemName: String) -> SettingsIcon {
        SettingsIcon(systemName: systemName, backgroundColor: Color(hex: "#FFCC00"))
    }

    static func about(_ systemName: String) -> SettingsIcon {
        SettingsIcon(systemName: systemName, backgroundColor: Color.gray.opacity(0.5))
    }

    static func danger(_ systemName: String) -> SettingsIcon {
        SettingsIcon(systemName: systemName, backgroundColor: .red)
    }
}

#Preview {
    List {
        Label {
            Text("账号设置")
        } icon: {
            SettingsIcon.account("person.fill")
        }

        Label {
            Text("API 配置")
        } icon: {
            SettingsIcon.app("key.fill")
        }

        Label {
            Text("常见问题")
        } icon: {
            SettingsIcon.help("questionmark")
        }
    }
}