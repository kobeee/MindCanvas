# MindCanvas 后端系统详细设计文档

## 1. 概述 (Overview)

本文档基于 MindCanvas v1.0 PRD，阐述后端系统的 API 接口设计、数据库模型及核心业务逻辑。后端将采用 **Python (FastAPI)** 构建，强调高性能异步处理和对 AI 模型的便捷调用。

### 1.1 技术栈选择
*   **Web 框架**: FastAPI (Python 3.11+)
*   **应用服务器**: Uvicorn / Gunicorn
*   **数据库**: PostgreSQL 15+ (主数据存储)
*   **缓存/队列**: Redis (Token 缓存、生成任务队列、点赞计数)
*   **对象存储**: AWS S3 / Aliyun OSS (存储用户上传及生成的图片)
*   **AI 集成**: Google Gemini API (Nano Banana Pro)
*   **部署**: Docker Compose

---

## 2. 系统架构 (Architecture)

### 2.1 逻辑分层
*   **API Layer (Routers)**: 处理 HTTP 请求，参数校验 (Pydantic)。
*   **Service Layer**: 业务逻辑核心（如：处理生成请求、组合 Prompt、社区逻辑）。
*   **Repository Layer (DAL)**: 封装 SQLAlchemy/Tortoise-ORM 操作。
*   **Adapter Layer**: 外部服务适配器（S3 Client, Gemini Client）。

### 2.2 数据流向
1.  Client 发起生成请求 -> API Layer 校验 JWT。
2.  Service Layer 将请求参数放入 Redis 队列 (可选，若并发量大) 或直接异步调用。
3.  Gemini Adapter 调用 LLM API。
4.  获取结果图片 -> Upload to S3 -> 获取公网 URL。
5.  写入 Database (Assets 表) -> 返回给前端。

---

## 3. 数据库设计 (Database Schema)

### 3.1 ER 图描述

#### `users` (用户表)
| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | UUID | 主键 |
| `email` | VARCHAR | 邮箱 (唯一) |
| `username` | VARCHAR | 用户名 |
| `auth_provider` | VARCHAR | 'apple', 'google', 'github', 'email' |
| `provider_id` | VARCHAR | 第三方唯一 ID |
| `avatar_url` | VARCHAR | 头像 |
| `created_at` | TIMESTAMP | 注册时间 |

#### `projects` (画布工程表 - 可选，v1.0 若暂不支持云端同步画布状态可仅存本地)
| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | UUID | 主键 |
| `user_id` | UUID | 外键 -> users.id |
| `name` | VARCHAR | 工程名 |
| `snapshot_json` | JSONB | tldraw 画布数据快照 |
| `updated_at` | TIMESTAMP | 最后修改时间 |

#### `assets` (资源/图片表)
| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | UUID | 主键 |
| `user_id` | UUID | 外键 -> users.id |
| `url` | VARCHAR | S3 图片地址 |
| `type` | VARCHAR | 'upload' (原图), 'generated' (AI图) |
| `prompt` | TEXT | 生成时的提示词 (仅 generated 有效) |
| `model_version` | VARCHAR | 'nano-banana-pro-v1' |
| `is_public` | BOOLEAN | 是否已发布到社区 (默认为 False) |
| `created_at` | TIMESTAMP | 创建时间 |

#### `feed_items` (社区动态表)
| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | UUID | 主键 |
| `asset_id` | UUID | 外键 -> assets.id (关联的具体图片) |
| `user_id` | UUID | 作者 ID |
| `title` | VARCHAR | 发布时的标题 |
| `likes_count` | INT | 点赞数 (Redis 同步) |
| `published_at` | TIMESTAMP | 发布时间 |

---

## 4. API 接口设计 (API Endpoints)

