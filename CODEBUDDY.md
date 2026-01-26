# MindCanvas 项目概览

MindCanvas 是一个基于 AI 的创意绘图应用，专为 iPad 设计，集成了 AI 图像生成能力，允许用户通过简单的画布操作和文字描述来创作独特的艺术作品。

## 项目类型

这是一个 **iOS 应用项目**，采用前后端分离架构，目前专注于 iOS 客户端的开发，使用 SwiftUI 构建现代化的用户界面。

## 技术栈

### iOS 客户端
- **语言**: Swift 5.9+
- **UI 框架**: SwiftUI + UIKit (混合架构)
- **最低版本**: iPadOS 17.0+
- **数据存储**: SwiftData
- **网络**: URLSession (当前使用 Mock 服务)
- **画布**: PencilKit (PKCanvasView) + UIKit 自定义对象层
  - 笔刷绘制: PKCanvasView 原生支持
  - 图形对象: UIKit 自定义视图 (箭头、形状、图片等)
  - 控制点交互: 专业级缩放/旋转控制点系统

### 后端（待开发）
- **语言**: Python 3.11
- **框架**: FastAPI
- **数据库**: PostgreSQL
- **缓存**: Redis
- **部署**: Docker

## 项目结构

```
MindCanvas/
├── docs/                   # 文档
│   ├── prd/               # 产品需求文档
│   ├── design/            # 设计文档
│   │   ├── backend/       # 后端设计
│   │   ├── fix/           # 问题修复方案
│   │   └── ui/            # UI 设计方案
│   └── archive/           # 归档文档
├── src/                   # 源代码
│   └── MindCanvas/        # iOS 项目
│       ├── Models/        # 数据模型
│       │   └── Canvas/    # 画布相关模型
│       ├── ViewModels/    # 视图模型
│       ├── Views/         # 视图层
│       │   ├── Editor/    # 编辑器视图
│       │   │   ├── Canvas/  # 画布组件
│       │   │   └── Sheets/  # 弹出表单
│       │   ├── Feed/      # 社区流
│       │   ├── Projects/  # 项目列表
│       │   └── Settings/  # 设置
│       ├── Services/      # 服务层（Mock）
│       ├── Managers/      # 管理器
│       └── Infrastructure/ # 基础设施
└── tests/                 # 测试代码
```

## 核心功能模块

1. **身份认证**: 支持 Apple/Google/GitHub/邮箱多种登录方式
2. **项目管理**: 创建、编辑、管理多个绘图项目
3. **核心编辑器**: 三栏式编辑界面（资源库 + 画布 + 控制面板）
4. **AI 生成**: 基于提示词生成图像（当前使用 Mock）
5. **社区模块**: MindStream 灵感流，浏览和分享作品
6. **订阅系统**: Pro 会员展示和订阅计划
7. **设置中心**: 账号管理、配置和退出登录

## 构建和运行

### iOS 开发

1. **环境要求**:
   - macOS 14.0+
   - Xcode 15.0+
   - iPad 模拟器或真机

2. **打开项目**:
```bash
cd src/MindCanvas
open MindCanvas.xcodeproj
```

3. **运行**: 选择 iPad 目标设备并运行（⌘R）

### Mock 数据说明

当前版本使用完全本地化的 Mock 数据：
- 所有登录都会成功（邮箱验证码: `123456`）
- 图片生成使用 picsum.photos 随机图片
- 社区内容为随机生成
- 无需后端服务即可完整体验 UI 和交互

## 开发状态

### 已完成 ✅
- iOS 客户端基础架构
- 所有核心模块的 UI 和交互
- Mock 服务层（模拟后端接口）
- SwiftData 本地数据持久化
- **原生画布系统 (PencilKit + UIKit)**
  - PKCanvasView 架构重构（直接使用内置缩放，解决笔画漂移问题）
  - 撤销/恢复系统（支持笔画和对象操作）
  - 多工具支持（笔刷、选择、平移、图片、箭头、形状、文本、标注）
- **图形工具系统**
  - 箭头/直线工具（支持区分箭头和纯直线）
  - 形状工具（矩形、圆形、三角形、菱形、五角星、六边形、圆角矩形）
  - 形状选择器弹出菜单
- **专业级控制点交互系统**
  - 形状对象：4个角点控制点 + 旋转手柄
  - 箭头对象：起点/终点控制点
  - 支持旋转状态下的精确缩放
  - 移除双指手势依赖，符合 Figma/Canva 交互标准

### 进行中 🚧
- 真实后端 API 集成
- IAP 订阅功能

