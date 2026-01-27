# 设置页图标 iOS 原生风格改造方案 v1.0

## 概述

将设置页列表图标改造为 iOS 系统设置风格：彩色圆角矩形背景 + 白色填充图标。

## 当前问题

1. **风格不统一**：部分图标用 `.fill`，部分用线条风格
2. **颜色单调**：全是黑/灰色，缺乏视觉层次
3. **部分图标语义不直观**：如"隐私政策"用 `hand.raised.fill`

## 设计方案

### 视觉效果

```
┌─────────────────────────────────────┐
│ [🔵] 账号设置                   >   │
│ [🟣] API 配置                   >   │
├─────────────────────────────────────┤
│ [🟢] 常见问题                   >   │
│ [🟠] 联系我们      [有福利]     >   │
│ [🟡] 给个好评                   >   │
├─────────────────────────────────────┤
│ [⚫] 版本                   1.0.0   │
│ [⚫] 隐私政策                   >   │
│ [⚫] 使用条款                   >   │
└─────────────────────────────────────┘
```

### 图标配色方案

| 分组 | 项目 | 图标 | 背景色 | 色值 |
|------|------|------|--------|------|
| 账号 | 账号设置 | `person.fill` | 蓝色 | `#007AFF` |
| 应用设置 | API 配置 | `key.fill` | 紫色 | `#AF52DE` |
| 帮助与反馈 | 常见问题 | `questionmark` | 绿色 | `#34C759` |
| 帮助与反馈 | 联系我们 | `bubble.left.fill` | 橙色 | `#FF9500` |
| 帮助与反馈 | 给个好评 | `star.fill` | 黄色 | `#FFCC00` |
| 关于 | 版本 | `info` | 灰色 | `#8E8E93` |
| 关于 | 隐私政策 | `lock.fill` | 灰色 | `#8E8E93` |
| 关于 | 使用条款 | `doc.text.fill` | 灰色 | `#8E8E93` |
| 危险操作 | 退出登录 | `rectangle.portrait.and.arrow.right` | 红色 | `#FF3B30` |

### 设计规范

- **背景尺寸**：27 x 27 pt
- **圆角半径**：8 pt（更圆润，视觉更柔和）
- **图标尺寸**：13 pt（更小，留出更多呼吸空间）
- **图标颜色**：白色 `#FFFFFF`
- **图标权重**：`.medium`

> **v1.0 优化说明**：
> - 圆角 8pt，使背景块更圆润
> - 图标 13pt，与背景比例更协调
> - 背景 27pt，整体更精致

## 技术实现

### 1. 创建 SettingsIcon 组件

```swift
// 文件: Infrastructure/Theme/SettingsIcon.swift

import SwiftUI

struct SettingsIcon: View {
    let systemName: String
    let backgroundColor: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))  // 图标 13pt
            .foregroundStyle(.white)
            .frame(width: 27, height: 27)              // 背景 27pt
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))  // 圆角 8pt
    }
}

// 预设颜色扩展
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
        SettingsIcon(systemName: systemName, backgroundColor: Color(hex: "#FFCC00") ?? .yellow)
    }

    static func about(_ systemName: String) -> SettingsIcon {
        SettingsIcon(systemName: systemName, backgroundColor: Color(UIColor.systemGray))
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
```

### 2. 修改 SettingsView.swift

#### accountSection

```swift
private var accountSection: some View {
    Section {
        NavigationLink {
            AccountSettingsView()
        } label: {
            Label {
                Text("账号设置")
                    .foregroundStyle(Theme.Colors.primaryText)
            } icon: {
                SettingsIcon.account("person.fill")
            }
        }
    } header: {
        Text("账号")
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.secondaryText)
            .textCase(.uppercase)
    }
}
```

#### appSection

```swift
private var appSection: some View {
    Section {
        NavigationLink {
            APIConfigView()
        } label: {
            Label {
                Text("API 配置")
                    .foregroundStyle(Theme.Colors.primaryText)
            } icon: {
                SettingsIcon.app("key.fill")
            }
        }
    } header: {
        Text("应用设置")
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.secondaryText)
            .textCase(.uppercase)
    }
}
```

