# 编辑器交互问题修复方案 v1.1（Zoom / 触控板 / Sheet / 绘画漂移 / 图生图预览）

| 版本 | 日期 | 说明 |
|:---|:---|:---|
| v1.1 | 2025-12-12 | 基于 v1.0 的问题排查结论，给出唯一最佳实践修复方案（不再给 A/B 选项）。 |

---

## 背景与目标

近期在 **macOS Simulator（预览器）+ MacBook 触控板** 场景下暴露出以下问题：

- Zoom HUD 的百分比文本会“卡死”，但缩放本体正常
- 触控板双指捏合无法缩放；按压拖拽变成移动
- 文生图 Sheet 点外部关闭后无法再次打开
- 绘画时笔画漂移（按住漂移，松手恢复）
- 图生图预览（选框蓝框区域）空白/漏层，且存在坐标系回填错位风险

本方案目标：

- **单一事实来源**：任何 UI 的显隐状态必须只有一个状态源
- **输入模型统一**：明确区分 Touch（屏幕多点触控）与 Indirect（触控板/鼠标滚轮）输入，并显式支持 Simulator
- **坐标系统一**：Magic Frame 一律以“视口坐标”存储，截图与回填一律转换为“画布内容坐标”
- **截图链路确定性**：避免 `drawHierarchy` 对 PencilKit 的不稳定渲染，改为 PencilKit 官方导出 + Layer 渲染合成

---

## 影响范围（需要修改的文件）

- `src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift`
- `src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`
- `src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift`
- `src/MindCanvas/MindCanvas/Views/Editor/Canvas/ResizableImageView.swift`

---

## 问题 1：Zoom HUD 百分比卡死（缩放本体正常）

### 根因（已确认）

`NativeEditorView` 内部把“用户编辑态”错误绑定在 `zoomText` 的变化上：程序同步 `zoomText` 也会触发 `.onChange(zoomText)`，导致 `isEditingZoom` 被永久置为 `true`，从而阻断后续 `zoomScale -> zoomText` 的同步。

另外 `keyboardType(.numberPad)` 在 iPad/Simulator 场景下通常没有可靠的 `onSubmit`，导致无法自动退出编辑态。

### 修复方案（唯一方案）

1. **用焦点作为“是否编辑”的唯一依据**  
   - Zoom 文本框采用 `FocusState`（或等效机制）判断是否在编辑中  
   - 删除“只要 zoomText 变更就进入编辑态”的逻辑

2. **引入“草稿值”与“已生效值”分离**  
   - `zoomPercentDraft`（仅用于 TextField 输入）  
   - `stateManager.zoomScale`（唯一缩放事实源）  
   - 当 TextField 未聚焦时：`zoomPercentDraft = Int(zoomScale * 100)`  
   - 当 TextField 聚焦时：不再被缩放回调覆盖

3. **提供显式“完成/应用”入口**（必须）  
   - 为数字键盘提供 Done（键盘工具栏按钮）或 HUD 内“应用”按钮  
   - Done/应用时解析百分比并调用 `canvasView.setZoomScale(...)`，随后清理焦点

### 验收标准

- 连续点击 `-`：100 → 90 → 80 → … HUD 百分比连续更新
- 连续点击 `+`：100 → 110 → 120 → … HUD 百分比连续更新
- 通过手势缩放/滚轮缩放后：HUD 百分比持续同步
- 手动输入后点击 Done/应用：缩放生效，HUD 正常退出编辑态

---

## 问题 2：Simulator 触控板双指缩放/漫游不可用

### 根因（已确认）

Simulator + 触控板属于 **Indirect 输入**（scroll wheel / pointer drag / trackpad gesture），与 iPad 触屏的 Touch 多点手势不同。当前实现只覆盖 Touch（`minimumNumberOfTouches`、pinch recognizer 仲裁），完全未配置 Indirect 输入的手势接入（例如 `allowedScrollTypesMask` / `allowedTouchTypes`）。

### 修复方案（唯一方案）

在 `NativeCanvasView` 中，明确把滚动画布与缩放画布的输入源分成两类，并显式允许 Indirect：

1. **Scroll（平移）统一交给外层 `scrollView`，并显式允许 scroll wheel**
   - 配置 `scrollView.panGestureRecognizer.allowedScrollTypesMask` 包含 `.continuous`（触控板两指滑动）与必要时的 `.discrete`
   - 保持 Touch 场景下：
     - 对象模式：单指可平移（`minimumNumberOfTouches = 1`）
     - 绘图模式：双指可平移（`minimumNumberOfTouches = 2`）
   - 对 Indirect 场景：不依赖 `minimumNumberOfTouches`，由 `allowedScrollTypesMask` 接管