### 待开发 📋
- 后端服务器
- 真实 AI 模型集成
- 图片下载功能
- Remix 完整流程
- 性能优化
- 控制点增强功能（等比例缩放、吸附、键盘快捷键）

## 开发约定

### 状态管理
使用 iOS 17+ 的 `@Observable` 宏替代传统的 `ObservableObject`：

```swift
@Observable
@MainActor
final class EditorViewModel {
    var prompt = ""
    var isGenerating = false
    // ...
}
```

### 画布架构

**核心架构**：直接使用 PKCanvasView 的内置缩放功能
```swift
NativeCanvasView (UIView)
└── pencilCanvas (PKCanvasView)    // 直接作为根滚动容器
    └── overlayContainerView (UIView)  // 滚动同步容器
        └── objectLayerView (UIView)   // 对象图层（箭头、形状、图片等）
```

**关键技术点**：
- PKCanvasView 本身继承自 UIScrollView，直接使用其内置缩放
- overlayContainerView 通过同步机制跟随 PKCanvasView 滚动和缩放
- 避免嵌套 UIScrollView（已知的 Apple Bug FB15166022）

**坐标系统**：
- 画布内容尺寸：5000x5000 pt
- 视口坐标 → 内容坐标转换：`(x + offset.x) / scale`
- 使用 `contentRect(forViewportRect:)` 进行坐标转换

### 控制点交互系统

**形状对象控制点**：
```
        ○ ← 旋转手柄（圆形，12x12）
        │   连接线（蓝色，1.5pt）
    ●───┴───●
    │       │  ← 角点控制点（方形，12x12）
    │ 形状  │
    │       │
    ●───────●
```

**箭头对象控制点**：
- 起点控制点：圆形，调整箭头起点
- 终点控制点：圆形，调整箭头终点

**旋转状态下的缩放计算**：
```swift
// 1. 获取锚点在旋转后的实际位置
let anchorInSuperview = CGPoint(
    x: centerX + relX * cos(rotation) - relY * sin(rotation),
    y: centerY + relX * sin(rotation) + relY * cos(rotation)
)

// 2. 将拖动向量转换到未旋转的坐标系
let localDx = dx * cos(-rotation) - dy * sin(-rotation)
let localDy = dx * sin(-rotation) + dy * cos(-rotation)

// 3. 计算新尺寸并保持锚点位置
```

### SwiftData 查询
```swift
@Query(sort: \Project.lastModified, order: .reverse) 
private var projects: [Project]
```

## 注意事项

### 应用架构
1. **iPad Only**: 本应用专为 iPad 设计，使用 NavigationSplitView
2. **无后端依赖**: 当前版本完全独立运行，不需要后端服务
3. **Mock 延迟**: 所有 Mock 接口都添加了人工延迟以模拟真实网络环境
4. **审核合规**: 已预置举报、拉黑功能以符合 App Store 审核要求

### 画布系统关键技术点
1. **PKCanvasView 嵌套问题**: 严禁将 PKCanvasView 嵌套在 UIScrollView 中（Apple Bug FB15166022），会导致坐标转换错误和笔画漂移
2. **撤销系统**: 使用 PKCanvasView 重建实例来彻底清除内部缓存，避免撤销后笔画复活问题
3. **视图层级**: objectLayerView 必须作为 overlayContainerView 的子视图，通过同步机制跟随画布滚动
4. **手势冲突**: 不同工具模式下需要正确配置 `drawingPolicy` 和手势识别器状态
5. **控制点交互**: 已移除双指手势依赖，使用单指拖动 + 控制点的专业交互方式
6. **坐标转换**: SwiftUI 手势坐标需要转换为画布内容坐标，考虑 `contentOffset` 和 `zoomScale`

## 开发规范与约定

### 核心开发原则
- **研发流程**：接需求->写PRD->需求分析->系统设计和分析->测试设计和分析->研发->**强制代码审查**->测试
- **先设计后开发**：按照研发流程一步步推进，设计应包含测试用例
- **可测试性**：编写可测试的代码，组件应保持单一职责
- **DRY 原则**：避免重复代码，提取共用逻辑到单独的函数或类
- **代码简洁**：保持代码简洁明了，遵循 KISS 原则
- **命名规范**：使用描述性的变量、函数和类名，反映其用途和含义
- **风格一致**：遵循项目或语言的官方风格指南和代码约定

### 🔄 强制代码审查流程（研发最后阶段）

#### 触发条件
每次完成代码修改后，必须立即启动代码审查流程，包括但不限于：
- 新功能开发完成
- Bug修复完成
- 重构代码完成
- 配置文件修改
- 依赖库更新

