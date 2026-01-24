# 设置页面重构设计方案 v1.0

## 1. 背景与目标

### 1.1 背景
MindCanvas 即将上架 App Store，当前设置页面存在以下问题：
- 多个占位符功能未实现（通知设置、存储管理）
- GitHub 链接对用户无实际价值
- 缺少 App Store 上架必备的隐私政策和使用条款内容
- 缺少用户反馈渠道和公众号引流入口

### 1.2 目标
1. 清理无用功能，精简设置页面
2. 补全 App Store 上架必备内容（隐私政策、使用条款）
3. 新增"帮助与反馈"模块，引流至微信公众号「逃离莫比乌斯」
4. 保持界面简洁、符合 iOS 设计规范

## 2. 设置页面结构对比

### 2.1 当前结构（需改造）
```
设置
├── 用户信息头部
├── 应用设置
│   ├── API 配置 ✅
│   ├── 通知设置 ❌ (占位符)
│   └── 存储管理 ❌ (占位符)
├── 关于
│   ├── 版本号
│   ├── 隐私政策 ❌ (占位符)
│   ├── 使用条款 ❌ (占位符)
│   └── GitHub ❌ (无用)
└── 退出登录
```

### 2.2 目标结构
```
设置
├── 用户信息头部
├── 应用设置
│   └── API 配置
├── 帮助与反馈 (新增 Section)
│   ├── 常见问题
│   ├── 联系我们 (公众号二维码)
│   └── 给个好评
├── 关于
│   ├── 版本号
│   ├── 隐私政策 (纯文本页面)
│   └── 使用条款 (纯文本页面)
└── 退出登录
```

## 3. 删除内容

| 文件/代码位置 | 删除内容 | 原因 |
|--------------|---------|------|
| SettingsView.swift | 通知设置 NavigationLink | 占位符，无实际功能 |
| SettingsView.swift | 存储管理 NavigationLink | 占位符，无实际功能 |
| SettingsView.swift | GitHub Link | 对普通用户无价值 |

## 4. 新增内容

### 4.1 新增文件清单

| 文件名 | 路径 | 说明 |
|-------|------|------|
| HelpFeedbackView.swift | Views/Settings/ | 帮助与反馈主页面 |
| FAQView.swift | Views/Settings/ | 常见问题页面 |
| ContactUsView.swift | Views/Settings/ | 联系我们页面（公众号二维码） |
| PrivacyPolicyView.swift | Views/Settings/ | 隐私政策页面 |
| TermsOfServiceView.swift | Views/Settings/ | 使用条款页面 |
| wechat_qrcode.png | Assets.xcassets/ | 公众号二维码图片 |

### 4.2 文件结构
```
Views/Settings/
├── SettingsView.swift (修改)
├── APIConfigView.swift (保留)
├── Components/
│   └── SecureAPIKeyField.swift (保留)
├── HelpFeedbackView.swift (新增)
├── FAQView.swift (新增)
├── ContactUsView.swift (新增)
├── PrivacyPolicyView.swift (新增)
└── TermsOfServiceView.swift (新增)
```

## 5. 页面设计详情

### 5.1 帮助与反馈页面 (HelpFeedbackView)

入口：设置页面 Section

**UI 结构：**
```
NavigationStack
└── List
    ├── Section: 获取帮助
    │   └── NavigationLink -> FAQView
    │       └── Label("常见问题", systemImage: "questionmark.circle")
    │
    ├── Section: 联系我们
    │   └── NavigationLink -> ContactUsView
    │       └── Label("关注公众号反馈", systemImage: "message")
    │
    └── Section: 支持我们
        └── Button -> 跳转 App Store 评分
            └── Label("给个好评", systemImage: "star")
```

### 5.2 常见问题页面 (FAQView)

**FAQ 内容：**

| 问题 | 答案 |
|------|------|
| 如何配置 API Key？ | 进入「设置 > API 配置」，输入您的 API Key 即可。支持多种 AI 服务商。 |
| 生成的图片保存在哪里？ | 生成的图片会自动保存在您的作品中，您可以在「我的作品」中查看和管理。 |
| 为什么生成失败？ | 请检查：1) API Key 是否正确配置；2) 网络连接是否正常；3) API 额度是否充足。 |
| 如何导出作品？ | 在编辑器中点击右上角导出按钮，可选择导出为 PNG 或 JPG 格式。 |
| 支持哪些 AI 模型？ | 目前支持主流的图像生成模型，具体取决于您配置的 API 服务商。 |