### 4.1 认证模块 (Auth)
*   `POST /api/v1/auth/login`
    *   **Body**: `{ provider: "apple", token: "identity_token_string" }`
    *   **Logic**: 验证第三方 Token 有效性 -> 查找/创建 User -> 签发 JWT (Access Token)。
    *   **Response**: `{ access_token: "...", token_type: "bearer" }`

### 4.2 资源与上传 (Assets)
*   `POST /api/v1/assets/upload`
    *   **Form-Data**: `file: binary`
    *   **Logic**: 校验文件类型/大小 -> 上传 S3 -> 记录 `assets` 表 (type='upload')。
    *   **Response**: `{ id: "...", url: "https://..." }`

*   `GET /api/v1/assets/my`
    *   **Query**: `page=1, size=20`
    *   **Response**: 用户个人的图片列表（上传+生成）。

### 4.3 AI 生成 (Generation)
*   `POST /api/v1/generate`
    *   **Headers**: `Authorization: Bearer <token>`
    *   **Body**:
        ```json
        {
          "prompt": "A futuristic city...",
          "base_image": "base64_string_or_url", // 画布参考图
          "strength": 0.75 // 意图强度
        }
        ```
    *   **Logic**:
        1.  检查用户配额/权限。
        2.  调用 Gemini API (Nano Banana Pro)。
        3.  接收图片流 -> 上传 S3。
        4.  写入 `assets` 表 (type='generated')。
    *   **Response**: `{ id: "...", url: "...", prompt: "..." }`

### 4.4 社区 (MindStream)
*   `GET /api/v1/feed`
    *   **Query**: `page=1, size=20, sort=latest|hot`
    *   **Response**: 包含 FeedItem 信息，以及关联 Asset 的 Prompt（用于 Remix）。

*   `POST /api/v1/assets/{asset_id}/publish`
    *   **Body**: `{ title: "My Masterpiece" }`
    *   **Logic**: 检查 asset 归属 -> 更新 `is_public=true` -> 插入 `feed_items`。
    *   **Audit**: 触发内容安全审核（文本+图片），若违规直接拒绝或标记为待审。

*   `POST /api/v1/feed/{feed_id}/report`
    *   **Body**: `{ reason: "nsfw" }`
    *   **Logic**: 记录举报信息，若超过阈值自动隐藏，通知管理员。

---

## 5. 核心业务流程详解

### 5.1 生成服务 (Generation Service)
由于 Gemini 生成图片可能耗时（5s-15s），建议设计为：
*   **方案 A (简单)**: 同步等待。FastAPI 支持 `async def`，不会阻塞主线程，但客户端需要维持长连接，设置较长的 Timeout。
*   **方案 B (健壮)**: 异步任务 + 轮询/SSE。
    1.  POST `/generate` 返回 `task_id`。
    2.  客户端轮询 `/generate/status/{task_id}` 或建立 SSE 连接。
    3.  Worker 处理完成后更新状态。
*   *v1.0 决策*: 为降低开发复杂度，采用 **方案 A (异步非阻塞等待)**。FastAPI 性能足够支撑初期并发。

### 5.2 内容安全审核 (UGC Safety)
App Store 对 UGC 应用审核极其严格。
1.  **文本拦截**: 发布时，检查 Title 和 Prompt 是否包含敏感词。
2.  **图片审核**: 使用 AWS Rekognition 或开源模型（如 NudeNet，部署在单独容器）在发布前扫描图片。
3.  **开关**: 后端需做一个全局配置 `ENABLE_STRICT_AUDIT`，审核期间开启最严模式。

---

## 6. 安全与扩展性 (Security & Scalability)

*   **API Rate Limiting**: 使用 `fastapi-limiter` (基于 Redis)，限制 `/generate` 接口每分钟调用次数（如 5次/分），防止 API Key 被刷爆。
*   **Key Management**: Google API Key 存储在服务器环境变量中，绝不下发给客户端。
*   **CDN**: 图片 URL 均走 CDN 域名，减少 S3 流量费用并加速加载。