#### 审查执行步骤
1. **启动代码审查subagent**：
   ```bash
   使用Task工具启动general-purpose subagent
   传入修改的文件路径和审查指令
   ```

2. **语法完整性检查**：
   - 验证所有ForEach语句的id参数正确性
   - 检查所有闭包大括号匹配
   - 确认函数调用参数完整性
   - 验证文件结构完整性

3. **编译错误预防**：
   - 检查泛型参数推断问题
   - 验证协议实现完整性
   - 确认依赖关系正确性
   - 检查可能的类型转换错误

4. **代码质量评估**：
   - 验证命名规范遵循情况
   - 检查代码结构和可读性
   - 确认注释和文档完整性
   - 验证错误处理机制

5. **问题修复流程**：
   - 发现问题立即记录并修复
   - 重大问题需要重新审视设计方案
   - 修复后重新运行审查流程
   - 确认无问题后标记审查完成

#### 审查完成标准
- ✅ 所有语法错误已修复
- ✅ 所有编译警告已处理
- ✅ 代码符合项目规范
- ✅ 依赖关系正确无误
- ✅ 文档和注释完整

#### 审查记录要求
- 每次审查必须有详细记录
- 发现问题和修复方案必须文档化
- 审查结果要同步到项目文档
- 重大问题要上报并讨论

**注意：跳过代码审查流程导致的问题将由开发人员承担责任！**

### 项目通用规范
- **省token**: 不啰嗦、不生成无用文档、读代码跳注释、非必要不读 docs/archive
- **不自动提交**: 禁止 git push 或 git commit，需要用户明确同意
- **不追求完美**: 谦虚务实，实践检验，有疑问就问
- **代码有效**: 不添加调试用的无效日志，调试完后主动清除
- **禁止在代码和注释里使用图标，只允许使用文字**

### SwiftUI 开发规范
- **视图即值**: 必须使用 `struct` 创建 View，保持视图小巧和专注
- **状态管理**: 
  - 本地状态使用 `@State` 并标记为 `private`
  - 双向绑定使用 `@Binding`
  - iOS 17+ 必须使用 `@Observable` 宏替代 `ObservableObject`
  - 依赖注入使用 `@Environment` 或 `@EnvironmentObject`
- **样式与布局**:
  - 创建自定义 `ViewModifier` 来封装重复的样式逻辑
  - 处理长列表时必须使用 `LazyVStack` 或 `LazyHStack`
  - 将复杂的业务逻辑从 View 中提取到 ViewModel
- **架构模式**: 默认使用 MVVM，View 负责渲染，ViewModel 负责状态流转
- **线程安全**: 所有 UI 相关的类和操作必须标记为 `@MainActor`

### 🚨 高优先级研发遵守准则（必须严格执行）

#### 语法完整性准则
1. **ForEach 参数规范**：
   - 必须正确指定 `id` 参数：`ForEach(data, id: \.id)` 或 `ForEach(data, id: \.self)`
   - 禁止使用模糊的泛型参数，确保编译器能正确推断类型
   - 枚举类型优先使用 `id: \.id`（利用Identifiable协议）

2. **闭包结构完整性**：
   - 所有闭包必须正确开始和结束，大括号成对匹配
   - 禁止在闭包外部放置属于闭包逻辑的代码
   - 多层嵌套闭包必须清晰缩进，避免结构混乱

3. **函数调用参数完整性**：
   - 必须提供所有必需参数，禁止省略关键参数
   - 可选参数要根据实际需求合理使用
   - 回调函数必须正确实现，不能留空或使用占位符

4. **文件结构完整性**：
   - 每个文件必须有正确的开始和结束结构
   - 禁止多余的大括号或缺少结构闭合
   - Preview代码必须放在文件末尾，结构完整

#### 编译错误预防准则
1. **修改前验证**：
   - 修改文件前必须先读取完整内容，了解现有结构
   - 复杂修改要分段进行，每次修改后验证语法
   - 禁止盲目修改，必须理解代码逻辑

2. **修改后验证**：
   - 每次修改后必须检查语法完整性
   - 确保所有大括号、括号、引号正确配对
   - 验证函数调用参数数量和类型正确性

3. **依赖关系检查**：
   - 修改组件时检查依赖的接口是否发生变化
   - 确保导入的模块和类型正确可用
   - 验证协议实现是否完整

#### 调试代码管理准则
1. **调试日志规范**：
   - 调试日志要有明确标识和层级
   - 禁止在生产代码中保留调试日志
   - 调试完成后必须清理相关日志代码

2. **临时代码管理**：
   - 临时变量和函数要有明确标记
   - 禁止将临时代码提交到最终版本
   - 定期清理无用的测试代码和注释

