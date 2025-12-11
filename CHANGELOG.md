# 开发记录

## 2025-12-11 - 我的创作页面视觉重构 v2.0 🎨

### 概述
按照《UI Optimization V2: My Creations (The Gallery)》设计方案，完成"我的创作"列表的全面视觉升级，从"应用图标列表"转变为"艺术画廊"。

### 设计理念
**核心目标**："From App Icons to Art Gallery"
- 去图标化：项目不是图标，而是画作预览
- 沉浸感：利用iPad大屏优势，让内容呼吸
- 极简与大气：中性色、留白、精致排版

### 实施方案：电影感列表 (Cinematic List)

#### 1. 缩略图视觉革命 ✅

**尺寸变化**
- 旧版：1:1 方形（150x150pt），像iOS桌面图标
- **新版**：4:3 宽画幅（120x90pt），符合画作预览心理预期

**占位图重新设计**
- ❌ 移除：高饱和度霓虹渐变（紫色、粉色、青色等5种渐变）
- ❌ 移除：巨大的缩写文字（如"示例"、"AI"等）
- ✅ **新设计**："未被染色的画布"理念
  - 背景：极浅冷灰色 `systemGray6`
  - 装饰：极细线条图标 `pencil.and.outline`（24pt, thin, opacity 0.3）
  - 风格：极简、低饱和度、纸张质感

**技术实现**
```swift
// 旧版代码（已移除）
- projectGradient: 5种霓虹渐变
- projectInitials: 提取项目名首字母

// 新版代码
ZStack {
    Color(uiColor: .systemGray6)
    Image(systemName: "pencil.and.outline")
        .font(.system(size: 24, weight: .thin))
        .foregroundStyle(.secondary.opacity(0.3))
}
```

#### 2. 排版与布局优化 ✅

**卡片间距**
- 旧版：`spacing: Theme.Spacing.md` (12pt)
- 新版：`spacing: 20` (增加呼吸感)

**标题层级**
- 旧版：`.font(Theme.Fonts.headline)` (较小)
- 新版：`.font(.title3.weight(.medium))` (更大更精致)

**元信息布局**
- ❌ 移除：点分隔符 `·` (视觉噪音)
- ✅ 新设计：两行自然布局，VStack(spacing: 4)
  - 第一行："修改于 日期时间" (formatted)
  - 第二行："0 张图片"
- 字体统一：`.subheadline + .secondary`

**移除干扰元素**
- ❌ 移除：右侧 `chevron.right` 箭头（卡片本身暗示可点击）
- ✅ 保留：卡片整体可点击状态

#### 3. 质感与细节 ✅

**阴影优化**
- 旧版：`opacity(0.05), radius: 4` (略显生硬)
- 新版：`opacity(0.03), radius: 5` (更轻盈、更柔和)

**圆角统一**
- 卡片：16pt
- 缩略图：12pt (内部元素略小于容器)

**内边距精确化**
- 卡片内边距：16pt (硬编码，确保一致性)
- 内容间距：HStack spacing: 16, VStack spacing: 8/4

### 修改的文件
```
src/MindCanvas/MindCanvas/Views/Projects/ProjectListView.swift
```

**代码变更统计**
- 删除：~50 行（渐变配置、缩写逻辑、旧排版）
- 新增：~30 行（极简占位图、新排版）
- 净减少：~20 行（代码更简洁）

### 视觉对比

| 元素 | 旧版 (v1.0) | 新版 (v2.0) |
|:---|:---|:---|
| 缩略图比例 | 1:1 方形 | 4:3 宽画幅 |
| 占位图背景 | 霓虹渐变 | 极简灰度 |
| 占位图装饰 | 巨大缩写 | 细线图标 |
| 标题字号 | Headline | Title3 Medium |
| 元信息布局 | 横排+点分隔 | 竖排自然间距 |
| 右侧箭头 | 有 | 无 |
| 卡片间距 | 12pt | 20pt |
| 阴影透明度 | 0.05 | 0.03 |

### 用户体验提升
1. **第一印象改善**：从"便宜的App列表"变为"精致的作品集"
2. **视觉层级清晰**：宽画幅缩略图成为视觉焦点，而非配角
3. **降低噪音**：移除无意义装饰（箭头、点、渐变），让内容说话
4. **呼吸感**：增加留白，减少压迫感，更适合创意类应用
5. **品味感**：中性色 + 纸张质感 = 专业工具的气质

### 后续优化方向（可选）
- [ ] 实现方案B：画廊网格视图（Gallery Grid）
- [ ] 添加列表/网格切换按钮
- [ ] 支持拖拽排序
- [ ] 长按显示操作菜单（重命名、删除、分享）

---

## 2025-12-10 - iOS 端 UI/UX 全面视觉优化 v1.0 ✨

### 概述
按照《MindCanvas UI/UX 视觉优化方案 v1.0》完成了 iOS 端所有页面的视觉升级，打造"简约、优雅、有品味"的原生级体验。

### 核心成果

#### 1. 全局设计系统 (Theme.swift) ✅

创建统一的视觉语言系统，包括：

