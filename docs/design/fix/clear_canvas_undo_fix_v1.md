# 清屏撤销问题修复验证计划

## 修复概述

通过深入分析发现，清屏撤销问题的根本原因是 `ClearCanvasAction` 只保存了图层(`LayerNode`)和画笔数据，遗漏了箭头、形状、矩形、文字、标注等其他图形对象。

### 修复内容

1. **扩展 ClearCanvasAction 结构**：
   - 添加 `previousArrows: [ArrowLayerNode]`
   - 添加 `previousShapes: [ShapeLayerNode]`
   - 添加 `previousRectangles: [RectangleLayerNode]`
   - 添加 `previousTexts: [TextLayerNode]`
   - 添加 `previousAnnotations: [AnnotationLayerNode]`

2. **新增 NativeCanvasView 方法**：
   - `getArrows() -> [ArrowLayerNode]`
   - `getShapes() -> [ShapeLayerNode]`
   - `getRectangles() -> [RectangleLayerNode]`
   - `getTexts() -> [TextLayerNode]`
   - `getAnnotations() -> [AnnotationLayerNode]`

3. **更新 NativeEditorView 清屏逻辑**：
   - 捕获所有类型图形对象而不仅仅是图层和画笔
   - 添加详细日志记录对象统计信息

4. **增强 ClearCanvasAction.undo() 方法**：
   - 按类型恢复所有图形对象
   - 添加详细的恢复过程日志

## 验证测试计划

### 测试场景 1：基础功能验证

**步骤**：
1. 创建一个新画布
2. 使用画笔工具绘制一些笔画
3. 使用箭头工具创建几个箭头
4. 使用形状工具创建几个形状（矩形、圆形、三角形等）
5. 点击清屏按钮
6. 点击撤销按钮

**预期结果**：
- ✅ 画笔内容完全恢复
- ✅ 所有箭头完全恢复
- ✅ 所有形状完全恢复
- ✅ 对象位置、颜色、大小等属性保持不变
- ✅ 控制台输出详细的恢复日志

### 测试场景 2：复杂场景验证

**步骤**：
1. 创建包含多种对象的复杂画布：
   - 多层图片叠加
   - 多个不同类型的箭头
   - 多个不同类型的形状
   - 标注对象
2. 对部分对象进行旋转、缩放操作
3. 执行清屏操作
4. 执行撤销操作

**预期结果**：
- ✅ 所有对象完全恢复
- ✅ 对象的变换状态（旋转、缩放）保持不变
- ✅ 对象的层级关系保持不变
- ✅ 控制台输出详细的统计和恢复日志

### 测试场景 3：边界情况验证

**步骤**：
1. 测试空画布清屏撤销
2. 测试只有画笔的画布清屏撤销
3. 测试只有图形对象的画布清屏撤销
4. 测试大量对象（性能测试）

**预期结果**：
- ✅ 空画布撤销正常，无错误日志
- ✅ 部分对象类型撤销正常
- ✅ 大量对象撤销性能可接受

## 关键日志验证

### 清屏操作日志
```
[ClearCanvas] 开始清屏，当前对象统计:
[ClearCanvas] - 图层: X
[ClearCanvas] - 箭头: X
[ClearCanvas] - 形状: X
[ClearCanvas] - 矩形: X
[ClearCanvas] - 文字: X
[ClearCanvas] - 标注: X
[ClearCanvas] - 画笔数据: X 字节
[ClearCanvas] 清屏操作完成
```

### 撤销操作日志
```
[ClearCanvas] 开始撤销清屏操作
[ClearCanvas] 恢复对象统计 - 图层:X, 箭头:X, 形状:X, 矩形:X, 文字:X, 标注:X
[ClearCanvas] 恢复 X 个图层
[ClearCanvas] 恢复 X 个箭头
[ClearCanvas] 恢复 X 个形状
[ClearCanvas] 恢复 X 个矩形
[ClearCanvas] 恢复 X 个标注
[ClearCanvas] 恢复画笔数据，大小: X 字节
[ClearCanvas] 撤销清屏操作完成
```

## 代码修改清单

| 文件 | 修改类型 | 关键变更 |
|-----|---------|---------|
| `Models/Canvas/CanvasAction.swift` | 修改 | 扩展ClearCanvasAction结构，添加所有图形对象支持 |
| `Views/Editor/Canvas/NativeCanvasView.swift` | 修改 | 添加获取所有图形对象的方法 |
| `Views/Editor/NativeEditorView.swift` | 修改 | 更新清屏逻辑捕获所有对象类型 |

## 风险评估

### 低风险
- ✅ 修改仅影响清屏撤销功能
- ✅ 向后兼容，不影响现有数据结构
- ✅ 添加了详细日志便于问题排查

### 注意事项
- ⚠️ 文字工具尚未完全实现，相关代码已添加TODO标记
- ⚠️ 需要在真机上测试性能表现
- ⚠️ 需要验证大量对象场景下的内存使用

## 验收标准

- [ ] 所有测试场景通过
- [ ] 控制台日志输出正确
- [ ] 无性能回归
- [ ] 无内存泄漏
- [ ] 代码审查通过

## 后续优化建议

1. **性能优化**：考虑使用更高效的数据快照机制
2. **内存管理**：对于大量对象场景，考虑分批恢复
3. **扩展性**：为未来新增图形类型提供扩展机制
4. **测试覆盖**：添加自动化测试用例