# MindCanvas 原生编辑器 v4 详情页优化设计方案（仅设计，不动代码）

## 1. 背景与问题拆解

### 1.1 当前痛点（来自反馈与截图）

- **Magic Frame 不丝滑/失控**：拖拽或缩放过程中“越拖越飞”、容易直接飞出屏幕。
- **找回内容困难**：当选框/内容飞出视口后，用户无法通过拖动画布快速找回。
- **缩放体验缺失**：缺少显式缩放比例展示与可控调节入口。
- **绘图模式输入受限**：当前策略偏向 Pencil-only，但调试/模拟器场景需要鼠标也能画。
- **手势冲突复杂**：对象拖拽、画布平移、绘图输入、缩放/旋转同时存在。

### 1.2 v4 的核心决策（已确认）

- **Magic Frame 固定在屏幕坐标系（HUD/Viewport Space）**：不随画布缩放/漫游移动。
- **Magic Frame 仍可拖动/缩放**：其 frame 始终是“屏幕坐标”。
- **截图/生成区域**：永远截取“屏幕选框对应的画布内容区域”。

> 设计目标：降低复杂度 + 提升稳定性与可预期性。

---

## 2. 坐标系定义与数据流（v4 的关键）

### 2.1 坐标系

- **Viewport/Screen Space（屏幕坐标）**：以 `NativeCanvasContainer` 可视区域为参照；Magic Frame 的 `CGRect` 以此为基准。
- **Canvas Content Space（画布内容坐标）**：`NativeCanvasView.contentView` 的内部坐标系（5000×5000）。
- **Scroll Space（滚动容器状态）**：`UIScrollView.contentOffset` + `zoomScale` 定义当前 viewport 在 content 上的位置与缩放。

### 2.2 关键换算（屏幕框 → 内容框）

给定：

- `frame_screen`: Magic Frame 在屏幕坐标的 rect（相对于画布容器视口）
- `zoom = scrollView.zoomScale`
- `offset = scrollView.contentOffset`
- `inset = scrollView.adjustedContentInset`（若有）

则内容坐标中的截取区域：

- `frame_content.origin = (offset + frame_screen.origin - viewportOriginAdjust) / zoom`
- `frame_content.size = frame_screen.size / zoom`

其中 `viewportOriginAdjust` 用于处理：

- scrollView 内 content 居中（`scrollViewDidZoom` 中的 center 调整）可能带来的视觉偏移
- 安全区/容器 padding

**v4 设计要求**：

- 明确“哪一个视图作为 viewport 原点”：以 **`NativeCanvasViewWrapper` 的 bounds（SwiftUI 容器）** 为准；其与 `scrollView` 的坐标需要通过一次性映射函数统一。

### 2.3 截图渲染策略

- 截图输入必须使用 **内容坐标 rect**（`frame_content`），并在渲染时保证：
- 取到 `contentView` 当前的可见状态（含 object layer + pencil layer）
- 与 zoomScale、contentOffset 一致

v4 推荐的“定义正确性”判定：

- 用户将某个明显标记（比如一张图片角落）放入选框内，生成截图预览（可选）应当包含该标记且位置正确。

---

## 3. Magic Frame（HUD 选框）交互设计

### 3.1 行为约束（防飞走）

- **屏幕边界约束**：选框必须始终被限制在 viewport 内（可允许少量外溢 8–16pt 用于手柄，但主体不出界）。
- **最小尺寸**：保留 100×100（可配置）。
- **最大尺寸**：不得超过 viewport（减去安全边距）。

### 3.2 拖拽/缩放手感

- **必须使用“起始快照”+“增量应用”**：
- onChanged 使用 `startFrame + translationDelta` 计算，而不是在每帧累加到已变更 frame。
- **节流与动画**：
- onChanged 不做动画（避免抖动）
- onEnded 可做轻微吸附/回弹动画（如果超出边界则回到边界）

### 3.3 命中测试（让画布能拖）

- HUD 选框可交互区域仅限：
- 边框/内部拖拽区域
- 四角手柄
- 选框之外的 overlay 必须 **不拦截手势**（否则会影响 scrollView 漫游）。

---

## 4. 画布漫游与缩放（Infinite Canvas）

### 4.1 对象模式（Object Mode）

- **单指/鼠标拖空白处**：平移画布（scrollView pan）。
- **单指/鼠标拖对象**：移动对象（对象 pan）。
- **双指捏合 / 触控板缩放手势**：缩放画布（scrollView zoom）。
- **对象缩放/旋转**：
- 仅在对象上执行双指缩放/旋转（对象优先）
- 同时提供“锁定对象”避免误触

### 4.2 绘图模式（Drawing Mode，any-input）

你已选择：**任何输入都能画**。