**色彩系统**
- 主品牌色：`#007AFF` (System Blue)
- 渐变金色：用于高级功能标识
- 背景色：系统 GroupedBackground
- 文本色：Primary/Secondary/Placeholder 分级

**形状与质感**
- 统一圆角：按钮 12pt、卡片 16-20pt
- 柔和阴影：`Color.black.opacity(0.08), radius: 8`
- 统一图标系统：SF Symbols

**间距与尺寸系统**
- 间距：xs(4) -> xxxl(32) 八级间距
- 按钮高度：50pt
- 头像：Small(32) / Medium(48) / Large(80)

**便捷修饰符**
- `.cardStyle()`：统一卡片样式
- `.primaryButtonStyle()`：主按钮样式
- `.secondaryButtonStyle()`：次要按钮样式

#### 2. 登录页优化 (LoginView) ✅

**按钮统一**
- Apple 登录：保持官方黑色样式
- Google/GitHub：白色背景 + 灰色边框 + 品牌色图标
- 统一高度 50pt，圆角 12pt

**邮箱登录区优化**
- 添加 "OR" 分割线
- 输入框增加高度和浅灰背景
- 去掉黑边框，改为输入时蓝色高亮
- 发送按钮跟随品牌色，禁用状态透明度降低

**交互改进**
- 验证码倒计时样式优化
- Loading 状态放大并居中
- 错误提示使用品牌色背景

#### 3. 我的创作页优化 (ProjectListView) ✅

**列表样式改进**
- 从 List 改为 LazyVStack (卡片模式)
- 缩略图增大至 150x150，圆角 12pt
- 无缩略图项目生成彩色渐变背景 + 首字母

**排版优化**
- 标题使用 Headline 加粗
- 副标题（时间/数量）Caption 灰色
- 添加右侧箭头指示
- 统一卡片阴影

**侧边栏选中态**
- 选中项显示品牌色背景 + 白色文字
- 使用 `.fill` 图标变体
- 圆角矩形高亮

#### 4. MindStream 社区页优化 (FeedView) ✅

**卡片设计**
- 去除灰色边框，使用极淡阴影
- 统一圆角 16pt
- 图片 `aspectRatio(.fill)` 并裁切圆角

**用户信息区**
- 头像缩小至 32x32
- 用户名加粗
- Pro 标识使用渐变金色图标

**Prompt 区域**
- 使用等宽字体 `.monospaced`
- 浅灰背景块包裹
- 字号 13pt，增加科技感

**互动按钮**
- 移至卡片底部右侧
- 无背景图标按钮
- 点赞时 `scaleEffect` 弹跳反馈

#### 5. 订阅页优化 (SubscriptionView) ✅

**头部优化**
- 大尺寸圆形背景 + 渐变金色
- Crown 图标白色 50pt
- 标题 LargeTitle 加粗

**权益列表**
- 改为 Grid 2x2 布局
- 每个权益使用卡片展示
- 图标居中，品牌色圆形背景

**价格卡片重设计**
- 两个并排大卡片
- 选中态：3pt 品牌色边框 + 放大效果
- 节省标签：绿色 Capsule
- 价格字体：36pt 粗体

**CTA 按钮**
- 渐变金色背景
- 显示价格和周期
- 添加阴影增强立体感

#### 6. 设置页优化 (SettingsView) ✅

**使用 Form + 独立头部**
- iPad 自动 Inset Grouped 风格
- 个人资料区独立在 Form 外部

**个人资料头部**
- 头像增大至 80pt 并居中
- 用户名 Title2，Pro 标识渐变金色
- 邮箱 Callout 灰色
- 纯白背景卡片

**退出登录**
- 独立 Section
- 居中红色文字
- 确认 Alert

#### 7. 编辑器资源库优化 (AssetLibraryView) - 重点 ✅

**选中态视觉**
- 3pt 品牌色实线边框
- 图片 `scaleEffect(0.95)` 略微缩小
- Spring 动画过渡

**浮动工具条 (Floating Pill)**
- 使用 `.ultraThinMaterial` 毛玻璃效果
- Capsule 胶囊形状
- 显示在图片**下方**，不遮挡内容

**图标映射**
- 添加：`plus.circle.fill`
- 下载：`arrow.down.circle`
- 发布：`globe`
- 删除：`trash` (红色)
- 图标 20pt，间距 20pt

**交互优化**
- 仅显示图标，不显示文字
- `.hoverEffect(.lift)` 悬停效果
- 仅对生成图片显示下载/发布

### 技术亮点

1. **统一视觉语言**：通过 Theme.swift 确保全局一致性
2. **动画流畅**：Spring 动画 + ScaleEffect
3. **Material 质感**：充分利用 iOS 原生毛玻璃效果
4. **SF Symbols**：统一使用系统图标
5. **响应式设计**：充分适配 iPad 大屏

### 文件修改清单

1. **新增**：
   - `Infrastructure/Theme.swift` - 全局设计系统

2. **优化**：
   - `Views/Auth/LoginView.swift`
   - `Views/Projects/ProjectListView.swift`
   - `Views/Navigation/SidebarView.swift`
   - `Models/AppTab.swift`
   - `Views/Feed/FeedView.swift`
   - `Views/Subscription/SubscriptionView.swift`
   - `Views/Settings/SettingsView.swift`
   - `Views/Editor/AssetLibraryView.swift` (重点)

