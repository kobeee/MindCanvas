# 数据库模型和连接层实现总结

**实施日期**: 2025-12-27
**状态**: 已完成
**版本**: 1.0.0

---

## 1. 创建的文件列表

### 1.1 数据库连接层

| 文件路径 | 说明 |
|---------|------|
| `/src/backend/app/database/connection.py` | 数据库连接管理，提供异步会话和依赖注入 |
| `/src/backend/app/database/base.py` | SQLAlchemy Base 模型，定义混入类 |
| `/src/backend/app/database/__init__.py` | 数据库模块导出 |

### 1.2 数据模型

| 文件路径 | 说明 |
|---------|------|
| `/src/backend/app/models/user.py` | 用户模型 (User) |
| `/src/backend/app/models/asset.py` | 资源模型 (Asset) |
| `/src/backend/app/models/feed.py` | 社区动态模型 (FeedItem) |
| `/src/backend/app/models/task.py` | 生图任务模型 (Task) |
| `/src/backend/app/models/report.py` | 举报模型 (Report) |
| `/src/backend/app/models/schemas.py` | Pydantic 请求/响应模型 |
| `/src/backend/app/models/__init__.py` | 模型模块导出 |

### 1.3 测试文件

| 文件路径 | 说明 |
|---------|------|
| `/src/backend/tests/test_models.py` | 模型结构验证测试 |
| `/src/backend/tests/__init__.py` | 测试模块导出 |

---

## 2. 数据库模型详情

### 2.1 User 模型 (用户表)

**表名**: `users`

**关键字段**:
- `id` (UUID, PK) - 主键
- `email` (VARCHAR, UNIQUE) - 邮箱
- `username` (VARCHAR) - 用户名
- `auth_provider` (VARCHAR) - 认证提供者 ('apple', 'google', 'github', 'email')
- `provider_id` (VARCHAR) - 第三方唯一 ID
- `avatar_url` (VARCHAR) - 头像 URL
- `created_at` (TIMESTAMP) - 创建时间
- `updated_at` (TIMESTAMP) - 更新时间

**关系**:
- `assets` - 一对多，关联用户的资源
- `tasks` - 一对多，关联用户的任务
- `feed_items` - 一对多，关联用户发布的动态
- `reports` - 一对多，关联用户提交的举报

**索引**:
- `idx_users_email` - email 字段
- `idx_users_provider_id` - provider_id 字段

---

### 2.2 Asset 模型 (资源表)

**表名**: `assets`

**关键字段**:
- `id` (UUID, PK) - 主键
- `user_id` (UUID, FK) - 用户 ID
- `url` (VARCHAR) - 图片 URL
- `type` (VARCHAR) - 资源类型 ('upload', 'generated')
- `prompt` (TEXT) - 生成提示词
- `model_version` (VARCHAR) - 模型版本
- `is_public` (BOOLEAN) - 是否公开
- `created_at` (TIMESTAMP) - 创建时间
- `updated_at` (TIMESTAMP) - 更新时间

**关系**:
- `user` - 多对一，关联用户
- `feed_item` - 一对一，关联社区动态

**索引**:
- `idx_assets_user_id` - user_id 字段
- `idx_assets_type` - type 字段
- `idx_assets_is_public` - is_public 字段
- `idx_assets_created_at` - created_at 字段

---

### 2.3 FeedItem 模型 (社区动态表)

**表名**: `feed_items`

**关键字段**:
- `id` (UUID, PK) - 主键
- `asset_id` (UUID, FK, UNIQUE) - 资源 ID
- `user_id` (UUID, FK) - 作者 ID
- `title` (VARCHAR) - 标题
- `likes_count` (INT) - 点赞数
- `published_at` (TIMESTAMP) - 发布时间
- `created_at` (TIMESTAMP) - 创建时间
- `updated_at` (TIMESTAMP) - 更新时间

**关系**:
- `asset` - 多对一，关联资源
- `user` - 多对一，关联作者
- `reports` - 一对多，关联举报

**索引**:
- `idx_feed_items_asset_id` - asset_id 字段
- `idx_feed_items_user_id` - user_id 字段
- `idx_feed_items_published_at` - published_at 字段

---

### 2.4 Task 模型 (生图任务表)

**表名**: `generation_tasks`