#### 代码审查强制流程
每次开发完成后，必须运行代码审查subagent：
1. **语法完整性检查**：验证所有语法结构正确
2. **编译错误预防**：检查可能的编译问题
3. **代码质量评估**：确保符合项目规范
4. **依赖关系验证**：检查模块依赖正确性

**违反以上准则将导致严重的编译错误和项目延期，必须严格执行！**

### Swift 语法最佳实践
- **绝对禁区**:
  - 严禁强制解包 (`!`)，除了 `IBOutlet` 和极少数确定性场景
  - 严禁 `NS` 前缀类型，使用 `String`、`Array`、`Dictionary`
  - 严禁 `try!`，使用 `do-catch` 或 `try?`
  - 慎用 `unowned`，在闭包捕获列表中一律使用 `[weak self]`
- **流程控制**:
  - 卫语句优先 (`guard let`)，拒绝"金字塔式"嵌套
  - Switch 穷举，尽量避免使用 `default`
  - 使用 `defer` 确保资源释放
- **函数式与集合**:
  - 优先使用 `.map`, `.filter`, `.reduce`, `.compactMap`
  - 使用 KeyPath 语法: `users.map(\.name)`
  - 使用 `.isEmpty` 检查集合，不要使用 `.count == 0`
- **属性与访问控制**:
  - 所有属性默认标记为 `private` 或 `private(set)`
  - 使用只读计算属性而不是函数
  - 对于昂贵的初始化操作必须使用 `lazy var`

### FastAPI 开发规范（后端）
- 为所有函数参数和返回值使用类型提示
- 使用 Pydantic 模型进行请求和响应验证
- 在路径操作装饰器中使用适当的 HTTP 方法
- 使用依赖注入实现共享逻辑
- 使用后台任务进行非阻塞操作
- 使用适当的状态码进行响应
- 使用 APIRouter 按功能或资源组织路由

### 文档规范
- 所有文档使用Markdown格式
- 使用简洁、清晰的语言，文档内容应保持最新
- 使用中文作为主要语言
- 开发记录使用 `CHANGELOG.md`，每次以换行追加到文件头部，**无论变更是否在同一天内发送，总是最新的修改出现在文件的最顶部，除非明确要求整合CHANGELOG的内容，否则不允许以修改的方式覆盖CHANGELOG，CHANGELOG就是要记录过程的！！！！！！！**
- 在 Plan 模式下产出的方案需保存到 `docs/design/` 目录

## 远程服务器部署信息

**服务器地址**: 65.75.220.11

**SSH 登录**:
- 用户: root
- 方式: SSH 密钥登录（无需密码）
- 命令: `ssh root@65.75.220.11`

**部署路径**: `/root/mind-canvas/`

**部署架构**:
```
用户浏览器
    ↓ (HTTPS)
Cloudflare (SSL 终止 + Always Use HTTPS)
    ↓ (HTTP)
Nginx (80 端口，反向代理)
    ↓ (127.0.0.1:8008)
Docker Backend 容器 (8000 端口)
    ↓
PostgreSQL + Redis (Docker 网络内)
```

**服务配置**:
- **Backend 服务**: 对外暴露端口 8008（映射到容器内 8000，仅监听 127.0.0.1）
- **Nginx**: 监听 80 端口，反向代理到 Backend 服务
- **PostgreSQL**: 未暴露端口（仅在 Docker 网络内访问）
- **Redis**: 未暴露端口（仅在 Docker 网络内访问）
- **Admin 服务**: 未暴露端口（仅在 Docker 网络内访问）

**域名配置**:
- **子域名**: mindcanvas.escapemobius.cc
- **SSL**: Cloudflare Origin Certificate + Always Use HTTPS
- **Cloudflare 模式**: Flexible（Cloudflare 到源服务器使用 HTTP）

**安全配置**:
- PostgreSQL 和 Redis 端口未对外暴露，仅通过 Docker 网络访问
- 管理服务在 Docker 容器内运行，不对外暴露
- Backend 服务只监听 127.0.0.1，不对外暴露
- Nginx 拒绝通过 IP 地址访问，只允许通过域名访问
- Cloudflare Always Use HTTPS 自动重定向 HTTP 到 HTTPS

**服务状态检查**:
```bash
# SSH 登录服务器
ssh root@65.75.220.11

# 进入部署目录
cd /root/mind-canvas

# 查看服务状态
docker-compose ps

# 查看服务日志
docker-compose logs -f backend

# 重启服务
docker-compose restart

# 停止服务
docker-compose down

# 启动服务
docker-compose up -d

# Nginx 相关命令
systemctl status nginx
systemctl restart nginx
nginx -t  # 测试配置
```