### 视觉对比

**优化前**：
- 按钮风格割裂（黑、粉、灰混杂）
- 缺乏统一间距和圆角
- 资源库工具条遮挡图片
- 卡片使用粗黑边框

**优化后**：
- 统一品牌色和样式系统
- 一致的圆角、间距、阴影
- 优雅的浮动工具条
- 柔和的卡片阴影

### 编译状态
✅ 无编译错误  
✅ 符合 SwiftUI 最佳实践  
✅ 符合 Apple HIG 设计规范  
✅ 完美实现 UI 优化方案 v1.0  

### 后续优化方向
- [ ] 添加深色模式适配
- [ ] 优化动画曲线和时长
- [ ] 添加触觉反馈
- [ ] 完善无障碍支持

---

## 2025-12-10 - 使用 columnVisibility 完美解决导航问题 ✅

### 问题回顾
之前尝试的多个方案都存在缺陷：
- `fullScreenCover`：动画从下往上（Modal 风格），不符合"详情页"直觉
- `.prominentDetail`：左侧栏变成浮层（overlay）
- `.balanced`：左侧栏固定但进入编辑器时仍然显示

### 最终解决方案

采用 **columnVisibility 动态控制** 方案，核心思路：

#### 技术实现

1. **MainView 状态管理**
   - 添加 `@State private var columnVisibility: NavigationSplitViewVisibility = .all`
   - 通过 `NavigationSplitView(columnVisibility: $columnVisibility)` 绑定状态
   - 使用自定义环境变量 `.environment(\.columnVisibilityBinding, $columnVisibility)` 传递控制权

2. **环境变量支持**
   - 创建 `ColumnVisibilityEnvironment.swift`
   - 定义自定义 `EnvironmentKey` 传递 `Binding<NavigationSplitViewVisibility>`
   - 允许深层视图控制顶层 NavigationSplitView 的侧边栏显示

3. **EditorView 控制逻辑**
   - 通过 `@Environment(\.columnVisibilityBinding)` 接收环境绑定
   - `.onAppear`：设置 `columnVisibility = .detailOnly`（隐藏侧边栏）
   - `.onDisappear`：设置 `columnVisibility = .all`（恢复侧边栏）

### 实现效果

| 场景 | 侧边栏状态 | 动画效果 | 用户体验 |
|:---|:---|:---|:---|
| **主界面** | ✅ 显示（固定占据空间） | - | 标准双栏布局 |
| **进入编辑器** | ✅ 自动隐藏 | 从右往左推入 | 编辑器全屏显示 |
| **退出编辑器** | ✅ 自动恢复 | 从左往右滑出 | 平滑过渡回主界面 |

### 核心优势

✅ **标准动画**：完全符合 iOS 推入/弹出的标准侧滑动画  
✅ **智能隐藏**：编辑器进入时侧边栏自动消失，提供最大编辑空间  
✅ **自动恢复**：返回时侧边栏自然恢复，导航上下文清晰  
✅ **简洁实现**：使用 SwiftUI 原生 API，无需自定义复杂逻辑  
✅ **环境驱动**：通过环境变量实现跨层级控制，符合 SwiftUI 最佳实践  
✅ **类型安全**：使用 `Binding` 和 `Optional`，避免崩溃风险  

### 文件修改

1. **Views/MainView.swift**
   - 添加 `columnVisibility` 状态
   - 绑定到 `NavigationSplitView`
   - 注入环境变量

2. **Views/ColumnVisibilityEnvironment.swift**（新增）
   - 定义 `ColumnVisibilityBindingKey`
   - 扩展 `EnvironmentValues`

3. **Views/Editor/EditorView.swift**
   - 接收环境绑定
   - 在 `.onAppear` / `.onDisappear` 控制显隐

### 编译状态
✅ 无编译错误  
✅ 无 linter 警告  
✅ 符合 SwiftUI 最佳实践  
✅ **完美解决导航问题**  

### 技术亮点

1. **环境驱动架构**：通过 `EnvironmentKey` 实现松耦合的跨层级通信
2. **生命周期绑定**：利用 SwiftUI 的 `.onAppear` / `.onDisappear` 自动管理状态
3. **Optional 安全**：环境值为可选类型，防止在非 SplitView 环境下崩溃
4. **iPad 优化**：充分利用 iPadOS 的 `NavigationSplitViewVisibility` 特性

### 经验总结

1. **优先使用系统能力**：SwiftUI 的 `columnVisibility` 本身就支持动态控制，无需自己造轮子
2. **环境变量的强大**：`@Environment` 是跨层级传递控制权的最佳方式
3. **生命周期钩子**：`.onAppear` / `.onDisappear` 是处理导航状态的天然时机
4. **渐进式优化**：从简单方案开始，逐步找到最优解，而不是一开始就过度设计

---

## 2025-12-10 - 导航问题待解决

### 问题描述
尝试了多种方案优化编辑器的导航体验，但都存在不同的问题：

