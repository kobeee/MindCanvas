# TaskService 实现总结

**文档版本**: v1.0
**创建日期**: 2025-12-27
**状态**: 已完成

---

## 1. 概述

TaskService 是 MindCanvas 后端的核心服务之一，负责处理生图任务的创建、状态查询和异步处理。它整合了 EncryptionService、GoogleAPIClient 和 ImageStorage 三个服务，实现了完整的生图流程。

---

## 2. 创建的文件

### 2.1 核心实现文件

1. **`app/services/task_service.py`** - TaskService 类实现
   - 位置: `/Users/elvis/Documents/codes/一个月一个AI项目挑战/2025/12月/MindCanvas/src/backend/app/services/task_service.py`
   - 大小: 约 600 行代码

### 2.2 测试文件

2. **`tests/test_task_service.py`** - 单元测试
   - 位置: `/Users/elvis/Documents/codes/一个月一个AI项目挑战/2025/12月/MindCanvas/src/backend/tests/test_task_service.py`
   - 说明: 包含 TaskService 的核心功能测试用例

### 2.3 示例文件

3. **`examples/task_service_example.py`** - 使用示例
   - 位置: `/Users/elvis/Documents/codes/一个月一个AI项目挑战/2025/12月/MindCanvas/src/backend/examples/task_service_example.py`
   - 说明: 演示如何使用 TaskService 及相关服务

### 2.4 配置文件更新

4. **`requirements.txt`** - 依赖更新
   - 新增: `pytest==7.4.3`
   - 新增: `pytest-asyncio==0.21.1`
   - 更新: `pydantic-settings==2.8.1`

5. **`.env`** - 环境变量配置
   - 设置: `ENCRYPTION_SECRET_KEY`

---

## 3. TaskService 类结构

### 3.1 类属性

```python
class TaskService:
    def __init__(
        self,
        db: AsyncSession,
        encryption_service: EncryptionService,
        google_client: GoogleAPIClient,
        storage: Optional[ImageStorage] = None
    )
```

**参数说明**:
- `db`: 异步数据库会话
- `encryption_service`: 加密服务实例
- `google_client`: Google API 客户端实例
- `storage`: 图片存储服务实例（可选，默认创建新实例）

### 3.2 公共方法

#### 3.2.1 `create_task`
创建生图任务

```python
async def create_task(
    self,
    user_id: str,
    encrypted_api_key: str,
    prompt: str,
    base_image: Optional[str] = None
) -> str
```

**功能**:
- 创建任务记录到数据库
- 异步处理任务（不阻塞主线程）
- 返回任务 ID

**参数**:
- `user_id`: 用户 ID
- `encrypted_api_key`: 加密的 API Key
- `prompt`: 提示词
- `base_image`: 参考图（可选）

**返回**:
- 任务 ID（UUID 字符串）

**异常**:
- `TaskServiceError`: 如果任务创建失败

#### 3.2.2 `get_task_status`
获取任务状态

```python
async def get_task_status(self, task_id: str) -> Dict[str, Any]
```

**功能**:
- 查询任务状态
- 返回任务详细信息

**参数**:
- `task_id`: 任务 ID

**返回**:
- 任务状态信息字典：
  - `task_id`: 任务 ID
  - `status`: 任务状态（pending/processing/completed/failed）
  - `image_url`: 图片 URL（仅当 status=completed 时）
  - `error_message`: 错误信息（仅当 status=failed 时）

**异常**:
- `TaskNotFoundError`: 如果任务不存在
- `TaskServiceError`: 如果查询失败

#### 3.2.3 `cleanup_old_tasks`
清理过期任务

```python
async def cleanup_old_tasks(self, hours: int = 24) -> int
```

**功能**:
- 清理指定时间前的已完成或失败任务
- 删除关联的图片文件

**参数**:
- `hours`: 保留小时数（默认 24 小时）

**返回**:
- 删除的任务数量

#### 3.2.4 `get_user_tasks`
获取用户的任务列表