**UI 结构：**
```
NavigationStack
└── List
    └── ForEach(faqs)
        └── DisclosureGroup(question)
            └── Text(answer)
```

### 5.3 联系我们页面 (ContactUsView)

**UI 结构：**
```
NavigationStack
└── VStack
    ├── Spacer
    ├── Image("wechat_qrcode") // 公众号二维码
    │   └── 200x200, 圆角 12
    ├── Text("逃离莫比乌斯")
    │   └── title2, bold
    ├── Text("长按识别二维码关注公众号")
    │   └── callout, secondaryText
    ├── Text("私信留言，我们会尽快回复")
    │   └── callout, secondaryText
    ├── Spacer
    └── 保存二维码按钮 (可选)
```

**交互：**
- 长按二维码可保存到相册
- 点击"保存二维码"按钮保存图片

### 5.4 隐私政策页面 (PrivacyPolicyView)

**UI 结构：**
```
NavigationStack
└── ScrollView
    └── VStack(alignment: .leading)
        └── Text(privacyPolicyContent)
            └── body, primaryText
```

### 5.5 使用条款页面 (TermsOfServiceView)

**UI 结构：**
```
NavigationStack
└── ScrollView
    └── VStack(alignment: .leading)
        └── Text(termsOfServiceContent)
            └── body, primaryText
```

## 6. 隐私政策内容

```
MindCanvas 隐私政策

最后更新日期：2025年1月

感谢您使用 MindCanvas。我们非常重视您的隐私，本隐私政策旨在向您说明我们如何收集、使用和保护您的个人信息。

一、信息收集

1. 账户信息
当您注册 MindCanvas 账户时，我们会收集您的电子邮箱地址用于账户验证和登录。

2. 使用数据
我们可能收集您使用应用的基本信息，包括：
- 设备类型和操作系统版本
- 应用崩溃日志（用于改进应用稳定性）
- 功能使用频率（匿名统计）

3. 创作内容
您在 MindCanvas 中创建的画作和生成的图像存储在您的本地设备上。

二、信息使用

我们收集的信息仅用于：
- 提供和维护应用服务
- 改进用户体验
- 发送重要的服务通知
- 分析和解决技术问题

三、信息共享

我们不会出售、交易或以其他方式向第三方转让您的个人信息，除非：
- 获得您的明确同意
- 法律法规要求
- 保护我们的合法权益

四、第三方服务

MindCanvas 使用第三方 AI 服务生成图像。当您使用 AI 生成功能时，您的提示词会发送至相应的 AI 服务提供商。请参阅相关服务商的隐私政策了解其数据处理方式。

五、数据安全

我们采取合理的技术和管理措施保护您的个人信息安全，包括：
- 使用加密技术保护敏感数据
- 定期审查数据收集和存储实践
- 限制员工访问个人信息

六、您的权利

您有权：
- 访问您的个人信息
- 更正不准确的信息
- 删除您的账户和相关数据
- 撤回同意

如需行使上述权利，请通过应用内的反馈渠道联系我们。

七、儿童隐私

MindCanvas 不面向 13 岁以下儿童。我们不会故意收集儿童的个人信息。

八、隐私政策更新

我们可能会不时更新本隐私政策。更新后的政策将在应用内公布，建议您定期查阅。

九、联系我们

如您对本隐私政策有任何疑问，请关注微信公众号「逃离莫比乌斯」与我们联系。
```

## 7. 使用条款内容

```
MindCanvas 使用条款

最后更新日期：2025年1月

欢迎使用 MindCanvas。请在使用本应用前仔细阅读以下条款。

一、服务说明

MindCanvas 是一款基于 AI 的创意绘图应用，允许用户通过画布操作和文字描述创作艺术作品。

二、账户责任

1. 您需要注册账户才能使用完整功能
2. 您有责任保管好您的账户信息
3. 您对账户下的所有活动负责

三、使用规范

使用 MindCanvas 时，您同意不会：
1. 生成违法、色情、暴力或侵权内容
2. 尝试破解、逆向工程或干扰应用正常运行
3. 使用自动化工具批量生成内容
4. 将应用用于任何非法目的

四、知识产权

1. MindCanvas 应用的所有权利归开发者所有
2. 您使用 MindCanvas 创作的原创内容归您所有
3. AI 生成内容的版权归属请参考相关 AI 服务商的条款

五、API 配置

1. 您可以配置自己的 API Key 使用 AI 生成功能
2. API 使用费用由您自行承担
3. 请妥善保管您的 API Key，因泄露造成的损失由您自行承担

六、免责声明

1. MindCanvas 按「现状」提供，不提供任何明示或暗示的保证
2. 我们不对 AI 生成内容的准确性、适用性负责
3. 我们不对因使用本应用造成的任何直接或间接损失负责
4. 第三方 AI 服务的可用性和质量不在我们的控制范围内

七、服务变更

我们保留随时修改、暂停或终止服务的权利，恕不另行通知。

八、条款修改

我们可能会不时修改本使用条款。继续使用本应用即表示您接受修改后的条款。

九、适用法律

本条款受中华人民共和国法律管辖。

十、联系方式

如有任何问题，请关注微信公众号「逃离莫比乌斯」与我们联系。
```