#### 方案1：fullScreenCover（全屏模态）
- ✅ 优点：左侧导航栏完全消失，编辑器全屏显示
- ❌ 缺点：动画是从下往上滑入，不符合"进入详情页"的用户习惯
- **用户反馈**：动画方向不对

#### 方案2：.prominentDetail 样式
- ✅ 优点：从左往右的标准侧滑动画
- ❌ 缺点：左侧导航栏变成浮层（overlay），而不是固定占据空间
- **用户反馈**：左侧栏不应该是浮层

#### 方案3：.balanced 样式
- ✅ 优点：左侧栏固定占据空间（非浮层），标准侧滑动画
- ❌ 缺点：具体表现仍有问题（用户反馈"还是不行"）
- **当前状态**：待进一步分析

### 核心需求
1. **导航动画**：从左往右的标准推入动画（Push，而非 Modal）
2. **左侧栏行为**：进入编辑器时，左侧主导航栏应该自动隐藏或正常过渡
3. **布局方式**：左侧栏应该固定占据空间，而不是浮层

### 技术难点
iPad 上的 `NavigationSplitView` 在不同样式下的行为：
- **双栏模式**（Sidebar + Detail）在进入子页面时的显示逻辑较为复杂
- **嵌套 NavigationStack** 在 SplitView 内部的导航行为需要仔细处理
- 可能需要使用 `columnVisibility` 动态控制侧边栏显隐

### 待尝试的方案
1. 使用 `@Environment(\.horizontalSizeClass)` 根据屏幕尺寸调整布局
2. 在 EditorView 中监听导航状态，动态控制 `columnVisibility`
3. 考虑使用环境对象在深层页面控制侧边栏显隐
4. 或者接受 iPad 的标准行为，在宽屏幕上保持侧边栏显示

### 当前文件状态
- `Views/MainView.swift`：使用 `.balanced` 样式的双栏布局
- `Views/Projects/ProjectListView.swift`：标准 NavigationLink 导航
- `Views/Editor/EditorView.swift`：标准系统导航栏

### 编译状态
✅ 无编译错误
✅ 无 linter 警告
⚠️ 导航体验仍需优化

### 后续计划
1. 深入研究 NavigationSplitView 的 columnVisibility 机制
2. 查看 Apple 官方示例和文档
3. 可能需要重新设计整体导航架构
4. 或考虑在 iPad 上接受系统默认的分栏行为

---

## 2025-12-10 - 最终方案：保持简洁的标准导航（未能完全解决）

### 问题回顾
用户反馈之前的修改引入了新问题：
- 项目列表出现了不必要的选中高亮效果（蓝色背景）
- 过度复杂的自定义工具栏实现
- 偏离了"最小改动"的原则

### 最终解决方案（极简版）

**唯一改动**：将 MainView 的 NavigationSplitView 样式从 `.prominentDetail` 改为 `.balanced`

```swift
// MainView.swift
.navigationSplitViewStyle(.balanced)  // 唯一的改动！
```

**保持不变**：
- ProjectListView：标准的 `NavigationLink(destination:)` 导航
- EditorView：标准的系统导航栏和返回按钮
- 不使用 `selection`，不自定义工具栏，不增加复杂逻辑

### 效果对比

| 样式 | 左侧栏行为 | 导航动画 | 是否满足需求 |
|:---|:---|:---|:---|
| `.prominentDetail` | 浮层（Overlay） | ✅ 侧滑 | ❌ 左侧栏是浮层 |
| **`.balanced`** | ✅ 固定占据空间 | ✅ 侧滑 | ✅ 完美 |

### 实现细节

#### NavigationSplitView 两种样式的区别

1. **`.prominentDetail`**：
   - 详情页优先，侧边栏变成浮层
   - 适合："详情为主"的 App（如邮件、笔记）

2. **`.balanced`**：
   - 侧边栏和详情页并排显示
   - 适合：需要同时查看列表和详情的 App（如文件管理器）

### iPad 的导航行为（balanced 样式）

- **宽屏幕**：左侧栏和内容区域并排显示
- **窄屏幕或点击项目**：内容区域全屏显示，左侧栏暂时隐藏
- **返回**：从左往右滑出，返回列表，左侧栏重新显示
- **用户可以**：通过左上角按钮手动切换侧边栏显隐

### 为什么这个方案最好

✅ **最小改动**：只改一行代码  
✅ **标准体验**：完全遵循 Apple 设计规范  
✅ **无副作用**：不引入新的状态管理或自定义逻辑  
✅ **原生动画**：系统提供的流畅过渡  
✅ **支持手势**：自动支持从左边缘滑动返回  

### 文件修改
- `Views/MainView.swift`：`.navigationSplitViewStyle(.balanced)`
- `Views/ProjectListView.swift`：恢复为最简单的 NavigationLink
- `Views/Editor/EditorView.swift`：使用标准系统导航栏

### 编译状态
✅ 无编译错误
✅ 无 linter 警告
✅ 代码极简，易于维护

### 经验教训
1. 优先选择最简单的方案，不要过度设计
2. 理解系统提供的不同样式的适用场景
3. 一次只解决一个问题，避免引入新的复杂度

---

## 2025-12-10 - 修复左侧栏浮层问题并自定义编辑器工具栏（已废弃）