```python
async def get_user_tasks(
    self,
    user_id: str,
    status: Optional[str] = None,
    limit: int = 50
) -> list[Dict[str, Any]]
```

**功能**:
- 查询用户的任务列表
- 支持按状态过滤
- 按创建时间倒序排列

**参数**:
- `user_id`: 用户 ID
- `status`: 任务状态过滤（可选）
- `limit`: 返回数量限制（默认 50）

**返回**:
- 任务列表

### 3.3 私有方法

#### 3.3.1 `_process_task`
处理任务（后台异步执行）

```python
async def _process_task(self, task_id: str)
```

**功能**:
- 在后台异步执行任务处理
- 处理流程：
  1. 更新状态为 processing
  2. 解密 API Key（临时内存）
  3. 调用 Google API 生成图片
  4. 保存图片到本地存储
  5. 更新状态为 completed
  6. 清除 API Key（安全措施）

**异常处理**:
- 任何步骤失败都会更新状态为 failed 并清除 API Key

#### 3.3.2 `_update_task_status`
更新任务状态

```python
async def _update_task_status(
    self,
    task_id: str,
    status: str,
    image_url: Optional[str] = None,
    error_message: Optional[str] = None
)
```

**功能**:
- 更新任务状态到数据库
- 支持更新图片 URL 和错误信息

#### 3.3.3 `_clear_api_key`
清除 API Key（安全措施）

```python
async def _clear_api_key(self, task_id: str)
```

**功能**:
- 清除数据库中的 API Key
- 任务完成后必须立即清除
- 即使任务失败也要清除

#### 3.3.4 `_save_image`
保存图片到本地存储

```python
async def _save_image(self, task_id: str, image_data: bytes) -> str
```

**功能**:
- 保存图片到本地存储
- 使用任务 ID 作为文件名
- 图片类型为 GENERATED

**返回**:
- 图片访问 URL

---

## 4. API Key 安全流程

TaskService 实现了完整的 API Key 安全流程：

```
1. iOS APP 加密 API Key (AES-256-GCM)
   ↓
2. HTTPS 传输到后端
   ↓
3. 后端接收加密的 API Key
   ↓
4. 加密存储 API Key (Fernet) 到数据库
   ↓
5. 任务处理时解密 API Key 到内存 (临时)
   ↓
6. 调用 Google API
   ↓
7. 立即清除内存中的 API Key
   ↓
8. 任务完成后删除数据库中的 API Key
```

**安全特性**:
- ✅ 传输加密（HTTPS）
- ✅ 存储加密（Fernet）
- ✅ 临时内存（用完即销毁）
- ✅ 自动清理（任务完成后删除）
- ✅ 日志脱敏（不记录 API Key）

---

## 5. 任务状态管理

### 5.1 状态定义

| 状态 | 说明 |
|------|------|
| `pending` | 任务已创建，等待处理 |
| `processing` | 任务正在处理中 |
| `completed` | 任务已完成，图片已生成 |
| `failed` | 任务失败，查看 error_message |

### 5.2 状态转换

```
pending → processing → completed
    ↓
  failed
```

### 5.3 状态更新时机

- `pending`: 任务创建时
- `processing`: 开始处理任务时
- `completed`: 图片生成成功时
- `failed`: 任何步骤失败时

---

## 6. 异步任务处理

TaskService 使用 `asyncio.create_task` 实现异步任务处理：

```python
# 创建任务后立即启动后台处理
asyncio.create_task(self._process_task(task_id))
```

**优势**:
- 不阻塞主线程
- 提高并发性能
- 支持多个任务同时处理

**注意事项**:
- 后台任务使用独立的数据库会话
- 异常会被捕获并记录到日志
- 失败任务会自动清理 API Key

---

## 7. 错误处理

### 7.1 异常类型

| 异常类型 | 说明 |
|----------|------|
| `TaskNotFoundError` | 任务不存在 |
| `TaskServiceError` | 任务服务异常（基类） |
| `EncryptionError` | 加密服务异常 |
| `DecryptionError` | 解密失败异常 |
| `GoogleAPIError` | Google API 异常 |