**关键字段**:
- `id` (UUID, PK) - 主键
- `user_id` (UUID, FK) - 用户 ID
- `status` (VARCHAR) - 任务状态 ('pending', 'processing', 'completed', 'failed')
- `prompt` (TEXT) - 提示词
- `base_image` (TEXT) - 参考图
- `encrypted_api_key` (TEXT) - 加密的 API Key（任务完成后删除）
- `image_url` (VARCHAR) - 生成的图片 URL
- `error_message` (TEXT) - 错误信息
- `created_at` (TIMESTAMP) - 创建时间
- `updated_at` (TIMESTAMP) - 更新时间

**关系**:
- `user` - 多对一，关联用户

**索引**:
- `idx_generation_tasks_user_id` - user_id 字段
- `idx_generation_tasks_status` - status 字段
- `idx_generation_tasks_created_at` - created_at 字段

---

### 2.5 Report 模型 (举报表)

**表名**: `reports`

**关键字段**:
- `id` (UUID, PK) - 主键
- `feed_item_id` (UUID, FK) - 被举报内容 ID
- `reporter_id` (UUID, FK) - 举报人 ID
- `reason` (VARCHAR) - 举报原因
- `description` (TEXT) - 举报描述
- `status` (VARCHAR) - 举报状态 ('pending', 'reviewed', 'resolved', 'dismissed')
- `created_at` (TIMESTAMP) - 创建时间
- `updated_at` (TIMESTAMP) - 更新时间

**关系**:
- `feed_item` - 多对一，关联被举报内容
- `reporter` - 多对一，关联举报人

**索引**:
- `idx_reports_feed_item_id` - feed_item_id 字段
- `idx_reports_user_id` - reporter_id 字段
- `idx_reports_status` - status 字段

---

## 3. Pydantic 模型详情

### 3.1 用户相关模型

- `UserBase` - 用户基础模型
- `UserCreate` - 创建用户请求
- `UserUpdate` - 更新用户请求
- `UserResponse` - 用户响应

### 3.2 认证相关模型

- `LoginRequest` - 登录请求
- `LoginResponse` - 登录响应

### 3.3 资源相关模型

- `AssetBase` - 资源基础模型
- `AssetCreate` - 创建资源请求
- `AssetUpdate` - 更新资源请求
- `AssetResponse` - 资源响应
- `AssetListResponse` - 资源列表响应

### 3.4 社区动态相关模型

- `FeedItemBase` - 社区动态基础模型
- `FeedItemCreate` - 创建社区动态请求
- `FeedItemUpdate` - 更新社区动态请求
- `FeedItemResponse` - 社区动态响应
- `FeedListResponse` - 社区动态列表响应

### 3.5 任务相关模型

- `TaskBase` - 任务基础模型
- `TaskCreate` - 创建任务请求
- `TaskUpdate` - 更新任务请求
- `TaskResponse` - 任务响应
- `TaskStatusResponse` - 任务状态响应
- `TaskListResponse` - 任务列表响应

### 3.6 举报相关模型

- `ReportBase` - 举报基础模型
- `ReportCreate` - 创建举报请求
- `ReportUpdate` - 更新举报请求
- `ReportResponse` - 举报响应
- `ReportListResponse` - 举报列表响应

### 3.7 分页和过滤参数

- `PaginationParams` - 通用分页参数
- `FeedFilterParams` - 社区动态过滤参数
- `AssetFilterParams` - 资源过滤参数
- `TaskFilterParams` - 任务过滤参数

---

## 4. 数据库连接层功能

### 4.1 连接管理

- **异步引擎**: 使用 `create_async_engine` 创建异步数据库引擎
- **连接池配置**:
  - `pool_size=10` - 连接池大小
  - `max_overflow=20` - 最大溢出连接数
  - `pool_pre_ping=True` - 连接健康检查
- **会话工厂**: 使用 `async_sessionmaker` 创建异步会话工厂

### 4.2 依赖注入

- **get_db()**: FastAPI 依赖注入函数，提供数据库会话
- **自动提交**: 事务成功时自动提交
- **自动回滚**: 发生异常时自动回滚
- **会话关闭**: 确保会话正确关闭

### 4.3 初始化和清理

- **init_db()**: 初始化数据库，创建所有表（开发环境）
- **close_db()**: 关闭数据库连接

---

## 5. 混入类

### 5.1 Base 基类

所有数据库模型的基类，使用 SQLAlchemy 2.0 的 `DeclarativeBase`

### 5.2 TimestampMixin

提供时间戳字段:
- `created_at` - 创建时间
- `updated_at` - 更新时间（自动更新）