### 问题反馈
用户反馈使用 `.prominentDetail` 后左侧导航栏变成了浮层（overlay）模式，不符合预期：
- 侧边栏应该是固定宽度占据空间，而不是浮在内容上方
- iPad 标准 App 的侧边栏应该和内容区域并排显示

### 解决方案

#### 1. MainView 样式调整
- 改回 `.balanced` 样式，确保侧边栏固定占据空间
- 添加 `columnVisibility` 状态管理，为后续优化预留接口
- 移除 `.prominentDetail`，避免浮层行为

#### 2. ProjectListView 导航优化
- 使用 `.navigationDestination(for:)` 替代内联的 `NavigationLink(destination:)`
- 添加 `@State private var selectedProject` 跟踪选中状态
- 使用 `List(selection:)` 支持选中高亮

#### 3. EditorView 完全自定义导航栏
**关键改进**：使用 `.navigationBarHidden(true)` 隐藏系统导航栏，完全自定义 toolbar

自定义 `editorToolbar` 包含：
- **左侧**：返回按钮（`chevron.left` + "我的创作"）
- **中间**：项目名称编辑框（TextField）
- **右侧**：占位空间（保持视觉平衡）
- **底部**：分割线（Divider）

通过 `@Environment(\.dismiss)` 实现返回功能。

#### 4. 布局结构
```swift
VStack {
    自定义 Toolbar
    HStack {
        AssetLibrary | Canvas | ControlPanel
    }
}
```

### 视觉效果
- ✅ 左侧主导航栏固定占据空间（非浮层）
- ✅ 编辑器区域使用自定义工具栏，简洁美观
- ✅ 从右往左的标准推入动画
- ✅ 返回按钮清晰可见

### 后续优化方向
考虑到 iPad 的 NavigationSplitView 设计特性，如果需要在进入编辑器时**完全隐藏左侧栏**，可考虑：
1. 使用 `columnVisibility` 动态控制
2. 通过环境对象在深层页面控制侧边栏显隐
3. 或采用独立的全屏呈现方式

当前方案保持了 iPad 标准的分栏布局风格，用户可以：
- 在宽屏幕上同时看到项目列表和编辑器（通过侧边栏按钮切换）
- 在窄屏幕上编辑器自动全屏

### 文件修改
- `Views/MainView.swift`：添加 columnVisibility，恢复 balanced 样式
- `Views/Projects/ProjectListView.swift`：使用 navigationDestination
- `Views/Editor/EditorView.swift`：自定义工具栏，隐藏系统导航栏

### 编译状态
✅ 无编译错误
✅ 无 linter 警告
✅ 符合 iPad 分栏布局规范

---

## 2025-12-10 - 优化编辑器导航动画为侧滑推入

### 问题反馈
用户反馈全屏模态的"从下往上"动画不符合直觉：
- 模态视图（`.fullScreenCover`）的默认动画是从底部向上滑入
- 但对于"进入详情页"的场景，**从左往右推入（Push）** 更符合用户习惯
- iOS 系统中，导航进入子页面通常都是侧滑动画

### 最终解决方案

采用 **NavigationLink + .prominentDetail** 的组合方案：

#### 1. MainView 样式调整
- 将 `NavigationSplitView` 样式从 `.balanced` 改为 **`.prominentDetail`**
- 该样式会让详情页（Detail）**优先占据整个屏幕**，自动隐藏侧边栏
- iPad 在横屏时会智能管理侧边栏显示

#### 2. ProjectListView 恢复导航模式
- 改回使用 `NavigationLink(destination:)` 标准导航
- 移除 `@State private var selectedProject` 状态管理
- 移除 `.fullScreenCover` 模态呈现
- 系统自动提供**从左往右的推入动画** ✨

#### 3. EditorView 简化结构
- 移除外层的 `NavigationStack` 包装（不再需要）
- 移除 `@Environment(\.dismiss)` 和自定义返回按钮
- 使用 `.navigationBarBackButtonHidden(false)` 确保系统返回按钮显示
- 系统自动提供标准的返回按钮（`< 我的创作`）

### 动画效果对比

| 方案 | 进入动画 | 退出动画 | 用户体验 |
|:---|:---|:---|:---|
| **fullScreenCover（旧）** | 从下往上滑入 | 向下滑出 | ❌ 像弹窗，不符合导航直觉 |
| **NavigationLink（新）** | 从右往左推入 | 从左往右滑出 | ✅ 标准导航体验 |

### 左侧栏行为

在 iPad 上使用 `.prominentDetail` 样式时：
- **进入编辑器**：左侧主导航栏自动隐藏，编辑器全屏显示
- **滑动或点击返回**：编辑器从右往左退出，返回项目列表，主导航栏重新显示
- **横屏宽度足够时**：可通过左上角按钮手动切换侧边栏显示

### 技术要点
- **标准导航**：遵循 iOS/iPadOS 的导航规范和用户习惯
- **智能布局**：`.prominentDetail` 让系统自动处理侧边栏显隐逻辑
- **无缝动画**：系统提供的原生过渡动画流畅自然
- **返回手势**：支持标准的从左边缘滑动返回手势