### 7.2 错误处理策略

1. **任务创建失败**:
   - 回滚数据库事务
   - 抛出 `TaskServiceError`

2. **任务处理失败**:
   - 更新状态为 `failed`
   - 记录错误信息
   - 清除 API Key
   - 记录日志

3. **API Key 解密失败**:
   - 更新状态为 `failed`
   - 记录错误信息
   - 清除 API Key

4. **Google API 调用失败**:
   - 更新状态为 `failed`
   - 记录错误信息
   - 清除 API Key

5. **图片保存失败**:
   - 更新状态为 `failed`
   - 记录错误信息
   - 清除 API Key

---

## 8. 日志记录

TaskService 使用 Python 标准的 `logging` 模块记录日志：

```python
logger = logging.getLogger(__name__)
```

**日志级别**:
- `INFO`: 关键操作（任务创建、完成、清理）
- `DEBUG`: 详细信息（状态更新、API Key 解密）
- `WARNING`: 警告信息（任务不存在、缺少字段）
- `ERROR`: 错误信息（任务失败、API 错误）

**日志内容**:
- 任务 ID
- 用户 ID
- 操作类型
- 错误信息
- 时间戳

**日志脱敏**:
- 不记录 API Key
- 不记录敏感信息

---

## 9. 测试

### 9.1 单元测试

测试文件: `tests/test_task_service.py`

**测试用例**:
- ✅ 创建任务（成功）
- ✅ 创建任务（缺少参数）
- ✅ 获取任务状态（成功）
- ✅ 获取任务状态（任务不存在）

**测试框架**:
- `pytest==7.4.3`
- `pytest-asyncio==0.21.1`

### 9.2 集成测试

示例文件: `examples/task_service_example.py`

**演示内容**:
- 服务初始化
- API Key 加密
- 任务创建流程
- 任务状态说明
- API Key 安全流程
- 错误处理

---

## 10. 使用示例

### 10.1 初始化服务

```python
from app.services.task_service import TaskService
from app.services.encryption import EncryptionService
from app.services.google_api import GoogleAPIClient
from app.storage.image_storage import ImageStorage
from sqlalchemy.ext.asyncio import AsyncSession

# 初始化服务
task_service = TaskService(
    db=db_session,
    encryption_service=encryption_service,
    google_client=google_client,
    storage=image_storage
)
```

### 10.2 创建任务

```python
# 创建任务
task_id = await task_service.create_task(
    user_id="user-123",
    encrypted_api_key="encrypted_key",
    prompt="A beautiful sunset",
    base_image="base64_image"  # 可选
)

print(f"Task created: {task_id}")
```

### 10.3 查询任务状态

```python
# 查询任务状态
status = await task_service.get_task_status(task_id)

print(f"Task status: {status['status']}")
if status['status'] == 'completed':
    print(f"Image URL: {status['image_url']}")
elif status['status'] == 'failed':
    print(f"Error: {status['error_message']}")
```

### 10.4 获取用户任务列表

```python
# 获取用户的任务列表
tasks = await task_service.get_user_tasks(
    user_id="user-123",
    status="completed",
    limit=50
)

for task in tasks:
    print(f"Task {task['task_id']}: {task['status']}")
```

### 10.5 清理过期任务

```python
# 清理 24 小时前的任务
deleted_count = await task_service.cleanup_old_tasks(hours=24)

print(f"Deleted {deleted_count} old tasks")
```

---

## 11. 注意事项

### 11.1 数据库会话管理

- TaskService 使用外部传入的数据库会话
- 后台任务会创建新的会话，避免与外层会话冲突
- 所有数据库操作都有事务管理

### 11.2 API Key 安全

- API Key 必须加密后传输
- API Key 加密存储到数据库
- API Key 只在任务处理时解密到内存
- 任务完成后立即清除 API Key

### 11.3 异步任务

- 使用 `asyncio.create_task` 启动后台任务
- 后台任务不阻塞主线程
- 异常会被捕获并记录到日志