#### helpSection

```swift
private var helpSection: some View {
    Section {
        NavigationLink {
            FAQView()
        } label: {
            Label {
                Text("常见问题")
                    .foregroundStyle(Theme.Colors.primaryText)
            } icon: {
                SettingsIcon.help("questionmark")
            }
        }

        NavigationLink {
            ContactUsView()
        } label: {
            HStack {
                Label {
                    Text("联系我们")
                        .foregroundStyle(Theme.Colors.primaryText)
                } icon: {
                    SettingsIcon.contact("bubble.left.fill")
                }

                Spacer()

                // 有福利徽章保持不变
                HStack(spacing: 4) {
                    Text("有福利")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    LinearGradient(
                        colors: [Color.fromHex("#FF6B6B") ?? .red, Color.fromHex("#FF8E53") ?? .orange],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(4)
            }
        }

        Button {
            requestAppStoreReview()
        } label: {
            Label {
                Text("给个好评")
                    .foregroundStyle(Theme.Colors.primaryText)
            } icon: {
                SettingsIcon.rating("star.fill")
            }
        }
    } header: {
        Text("帮助与反馈")
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.secondaryText)
            .textCase(.uppercase)
    }
}
```

#### aboutSection

```swift
private var aboutSection: some View {
    Section {
        HStack {
            Label {
                Text("版本")
                    .foregroundStyle(Theme.Colors.primaryText)
            } icon: {
                SettingsIcon.about("info")
            }
            Spacer()
            Text(appVersion)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.secondaryText)
        }

        NavigationLink {
            PrivacyPolicyView()
        } label: {
            Label {
                Text("隐私政策")
                    .foregroundStyle(Theme.Colors.primaryText)
            } icon: {
                SettingsIcon.about("lock.fill")
            }
        }

        NavigationLink {
            TermsOfServiceView()
        } label: {
            Label {
                Text("使用条款")
                    .foregroundStyle(Theme.Colors.primaryText)
            } icon: {
                SettingsIcon.about("doc.text.fill")
            }
        }
    } header: {
        Text("关于")
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.secondaryText)
            .textCase(.uppercase)
    }
}
```

#### logoutSection

```swift
private var logoutSection: some View {
    Section {
        Button {
            showingLogoutAlert = true
        } label: {
            HStack {
                Spacer()
                Label {
                    Text("退出登录")
                        .font(Theme.Fonts.bodyBold)
                        .foregroundStyle(Theme.Colors.destructive)
                } icon: {
                    SettingsIcon.danger("rectangle.portrait.and.arrow.right")
                }
                Spacer()
            }
        }
    }
}
```

## 修改文件清单

| 文件 | 操作 | 说明 |
|------|------|------|
| `Infrastructure/Theme/SettingsIcon.swift` | 新建 | 设置图标组件 |
| `Views/Settings/SettingsView.swift` | 修改 | 替换所有 Label 图标 |

## 测试用例

1. **视觉一致性**
   - 所有图标背景为圆角矩形
   - 图标颜色为白色
   - 背景颜色按分组区分

2. **交互正常**
   - 点击各项可正常跳转
   - 退出登录弹窗正常

3. **深色模式**
   - 图标在深色模式下清晰可见
   - 背景色保持一致

## 注意事项

1. **图标选择**：使用简洁的 SF Symbols，避免过于复杂的图标
2. **颜色对比**：确保白色图标在各背景色上清晰可见
3. **尺寸比例**：背景 27pt，图标 13pt，圆角 8pt
4. **呼吸空间**：图标占背景面积约 23%，留足空白让视觉更轻盈

## 参考

- iOS 系统设置 App
- Apple Human Interface Guidelines - SF Symbols
- [SF Symbols 完整指南](https://www.hackingwithswift.com/articles/237/complete-guide-to-sf-symbols)