2. **Zoom（缩放）使用 `scrollView` 自带 pinch 缩放，并显式允许 Indirect touch types**
   - 配置 `scrollView.pinchGestureRecognizer?.allowedTouchTypes` 包含：
     - `.direct`（触屏）
     - `.indirect` / `.indirectPointer`（触控板/鼠标相关，具体由系统投递决定）
   - 同时在对象层（图片）与 PencilKit 之间建立“画布缩放优先”的仲裁规则（见下文问题 4/ResizableImageView）

3. **Simulator 的用户体验兜底（必须）**
   - 触控板“捏合”在部分 Simulator 版本可能不会投递为 pinch；因此必须保证 Zoom HUD 的 +/- 可连续工作，作为桌面端缩放主入口（问题 1 修复后自然满足）
   - 建议补充桌面习惯的缩放快捷方式（例如 `⌘ + 滚轮`），但实现细节不在本方案强制范围内

### 验收标准

- Simulator：触控板两指滑动能稳定平移画布
- Simulator：触控板捏合若系统投递 magnify，则能缩放；若不投递，HUD 作为兜底仍可完成所有缩放操作
- 真机：触屏 pinch 缩放正常；对象/绘图模式的平移规则不被破坏

---

## 问题 3：文生图 Sheet 点外部关闭后无法再次打开

### 根因（已确认）

当前 `NativeEditorView` 用两套状态驱动 sheet：

- View 本地：`activeSheet: ActiveSheet?`
- ViewModel：`isTextToImagePresented / isImageToImageConfirmPresented`

当用户点外部 dismiss，系统只会把 `activeSheet = nil`，但 ViewModel 的 Bool 仍为 true，导致再次点击按钮时状态未变化、`.onChange` 不触发，表现为“按钮没反应”。

### 修复方案（唯一方案：以 View 的 `activeSheet` 作为唯一事实源）

1. **删除 ViewModel 中的两个 sheet Bool 状态**  
   - `isTextToImagePresented`
   - `isImageToImageConfirmPresented`

2. **由 View 直接设置 `activeSheet`**  
   - 点击“文生图”：`activeSheet = .txt2img`
   - 点击“图生图”：先在 ViewModel 执行“准备预览”拿到 preview；若成功则 `activeSheet = .img2imgConfirm`

3. **在 `.sheet(item:)` 的 `onDismiss` 中统一清理流程状态**
   - 文生图：无 pending 状态，dismiss 不需要额外逻辑
   - 图生图：dismiss 时必须调用 ViewModel 的 `cancelImageToImageFlow()`，清掉 pending 预览与 base64

4. **确保按钮永远可见**
   - `TextToImageSheet` / `ImageToImageConfirmSheet` 的 actions 必须固定在安全区域底部或整体可滚动，避免 `.medium` detent + 键盘挤压导致“看不到确认按钮”

### 验收标准

- 点外部关闭后，再点按钮必定再次弹出
- 任意 detent、键盘弹起时，“取消/确认（生成）”按钮始终可见且可点

---

## 问题 4：绘画时笔画漂移（按住漂移，松手恢复）

### 根因（已确认）

在 Simulator + 触控板场景，用户“按压拖拽”的 Indirect 输入会触发外层 `UIScrollView` 的平移/滚动，导致绘制中的坐标系发生变化。PencilKit 绘制过程存在临时渲染与最终提交阶段：绘制中坐标系变化会导致视觉漂移；松手提交后又回到最终坐标系，看起来“恢复原位”。

### 修复方案（唯一方案：绘制期间强制冻结画布变换）

1. **绘制开始（`canvasViewDidBeginUsingTool`）时冻结外层 scroll 变换**
   - 禁用外层 `scrollView` 的 pan / pinch（同时覆盖 Touch 与 Indirect）
   - 同时禁用任何“scroll wheel 平移”输入（通过 `allowedScrollTypesMask` 临时置空或关闭对应 recognizer）

2. **绘制结束（`canvasViewDidEndUsingTool`）时恢复外层 scroll 变换**
   - 恢复 pan / pinch
   - 恢复 `allowedScrollTypesMask`

3. **在绘图模式下的“漫游”只允许发生在未绘制中**
   - 双指平移 / 触控板两指平移必须在 `isDrawing == false` 时才生效
   - 这条规则是为了保证 PencilKit 的输入坐标系在一次 stroke 生命周期内保持不变