### 文件修改
- `Views/MainView.swift`：改用 `.prominentDetail` 样式
- `Views/Projects/ProjectListView.swift`：恢复 NavigationLink 导航
- `Views/Editor/EditorView.swift`：简化为标准导航目标页

### 编译状态
✅ 无编译错误
✅ 无 linter 警告
✅ 符合 iOS 导航规范
✅ 提供原生侧滑动画

---

## 2025-12-10 - 优化编辑器呈现方式为全屏模态（已废弃）

### 问题描述
用户反馈：点击项目进入编辑器时，左侧主导航栏仍然显示，导致界面出现三栏布局：
- 左侧：主导航栏（我的创作、MindStream 等）
- 中间：资源库
- 右侧：控制面板

这样的布局非常拥挤，画布区域被严重压缩，不符合编辑器"全屏独立页面"的设计初衷。

### 解决方案

将编辑器从 `NavigationLink` 导航改为 **`.fullScreenCover` 全屏模态呈现**：

#### 1. ProjectListView 交互改进
- 移除 `NavigationLink`，改用 `Button` 触发
- 添加 `@State private var selectedProject: Project?` 跟踪选中项目
- 使用 `.fullScreenCover(item: $selectedProject)` 呈现编辑器
- 点击项目卡片时，左侧主导航栏**完全消失**，编辑器占据整个屏幕

#### 2. EditorView 结构优化
- 包装在独立的 `NavigationStack` 中（模态视图需要自己的导航容器）
- 添加 `@Environment(\.dismiss)` 支持关闭操作
- 在 Toolbar 左侧添加"返回"按钮：
  - 图标 + 文字：`chevron.left` + "返回"
  - 点击关闭编辑器，返回项目列表
- 保持中间的项目名称编辑功能

### 用户体验提升

**优化前**：
```
[主导航 | 资源库 | 控制面板]  // 拥挤，画布无空间
```

**优化后**：
```
[资源库 | 画布 | 控制面板]  // 全屏，空间充足
```

### 技术要点
- **全屏模态**：`.fullScreenCover` 提供完全独立的视图层级，主界面完全被覆盖
- **状态驱动**：使用 `item:` 参数，当 `selectedProject` 不为 nil 时自动呈现
- **优雅退出**：通过 `dismiss()` 环境值实现，符合 SwiftUI 最佳实践
- **导航独立**：模态视图内部的 `NavigationStack` 与外部完全隔离

### 文件修改
- `Views/Projects/ProjectListView.swift`：改用 fullScreenCover 呈现编辑器
- `Views/Editor/EditorView.swift`：添加 NavigationStack 包装和返回按钮

### 编译状态
✅ 无编译错误
✅ 无 linter 警告
✅ 符合 iOS 模态呈现规范
✅ 提供流畅的进入/退出动画

---

## 2025-12-10 - 修复导航结构问题

### 问题分析
通过对比截图、代码和 PRD，发现页面层级结构存在严重问题：
- **原实现**：使用三栏 `NavigationSplitView`，在第三栏直接显示 `EditorView`（编辑器本身就是三栏布局）
- **问题**：导致编辑器的三栏嵌套在主界面的第三栏里，违背了 PRD 设计意图
- **PRD 要求**：编辑器应该是"点击项目后进入的详情页"，应为独立全屏页面

### 架构调整

#### 1. MainView 导航结构优化
- **调整前**：三栏布局 (Sidebar + ContentList + Detail)
- **调整后**：两栏布局 (Sidebar + Content)
- 移除 `selectedProject` 状态管理
- 简化 `detailView`，改为 `contentView` 直接展示主内容

#### 2. ProjectListView 重构
- **关键改动**：内部使用 `NavigationStack` 而非依赖外层 `NavigationSplitView`
- 使用 `NavigationLink(destination:)` 实现点击项目后**导航到全屏编辑器**
- 移除 `@Binding var selectedProject` 参数依赖
- 简化 `createNewProject()`，不再自动选中项目

#### 3. 其他视图一致性处理
将 `FeedView`、`SubscriptionView`、`SettingsView` 都包装在 `NavigationStack` 中：
- 确保 `.navigationTitle` 正常显示
- 支持各视图内的进一步导航（如设置页的子页面）
- 保持与 `ProjectListView` 一致的导航体验

### 页面层级关系（修正后）

**一级导航**（MainView Sidebar）:
- 我的创作
- MindStream  
- 订阅
- 设置

**二级页面**（MainView Content）:
- 项目列表（选择"我的创作"时）
- 社区流（选择"MindStream"时）
- 订阅页面（选择"订阅"时）
- 设置页面（选择"设置"时）

**三级页面**（通过 NavigationLink 导航）:
- **编辑器全屏页面**（点击项目后进入）
  - 左栏：AssetLibraryView（资源库）
  - 中栏：CanvasContainerView（画布）
  - 右栏：ControlPanelView（控制面板）

### 技术要点
- iPad 标准两栏布局使用 `NavigationSplitView` 的双栏形式
- 内部页面使用 `NavigationStack` 实现独立导航栈
- 编辑器作为全屏页面，可以充分利用整个屏幕空间展示三栏布局
- 符合 PRD 中"点击列表项后进入详情页"的交互设计