**健康检查接口**:
- URL: `https://mindcanvas.escapemobius.cc/health`
- 返回: `{"status":"healthy","service":"MindCanvas Backend"}`
- HTTP 访问: `http://mindcanvas.escapemobius.cc/health` 自动重定向到 HTTPS
- IP 访问: 被拒绝（返回 444）

**部署文件清单**:
- docker-compose.yml
- .env
- Dockerfile
- requirements.txt
- app/（应用代码）
- migrations/（数据库迁移脚本）
- storage/（存储目录，包含 images/）
- nginx/（Nginx 配置文件）
- scripts/（部署脚本）

**Docker 镜像**:
- 镜像名: mindcanvas-backend:latest
- 镜像文件: /root/mind-canvas/mindcanvas-backend.tar（已加载）

**部署脚本命令**:
```bash
# 安装和配置 Nginx
./deploy.sh setup-nginx

# 启动 Nginx
./deploy.sh start-nginx

# 停止 Nginx
./deploy.sh stop-nginx

# 重启 Nginx
./deploy.sh restart-nginx

# 部署并启动服务
./deploy.sh deploy

# 启动服务
./deploy.sh start

# 停止服务
./deploy.sh stop

# 重启服务
./deploy.sh restart

# 查看状态
./deploy.sh status

# 查看日志
./deploy.sh logs

# 重新构建
./deploy.sh rebuild

# 清理服务（保留数据）
./deploy.sh clean

# 重置服务（删除所有数据）
./deploy.sh reset

# 启动管理服务
./deploy.sh start-admin

# 停止管理服务
./deploy.sh stop-admin

# 注入邮箱配额
./deploy.sh quota <email> <quota>

# 查询所有邮箱配额
./deploy.sh list-quota

# 查询指定邮箱配额
./deploy.sh get-quota <email>

# 减少指定邮箱配额
./deploy.sh reduce-quota <email> <amount>

# 同步到远程服务器并重新部署
./deploy.sh sync
```

**开发工作流**:
每次修改 `src/backend/` 目录下的代码后，必须执行以下步骤同步到远程服务器：

1. **同步代码并重新部署**:
```bash
cd src/backend
REMOTE_SERVER="65.75.220.11" REMOTE_USER="root" REMOTE_PATH="/root/mind-canvas" ./deploy.sh sync
```

2. **验证服务状态**:
```bash
ssh root@65.75.220.11 "cd /root/mind-canvas && docker-compose ps"
```

3. **查看服务日志**（如果需要）:
```bash
ssh root@65.75.220.11 "cd /root/mind-canvas && docker-compose logs -f backend"
```

**注意**: 本地开发和远程部署使用相同的代码库，修改代码后需要重新构建镜像并部署到服务器。

**iOS 端配置**:
- API_BASE_URL: `https://mindcanvas.escapemobius.cc`
- IMAGE_BASE_URL: `https://mindcanvas.escapemobius.cc/images/`

## 重要文件路径

### 应用核心
- **主应用入口**: `src/MindCanvas/MindCanvas/MindCanvasApp.swift`
- **认证管理器**: `src/MindCanvas/MindCanvas/Managers/AuthManager.swift`

### 编辑器系统
- **编辑器视图模型**: `src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`
- **编辑器主视图**: `src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift`
- **画布容器**: `src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift`
- **画布工具栏**: `src/MindCanvas/MindCanvas/Views/Editor/Canvas/CanvasToolbar.swift`

### 画布对象视图
- **可选择箭头视图**: `src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableArrowView.swift`
- **可选择形状视图**: `src/MindCanvas/MindCanvas/Views/Editor/Canvas/SelectableShapeView.swift`
- **形状选择器**: `src/MindCanvas/MindCanvas/Views/Editor/Canvas/ShapePickerPopover.swift`

### 数据模型
- **画布文档**: `src/MindCanvas/MindCanvas/Models/Canvas/CanvasDocument.swift`
- **图层节点**: `src/MindCanvas/MindCanvas/Models/Canvas/LayerNode.swift`
- **箭头节点**: `src/MindCanvas/MindCanvas/Models/Canvas/ArrowLayerNode.swift`
- **形状节点**: `src/MindCanvas/MindCanvas/Models/Canvas/ShapeLayerNode.swift`
- **画布操作**: `src/MindCanvas/MindCanvas/Models/Canvas/CanvasAction.swift`

### 文档
- **产品需求文档**: `docs/prd/v1.0.md`
- **后端架构设计**: `docs/design/backend/backend_architecture.md`
- **开发记录**: `CHANGELOG.md`