### 验收标准

- Simulator：绘制时不再漂移；松手前后位置一致
- Simulator：未绘制时仍可通过触控板两指滑动平移画布
- 真机：Apple Pencil/手指绘制体验不受负面影响

---

## 问题 5：图生图预览空白/漏层 + 回填坐标错位风险

### 根因（已确认）

1. 预览截图链路使用 `drawHierarchy` 渲染 `PKCanvasView`，在 offscreen renderer 下极易出现漏画/空白  
2. 生成回填时直接使用 `magicFrame`（视口坐标）作为生成图层的 frame（内容坐标），存在必然错位风险

### 修复方案（唯一方案：确定性截图 + 统一坐标系）

#### 5.1 坐标系统一规则（必须）

- `CanvasStateManager.magicFrame` 的语义固定为：**视口坐标（viewport / 屏幕坐标）**
- 任何与图层、回填相关的 frame 必须转换为：**画布内容坐标（contentView 坐标）**

因此在 ViewModel 的图生图流程里：

- 截图：`viewportRect = magicFrame` → `contentRect = canvasView.contentRect(forViewportRect: viewportRect)` → 以 `contentRect` 截图
- 回填：生成图层的 `frame` 必须使用 `contentRect`（而不是 `magicFrame`）

#### 5.2 截图链路（必须替换 `drawHierarchy`）

目标：稳定得到“对象层 + PencilKit 绘制层”的合成截图，并支持裁剪 `contentRect`。

实现原则：

1. **PencilKit 层使用官方导出**
   - 从 `PKDrawing` 导出 image：`PKDrawing.image(from: contentRect, scale: ...)`
   - 这样得到的绘制图像是确定性的，不依赖 `drawHierarchy`

2. **对象层使用 Core Animation 渲染**
   - 对 `objectLayerView.layer` 做裁剪渲染（clip 到 `contentRect`），使用 `CALayer.render(in:)`
   - 避免 `drawHierarchy` 的不确定性与 afterScreenUpdates 时序问题

3. **合成**
   - 用 `UIGraphicsImageRenderer` 以 `contentRect.size` 为画布：
     - 先绘制对象层裁剪图
     - 再叠加 PencilKit 裁剪图（透明背景）

4. **边界校验**
   - `contentRect` 必须与 `contentView.bounds` 取交集
   - 当 `contentRect` 宽高过小或为空时，明确返回 nil 并在 UI 上给出“选框过小/无有效内容”的提示（避免出现空 sheet）

#### 5.3 Sheet 预览展示保证

`NativeEditorView` 在展示 `.img2imgConfirm` 时不得出现“空内容”sheet：

- 预览准备失败时不打开 sheet，而是在控制面板给出明确原因（例如“选框无效/截图失败”）
- 只有 `previewImage != nil` 才设置 `activeSheet = .img2imgConfirm`

### 验收标准

- 图生图预览：对象层与画笔层均可见，不再空白/漏层
- 选框区域与预览区域一致（所见即所得）
- 生成回填：生成图片落点与选框一致（无明显偏移）

---

## 全量验收清单（建议按顺序验证）

### A. Zoom HUD

- [ ] 连点 +/- 百分比持续变化
- [ ] 手动输入 + Done/应用 生效，且退出编辑态
- [ ] 缩放手势/滚轮后 HUD 同步

### B. Simulator（触控板）

- [ ] 两指滑动：平移画布可用
- [ ] 绘制中：不会触发画布移动/缩放（无漂移）
- [ ] 未绘制：允许漫游
- [ ] 捏合：若系统投递 magnify 则可缩放；否则 HUD 缩放兜底可用

### C. Sheet

- [ ] 文生图：点外部关闭后仍能再次打开
- [ ] 图生图：预览永不空白；点外部关闭能正确清理 pending

### D. 图生图截图与回填

- [ ] 预览截图包含对象层 + 画笔层
- [ ] 预览区域与选框一致
- [ ] 生成回填位置与选框一致

---

## 备注：关于“Simulator vs 真机”的定位原则

本方案明确把 Simulator 触控板纳入支持范围，但必须接受一个客观事实：

- **触控板输入不是 Touch 多点触控**，必须用 Indirect 输入模型处理
- 因此“画布变换冻结（绘制期间）”是解决漂移的关键，它不依赖硬件差异

只要按本方案落实：真机与 Simulator 将共享同一套可预期的交互规则与截图链路。