### 5.3 UUIDMixin

提供 UUID 主键:
- `id` - UUID 类型主键，默认使用 `uuid4()`

---

## 6. 模型关系图

```
User (用户)
  ├─→ Asset (资源) [1:N]
  │    └─→ FeedItem (社区动态) [1:1]
  │         └─→ Report (举报) [1:N]
  ├─→ Task (任务) [1:N]
  ├─→ FeedItem (社区动态) [1:N]
  └─→ Report (举报) [1:N] (作为举报人)
```

---

## 7. 技术特性

### 7.1 SQLAlchemy 2.0 特性

- 使用 `Mapped` 类型注解
- 使用 `mapped_column` 定义列
- 使用 `relationship` 定义关系
- 异步支持 (`AsyncSession`)

### 7.2 Pydantic v2 特性

- 使用 `BaseModel` 定义模型
- 使用 `Field` 进行验证
- 使用 `ConfigDict(from_attributes=True)` 支持从 ORM 对象转换
- 使用 `EmailStr` 进行邮箱验证

### 7.3 PostgreSQL 特性

- 使用 `UUID` 作为主键
- 使用 `TIMESTAMP WITH TIME ZONE` 存储时间
- 使用外键约束 (`REFERENCES`)
- 使用级联删除 (`ON DELETE CASCADE`)

---

## 8. 安全措施

### 8.1 API Key 安全

- `encrypted_api_key` 字段存储加密的 API Key
- 任务完成后删除 API Key（安全措施）

### 8.2 数据完整性

- 使用外键约束确保数据完整性
- 使用级联删除避免孤立数据
- 使用唯一约束避免重复数据

### 8.3 输入验证

- Pydantic 模型提供输入验证
- 字段长度限制
- 枚举值验证

---

## 9. 性能优化

### 9.1 索引策略

- 所有外键字段都创建索引
- 常用查询字段创建索引
- 时间字段创建索引（用于排序和范围查询）

### 9.2 连接池

- 使用连接池减少连接创建开销
- 连接健康检查避免使用失效连接
- 合理配置连接池大小

---

## 10. 遇到的问题和解决方案

### 10.1 问题 1: 依赖安装超时

**问题描述**: 在 macOS 上安装 Python 依赖时遇到超时问题

**解决方案**:
- 使用虚拟环境 (`python3 -m venv venv`)
- 优先安装核心依赖验证模型

### 10.2 问题 2: 外键关系定义

**问题描述**: Report 模型需要关联 User 作为举报人，需要明确指定外键

**解决方案**:
- 使用 `foreign_keys="Report.reporter_id"` 参数明确指定外键
- 在关系定义中使用 `back_populates` 保持双向关系

---

## 11. 下一步工作

1. ✅ 实现加密服务（API Key 安全核心）
2. ⏳ 实现 Google API 客户端
3. ⏳ 实现任务服务（生图服务核心）
4. ⏳ 实现认证模块（用户、登录、JWT）
5. ⏳ 实现资源模块（上传、列表）
6. ⏳ 实现社区模块（Feed、发布、举报）
7. ⏳ 实现 API 路由层（整合所有模块）

---

## 12. 验证

### 12.1 语法验证

所有文件已通过 Python 语法检查：

```bash
python3 -m py_compile app/database/connection.py
python3 -m py_compile app/database/base.py
python3 -m py_compile app/models/user.py
python3 -m py_compile app/models/asset.py
python3 -m py_compile app/models/feed.py
python3 -m py_compile app/models/task.py
python3 -m py_compile app/models/report.py
python3 -m py_compile app/models/schemas.py
```

### 12.2 模型结构验证

测试文件 `tests/test_models.py` 提供了模型结构验证功能，需要在安装依赖后运行：

```bash
source venv/bin/activate
python tests/test_models.py
```

---

## 13. 参考资料

- [SQLAlchemy 2.0 文档](https://docs.sqlalchemy.org/en/20/)
- [Pydantic v2 文档](https://docs.pydantic.dev/latest/)
- [FastAPI 文档](https://fastapi.tiangolo.com/)
- [asyncpg 文档](https://magicstack.github.io/asyncpg/)

---

## 14. 审批

| 角色 | 姓名 | 审批状态 | 日期 |
|------|------|----------|------|
| 开发人员 | - | 已完成 | 2025-12-27 |
| 代码审查 | - | 待审查 | - |
| 技术负责人 | - | 待审批 | - |