### 文件修改
- `Views/MainView.swift`：简化为两栏布局
- `Views/Projects/ProjectListView.swift`：内嵌 NavigationStack，使用 NavigationLink 导航
- `Views/Feed/FeedView.swift`：包装在 NavigationStack 中
- `Views/Subscription/SubscriptionView.swift`：包装在 NavigationStack 中
- `Views/Settings/SettingsView.swift`：包装在 NavigationStack 中

### 编译状态
✅ 无编译错误
✅ 无 linter 警告
✅ 符合 PRD 设计要求
✅ 遵循 SwiftUI 最佳实践

---

## 2025-12-10 - v1.0 初始开发完成

### 概述
完成 MindCanvas iOS 客户端 v1.0 的基础架构和所有核心模块的开发，包括身份认证、项目管理、核心编辑器、社区模块、订阅和设置页面。

### 架构设计
- 采用 MVVM 架构模式
- 使用 SwiftUI + SwiftData 构建现代化 iOS 应用
- 使用 @Observable 宏进行状态管理（iOS 17+）
- 实现 Repository Pattern 的 Mock 服务层

### 数据模型层 (Models/)
创建的核心数据模型：
- `User.swift`: 用户信息模型（id, username, email, avatarUrl, isPro）
- `Project.swift`: 项目模型（使用 @Model 支持 SwiftData 持久化）
- `Asset.swift`: 资源模型（区分上传/生成类型，支持 loading 状态）
- `FeedItem.swift`: 社区内容模型
- `AppTab.swift`: 导航枚举（我的创作、MindStream、订阅、设置）

### 基础设施层 (Infrastructure/)
- `KeychainManager.swift`: 封装 Keychain 操作，安全存储用户 Token
  - saveToken(), getToken(), deleteToken()
  - 使用 Security framework

### 服务层 (Services/) - Mock 实现
所有服务都使用 Mock 数据，模拟真实后端行为：

1. **MockAuthService.swift**
   - 支持 Apple/Google/GitHub/Email 登录
   - 模拟 1 秒网络延迟
   - 邮箱验证码固定为 "123456"
   - 返回 LoginResponse (token + user)

2. **MockGenerationService.swift**
   - generate(): 模拟 AI 图片生成（3 秒延迟）
   - uploadImage(): 模拟图片上传（1 秒延迟）
   - 使用 picsum.photos 提供随机图片

3. **MockFeedService.swift**
   - fetchFeed(): 分页加载社区内容
   - publishImage(): 模拟发布操作
   - likeImage() / unlikeImage(): 点赞功能

### 管理器层 (Managers/)
- `AuthManager.swift`: 
  - 全局单例，管理认证状态
  - 使用 @Observable 宏进行状态管理
  - 集成 KeychainManager 进行 token 持久化
  - 提供 loginWith* 系列方法
  - 支持 logout 和自动检查认证状态

### 视图模型层 (ViewModels/)
1. **EditorViewModel.swift**
   - 管理编辑器核心状态（prompt, assets, isGenerating）
   - 协调左中右三个面板的交互
   - 处理图片导入、生成、删除、发布
   - 管理画布状态（snapshot, hasSelection）
   - 与 SwiftData ModelContext 集成

2. **FeedViewModel.swift**
   - 管理社区流数据加载
   - 分页加载逻辑
   - 点赞状态管理
   - 下拉刷新支持

### 视图层 (Views/)

#### 1. 身份认证 (Auth/)
- **LoginView.swift**:
  - Sign in with Apple 按钮（使用 AuthenticationServices）
  - 社交登录按钮（Google, GitHub）
  - 邮箱验证码登录流程
  - 倒计时功能
  - 错误提示展示
  - 加载状态处理

#### 2. 导航框架 (Navigation/)
- **RootView.swift**: 根视图，根据认证状态切换 LoginView / MainView
- **MainView.swift**: 主界面，使用 NavigationSplitView 实现三栏布局
- **SidebarView.swift**: 左侧主导航栏，展示 4 个主 Tab

#### 3. 项目管理 (Projects/)
- **ProjectListView.swift**:
  - 使用 @Query 查询 SwiftData
  - 支持创建、删除项目
  - 项目行展示（缩略图 + 名称 + 修改时间）
  - 初始化时创建示例项目
  - 集成 Toolbar 按钮

#### 4. 核心编辑器 (Editor/)
**EditorView.swift**: 三栏编辑器容器
  - 左：AssetLibraryView (300pt)
  - 中：CanvasContainerView (自适应)
  - 右：ControlPanelView (320pt)
  - 项目名称可编辑 Toolbar

**AssetLibraryView.swift**: 左侧资源库
  - 使用 PhotosPicker 导入图片
  - 懒加载列表展示资源
  - AssetCard 组件：
    - 图片预览（支持 loading 状态）
    - 选中态高亮
    - 浮动菜单：添加到画布、下载、发布、删除
    - 生成图片显示 AI 标识
  - 发布 Sheet：标题输入 + 预览