### 11.4 错误处理

- 所有公共方法都有异常处理
- 异常类型明确
- 错误信息详细

---

## 12. 性能优化

### 12.1 异步处理

- 所有 I/O 操作都是异步的
- 支持并发处理多个任务
- 不阻塞主线程

### 12.2 数据库优化

- 使用索引优化查询
- 批量操作减少数据库访问
- 连接池管理

### 12.3 图片存储

- 异步文件读写
- 支持本地存储和云存储
- 自动清理过期图片

---

## 13. 扩展性

### 13.1 支持多个 AI 服务提供商

当前实现支持 Google Nano Banana Pro API，可以扩展支持其他 AI 服务：

```python
class TaskService:
    def __init__(
        self,
        db: AsyncSession,
        encryption_service: EncryptionService,
        google_client: GoogleAPIClient,
        openai_client: Optional[OpenAIClient] = None,  # 新增
        stability_client: Optional[StabilityClient] = None,  # 新增
        storage: Optional[ImageStorage] = None
    ):
        self.google_client = google_client
        self.openai_client = openai_client  # 新增
        self.stability_client = stability_client  # 新增
```

### 13.2 支持任务优先级

可以扩展支持任务优先级：

```python
async def create_task(
    self,
    user_id: str,
    encrypted_api_key: str,
    prompt: str,
    base_image: Optional[str] = None,
    priority: int = 0  # 新增
) -> str:
    task = Task(
        user_id=user_id,
        encrypted_api_key=encrypted_api_key,
        prompt=prompt,
        base_image=base_image,
        status="pending",
        priority=priority  # 新增
    )
```

### 13.3 支持任务取消

可以扩展支持任务取消：

```python
async def cancel_task(self, task_id: str) -> bool:
    """取消任务"""
    await self._update_task_status(task_id, "cancelled")
    return True
```

---

## 14. 问题与解决方案

### 14.1 问题：数据库会话冲突

**问题**: 后台任务使用数据库会话时可能与外层会话冲突

**解决方案**:
- 后台任务使用独立的数据库会话
- 每个方法内部创建新会话
- 确保会话正确关闭

### 14.2 问题：API Key 泄露风险

**问题**: API Key 可能在日志、错误信息中泄露

**解决方案**:
- 日志中不记录 API Key
- 错误信息脱敏
- 使用完立即清除

### 14.3 问题：任务处理失败后 API Key 未清除

**问题**: 任务处理失败可能跳过 API Key 清除

**解决方案**:
- 使用 try-except-finally 确保清除
- 任何异常都会触发清除
- 清除失败不影响主流程

---

## 15. 总结

TaskService 已成功实现，具备以下特性：

✅ **完整的功能实现**:
- 任务创建
- 状态查询
- 异步处理
- 任务清理
- 用户任务列表

✅ **API Key 安全**:
- 加密传输
- 加密存储
- 临时内存
- 自动清理

✅ **异步处理**:
- 不阻塞主线程
- 支持并发
- 高性能

✅ **错误处理**:
- 完善的异常捕获
- 详细的错误信息
- 自动清理

✅ **日志记录**:
- 完整的操作日志
- 日志脱敏
- 便于排查问题

✅ **可测试性**:
- 单元测试
- 集成测试示例
- Mock 支持良好

TaskService 已准备好集成到 FastAPI 路由层，提供完整的生图服务 API。

---

## 16. 下一步工作

1. **实现 API 路由层**:
   - `POST /api/v1/generate/tasks` - 创建任务
   - `GET /api/v1/generate/tasks/{task_id}/status` - 查询状态
   - `GET /api/v1/generate/tasks/user/{user_id}` - 用户任务列表

2. **集成到 FastAPI 应用**:
   - 创建路由文件
   - 添加依赖注入
   - 实现请求验证

3. **完善测试**:
   - 添加更多测试用例
   - 集成测试
   - 性能测试

4. **文档完善**:
   - API 文档
   - 使用指南
   - 部署指南

---

**文档结束**