## 8. SettingsView 修改要点

### 8.1 删除代码

```swift
// 删除 appSection 中的：
NavigationLink {
    Text("通知设置页面")
} label: {
    Label("通知设置", systemImage: "bell.fill")
}

NavigationLink {
    Text("存储管理页面")
} label: {
    Label("存储管理", systemImage: "internaldrive.fill")
}

// 删除 aboutSection 中的：
Link(destination: URL(string: "https://github.com")!) {
    Label("GitHub", systemImage: "link")
}
```

### 8.2 新增 Section

```swift
private var helpSection: some View {
    Section {
        NavigationLink {
            FAQView()
        } label: {
            Label("常见问题", systemImage: "questionmark.circle")
        }

        NavigationLink {
            ContactUsView()
        } label: {
            Label("联系我们", systemImage: "message")
        }

        Button {
            requestAppStoreReview()
        } label: {
            Label("给个好评", systemImage: "star")
        }
    } header: {
        Text("帮助与反馈")
    }
}
```

### 8.3 修改 aboutSection

```swift
private var aboutSection: some View {
    Section {
        // 版本号保留
        HStack {
            Label("版本", systemImage: "info.circle")
            Spacer()
            Text(appVersion)
        }

        // 隐私政策 - 改为跳转到纯文本页面
        NavigationLink {
            PrivacyPolicyView()
        } label: {
            Label("隐私政策", systemImage: "hand.raised.fill")
        }

        // 使用条款 - 改为跳转到纯文本页面
        NavigationLink {
            TermsOfServiceView()
        } label: {
            Label("使用条款", systemImage: "doc.text.fill")
        }
    } header: {
        Text("关于")
    }
}
```

## 9. 实现步骤

### Step 1: 准备资源
- [ ] 获取公众号「逃离莫比乌斯」的二维码图片
- [ ] 将二维码图片添加到 Assets.xcassets，命名为 `wechat_qrcode`

### Step 2: 创建新页面
- [ ] 创建 PrivacyPolicyView.swift
- [ ] 创建 TermsOfServiceView.swift
- [ ] 创建 FAQView.swift
- [ ] 创建 ContactUsView.swift

### Step 3: 修改 SettingsView
- [ ] 删除通知设置、存储管理、GitHub 链接
- [ ] 新增帮助与反馈 Section
- [ ] 修改隐私政策和使用条款的跳转目标
- [ ] 添加 App Store 评分功能

### Step 4: 测试验证
- [ ] 验证所有页面跳转正常
- [ ] 验证隐私政策和使用条款内容显示正确
- [ ] 验证公众号二维码显示清晰
- [ ] 验证 App Store 评分弹窗正常

## 10. App Store 评分实现

使用 StoreKit 的 `requestReview` API：

```swift
import StoreKit

private func requestAppStoreReview() {
    if let scene = UIApplication.shared.connectedScenes
        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
        SKStoreReviewController.requestReview(in: scene)
    }
}
```

## 11. 注意事项

1. **二维码图片质量**：确保二维码清晰可扫描，建议尺寸不小于 300x300 像素
2. **App Store 评分限制**：系统会限制评分弹窗的显示频率，不要频繁调用
3. **隐私政策 URL**：App Store Connect 提交时需要填写隐私政策 URL，可以考虑：
   - 创建一个简单的 GitHub Pages 页面
   - 或使用 Notion 公开页面
   - 或其他免费静态托管服务
4. **版本号动态获取**：建议从 Bundle 中动态获取版本号，而非硬编码

```swift
private var appVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
}
```