- **单指/鼠标左键拖动**：绘制。
- **双指拖动 / 触控板两指滚动**：平移画布。
- **双指捏合 / 触控板缩放**：缩放画布。
- （可选增强）**空格键按住拖动**：平移画布（桌面类习惯；iPad 外接键盘也可用）。

> 这套规则的核心是：绘图模式下，单指不再承担“平移画布”，平移交给双指/触控板/键盘。

---

## 5. 左下角缩放比例控件（Zoom HUD）

### 5.1 UI 规格

- **位置**：左下角，贴近画布区域（不在全局 sidebar）。
- **布局**：`[-]  [ 100% ]  [+]`
- 中间百分比可点击进入编辑（支持输入 10–400 的百分比，最终 clamp 到 min/max）。

### 5.2 行为

- `-`：按步进缩小（默认 10% 或 1/1.1，二选一；推荐 10% 便于预期）。
- `+`：按步进放大。
- 文本输入：回车/失焦应用。
- 与手势同步：
- 用户 pinch 缩放后，百分比实时更新。

---

## 6. 手势冲突与优先级策略（设计层约束）

### 6.1 总原则

- **同一时刻只有一个“主交互”占用单指拖动**：
- 对象模式：对象拖动 或 画布平移（二者互斥）
- 绘图模式：绘制（单指）优先

### 6.2 优先级（建议）

- Magic Frame 手势 > 对象手势 > scrollView 手势（仅在命中区域）
- 空白区域：scrollView 手势优先
- 绘图模式：PKCanvasView（绘制）对单指优先；scrollView 仅响应双指/触控板滚动

---

## 7. 生成截图的“正确性与可解释性”

### 7.1 需要新增的概念（设计要求）

- **Viewport Snapshot Rect**：以屏幕选框为输入
- **Content Snapshot Rect**：通过映射得到的内容坐标 rect

### 7.2 可选的用户反馈（不一定 v4 就做）

- 在点击“生成”前提供一个“预览截取区域”的轻量预览（仅用于验证坐标换算正确性）。

---

## 8. 验收标准（v4）

### 8.1 Magic Frame

- 拖动/缩放跟手、无漂移、无加速。
- 永远不会飞出 viewport；松手后如越界会回弹到边界。
- 选框固定在屏幕，不随画布缩放/漫游移动。

### 8.2 画布漫游

- 对象模式：空白处可单指拖动平移画布；捏合缩放可用。
- 绘图模式（any-input）：
- 单指/鼠标能画
- 双指/触控板能平移与缩放

### 8.3 缩放控件

- 左下角显示正确百分比（与手势缩放同步）。
- `+/-` 步进缩放稳定。
- 输入百分比可用且有 clamp。

### 8.4 截图/生成区域

- 生成截图内容与屏幕选框看到的内容一致（考虑缩放/偏移后仍正确）。

---

## 9. 测试用例（设计层）

- **Case A（基础拖拽）**：选框拖到四个角落，松手不越界。
- **Case B（连续缩放）**：持续拉伸/缩小选框 10 次，尺寸变化线性、无跳变。
- **Case C（缩放后生成）**：画布缩放到 50%/200%，选框固定屏幕，生成截图内容正确。
- **Case D（漫游找回）**：把对象拖到远处（画布内容坐标偏大），通过画布平移找回。
- **Case E（鼠标绘制）**：模拟器或外接鼠标拖动可画；触控板两指滚动能平移。

---

## 10. 影响范围（后续落地时的文件级清单，仅用于评估）

- `src/MindCanvas/MindCanvas/Views/Editor/Canvas/MagicFrameView.swift`
- 拖拽/缩放算法与边界约束
- hit-testing 规则
- `src/MindCanvas/MindCanvas/Views/Editor/Canvas/NativeCanvasView.swift`
- 暴露 scrollView 状态（zoom/contentOffset）供 SwiftUI HUD 使用
- 提供“屏幕→内容 rect”映射方法或回调
- 绘图模式 any-input 下的手势策略
- `src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift`
- 新增 Zoom HUD 视图
- 串联工具模式与输入策略
- `src/MindCanvas/MindCanvas/ViewModels/CanvasStateManager.swift`
- 保存 MagicFrame（屏幕坐标）与 Zoom 百分比展示状态
- （可选）保存 viewport 尺寸用于边界计算

---

## 11. 设计后的落地顺序（未来执行，不在本次进行）

1. 修复 MagicFrame 的增量计算与边界约束（立刻改善“飞走”）。
2. 建立屏幕→内容的 rect 映射，并让截图走内容 rect。
3. 打通 scrollView zoomScale 与 Zoom HUD。
4. 调整绘图模式为 any-input，并定义平移/缩放的替代手势（双指/触控板）。
5. 最后统一手势优先级与命中测试，做一次整体回归。