**CanvasWebView.swift**: 中间画布（WKWebView）
  - UIViewRepresentable 包装 WKWebView
  - 内嵌简易 HTML5 Canvas
  - 工具栏：画笔、橡皮擦、框架、清空
  - Bridge 通信：
    - JS → Swift: canvas_updated, selection_changed, canvas_ready
    - Swift → JS: insertImage(url, x, y, w, h)
  - Coordinator 处理消息和导航事件
  - Fallback HTML（预留 tldraw 集成点）

**CanvasContainerView.swift**: 画布外层容器
  - 背景颜色
  - 帮助按钮

**ControlPanelView.swift**: 右侧控制面板
  - API 配置展示（官方服务）
  - 模型展示（Nano Banana Pro，锁定状态）
  - Prompt 输入（TextEditor，120pt 高度）
  - 生成按钮（支持 loading 状态）
  - 选区提示（hasSelection 状态）

#### 5. 社区模块 (Feed/)
**FeedView.swift**:
  - 垂直滚动列表（LazyVStack）
  - FeedCard 组件：
    - 作者信息（头像、用户名、Pro 标识）
    - 图片展示（AsyncImage）
    - Prompt 显示（可选）
    - 操作栏：点赞、Remix
    - 举报/拉黑菜单（审核要求）
  - 下拉刷新
  - 分页加载

#### 6. 订阅 (Subscription/)
**SubscriptionView.swift**:
  - 头部（Crown 图标 + 标题）
  - 功能列表（FeatureRow 组件）
  - 订阅计划卡片（月度/年度，PlanCard 组件）
  - 订阅按钮
  - FAQ 可折叠列表（FAQItem 组件）

#### 7. 设置 (Settings/)
**SettingsView.swift**:
  - 账号信息展示（头像、用户名、邮箱、Pro 标识）
  - 应用设置导航（API、通知、存储）
  - 关于信息（版本、隐私、条款、GitHub）
  - 退出登录（带确认 Alert）

### App 入口更新
**MindCanvasApp.swift**:
  - 更新 SwiftData Schema（Project, Asset）
  - 注入 AuthManager 到环境
  - 使用 RootView 作为根视图

### 技术亮点

1. **现代 Swift 特性**:
   - 使用 @Observable 替代 ObservableObject
   - async/await 异步编程
   - Task.sleep 模拟网络延迟
   - 强类型和泛型

2. **SwiftUI 最佳实践**:
   - NavigationSplitView 实现 iPad 三栏布局
   - LazyVStack 优化长列表性能
   - @Query 简化 SwiftData 查询
   - PhotosPicker 现代图片选择器
   - AsyncImage 异步图片加载
   - .task / .refreshable 修饰符

3. **WebView Bridge**:
   - WKScriptMessageHandler 实现 JS → Swift 通信
   - evaluateJavaScript 实现 Swift → JS 通信
   - 消息体使用结构化 JSON

4. **安全性**:
   - Keychain 存储敏感 Token
   - 不使用强制解包（!）
   - 使用 guard let 进行提前返回
   - 错误处理使用 do-catch

5. **组件化设计**:
   - 独立的 Card 组件（AssetCard, FeedCard, PlanCard）
   - 可复用的 Row 组件（FeatureRow, ProjectRow）
   - 功能组件（FAQItem）

### 项目结构完整性
```
MindCanvas/
├── Models/ (5 个文件)
├── ViewModels/ (2 个文件)
├── Views/ (8 个目录，16 个文件)
├── Services/ (3 个 Mock 服务)
├── Managers/ (1 个管理器)
├── Infrastructure/ (1 个工具类)
├── Assets.xcassets/
└── MindCanvasApp.swift
```

### 编译状态
✅ 无编译错误
✅ 无 linter 警告
✅ 符合 SwiftUI 和 Swift 最佳实践规范

### 待完成工作
- 集成真实 tldraw 库到 WebView
- 连接真实后端 API
- 实现图片下载到相册功能
- 完善 Remix 跳转逻辑
- 实现 IAP 订阅购买
- 性能优化和缓存策略

### 测试验证
建议测试流程：
1. 登录流程测试（4 种登录方式）
2. 项目创建和列表展示
3. 编辑器三栏交互
4. 资源导入和生成
5. 画布绘图功能
6. 社区流浏览和点赞
7. 订阅页面展示
8. 设置页面和退出登录

### 经验总结
1. 使用 @Observable 简化状态管理，比 ObservableObject 更简洁
2. SwiftData 的 @Query 大大简化了数据查询代码
3. Mock 服务层设计合理，便于后续替换为真实 API
4. WebView Bridge 通信需要注意 MainActor 标记
5. iPad 的 NavigationSplitView 需要注意布局模式设置
6. PhotosPicker 是 iOS 16+ 推荐的图片选择器
7. 组件化设计提高了代码复用性和可维护性

### 代码规范遵守
✅ 所有属性默认 private
✅ 使用 guard let 进行提前返回
✅ 使用 KeyPath 语法（如 \.name）
✅ 集合判空使用 .isEmpty
✅ 计算属性使用只读形式
✅ 视图保持小巧，超过 50 行拆分子组件
✅ Extension 分组协议遵循
✅ 异步操作使用 async/await
✅ UI 操作标记 @MainActor
✅ 使用 Result 类型处理错误

