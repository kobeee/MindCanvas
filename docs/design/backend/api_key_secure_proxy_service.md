# MindCanvas 后端服务设计（API Key 安全与生图代理模块）

**文档版本**: v1.1
**创建日期**: 2025-12-27
**状态**: 待实施

---

## 文档说明

本文档是 MindCanvas 后端服务设计的补充文档，重点解决**生图服务模块的 API Key 安全问题**。

**与 `backend_architecture.md` 的关系**：
- `backend_architecture.md`：描述完整的后端系统架构，包括认证、资源、社区等所有模块
- 本文档：重点设计生图服务模块的 API Key 安全方案，其他模块的设计参考 `backend_architecture.md`

**本文档范围**：
- ✅ 生图服务模块的 API Key 安全设计
- ✅ 生图服务的异步任务架构
- ✅ 完整后端服务的目录结构和部署方案
- ❌ 认证、资源、社区等模块的详细设计（参考 `backend_architecture.md`）

---

## 1. 概述

### 1.1 背景

MindCanvas iOS APP 在中国大陆使用，无法直接访问 Google API。用户在国内部署后端服务器，作为完整的 APP 后端服务，提供用户认证、资源管理、社区功能等完整业务能力。

**核心问题**：生图服务模块需要使用用户的 API Key 调用 Google Nano Banana Pro API。API Key 需要从 iOS APP 传递到后端，必须确保在传输、存储、使用全过程中的安全性，防止泄露。

### 1.2 核心目标

1. **完整后端服务**：提供 iOS APP 所需的完整后端能力（认证、资源、社区等）
2. **安全传输**：API Key 从 iOS APP 到后端的传输过程加密
3. **安全存储**：API Key 在后端服务器加密存储
4. **安全使用**：API Key 在内存中临时使用，用完即销毁
5. **异步任务**：生图服务支持异步任务模式
6. **一键部署**：使用 Docker Compose，一键部署所有服务

### 1.3 设计原则

- **安全第一**：API Key 全程加密，最小化暴露时间
- **最小权限**：API Key 只在必要时使用，用完即销毁
- **完整服务**：提供完整的后端能力，不只是生图代理
- **聚焦核心**：重点解决 API Key 安全问题，其他模块参考现有架构文档

---

## 2. 系统架构

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS APP (中国大陆)                        │
├─────────────────────────────────────────────────────────────┤
│  APIConfigView → APIKeyManager → EncryptionService          │
│  (加密 API Key) → HTTPS 传输到后端                          │
└─────────────────────────────────────────────────────────────┘
                            ↓ HTTPS (加密传输)
┌─────────────────────────────────────────────────────────────┐
│              后端服务器 (中国大陆，可访问 Google)             │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐   │
│  │  API Layer (FastAPI Routers)                       │   │
│  │  - POST /api/v1/tasks (提交任务)                    │   │
│  │  - GET  /api/v1/tasks/{task_id}/status (轮询状态)  │   │
│  └─────────────────────────────────────────────────────┘   │
│                            ↓                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Service Layer (业务逻辑)                           │   │
│  │  - TaskService (任务管理)                           │   │
│  │  - EncryptionService (加密/解密)                    │   │
│  └─────────────────────────────────────────────────────┘   │
│                            ↓                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Storage Layer (存储层)                             │   │
│  │  - PostgreSQL (任务记录)                            │   │
│  │  - Local Storage (生成的图片)                       │   │
│  └─────────────────────────────────────────────────────┘   │
│                            ↓                                │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  External Adapter (外部服务)                        │   │
│  │  - Google API Client (调用 Nano Banana Pro)        │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                            ↓ HTTPS
┌─────────────────────────────────────────────────────────────┐
│              Google API (Nano Banana Pro)                    │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 技术栈

- **Web 框架**: FastAPI (Python 3.11+)
- **应用服务器**: Uvicorn
- **数据库**: PostgreSQL 15+ (主数据存储)
- **缓存/队列**: Redis (Token 缓存、生成任务队列)
- **对象存储**: 本地存储 / 云存储 (AWS S3 / Aliyun OSS)
- **加密**: cryptography (Fernet 对称加密)
- **HTTP 客户端**: httpx (异步 HTTP 请求)
- **部署**: Docker Compose

### 2.3 目录结构

```
src/backend/
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI 应用入口
│   ├── config.py               # 配置管理
│   ├── models/
│   │   ├── __init__.py
│   │   ├── user.py             # 用户模型
│   │   ├── asset.py            # 资源模型
│   │   ├── task.py             # 任务模型（生图服务）
│   │   ├── feed.py             # 社区动态模型
│   │   └── schemas.py          # Pydantic 模型
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── auth.py             # 认证路由
│   │   ├── assets.py           # 资源路由
│   │   ├── tasks.py            # 任务路由（生图服务）
│   │   └── feed.py             # 社区路由
│   ├── services/
│   │   ├── __init__.py
│   │   ├── auth_service.py     # 认证服务
│   │   ├── encryption.py       # 加密服务（生图服务核心）
│   │   ├── google_api.py       # Google API 客户端（生图服务核心）
│   │   └── task_service.py     # 任务服务（生图服务核心）
│   ├── database/
│   │   ├── __init__.py
│   │   ├── connection.py       # 数据库连接
│   │   └── base.py             # Base 模型
│   ├── utils/
│   │   ├── __init__.py
│   │   └── logger.py           # 日志工具
│   └── storage/
│       ├── __init__.py
│       └── image_storage.py    # 图片存储
├── migrations/                 # 数据库迁移脚本
├── tests/                      # 测试代码
├── docker-compose.yml          # Docker Compose 配置
├── Dockerfile                  # 后端 Docker 镜像
├── requirements.txt            # Python 依赖
└── .env.example                # 环境变量示例
```

**说明**：
- 认证、资源、社区等模块的设计参考 `backend_architecture.md`
- 本文档重点设计**生图服务模块**的 API Key 安全方案

---

## 3. API Key 安全设计

### 3.1 安全威胁分析

| 威胁 | 风险 | 防护措施 |
|------|------|----------|
| 网络抓包 | 高 | HTTPS 强制 + 传输加密 |
| 服务器被入侵 | 中 | API Key 加密存储 + 临时内存 |
| 日志泄露 | 中 | 日志脱敏 + 不记录 API Key |
| 内存泄露 | 低 | 用完即销毁 + 最小化停留时间 |

### 3.2 API Key 生命周期

```
1. iOS APP 加密 API Key (AES-256-GCM)
   ↓
2. HTTPS 传输到后端
   ↓
3. 后端解密 API Key (Fernet)
   ↓
4. 加密存储 API Key (Fernet)
   ↓
5. 任务处理时解密到内存
   ↓
6. 调用 Google API
   ↓
7. 立即清除内存中的 API Key
   ↓
8. 任务完成后删除数据库中的 API Key
```

### 3.3 加密方案

#### 传输加密（iOS APP → 后端）

**iOS APP 端**：
- 使用 AES-256-GCM 加密 API Key
- 使用设备绑定密钥派生（HKDF-SHA256）
- 通过 HTTPS 传输加密后的 API Key

**后端端**：
- 接收加密后的 API Key
- 验证格式和完整性
- 解密后立即加密存储

#### 存储加密（后端）

**加密算法**：Fernet (AES-128-CBC + HMAC-SHA256)

**密钥管理**：
- 加密密钥存储在环境变量中
- 每个任务使用不同的加密密钥（基于 task_id）

**存储格式**：
```
加密数据 = Base64(IV + Ciphertext + Tag)
```

---

## 4. 数据库设计

**说明**：本节重点描述**生图服务模块**相关的数据库表，其他表（users、assets、feed_items）的设计参考 `backend_architecture.md`。

### 4.1 任务表 (generation_tasks)

**说明**：存储生图任务信息，用于异步任务管理。

| 字段名 | 类型 | 说明 |
| :--- | :--- | :--- |
| `id` | UUID | 任务 ID（主键） |
| `user_id` | UUID | 用户 ID（外键 -> users.id） |
| `status` | VARCHAR | 任务状态：pending/processing/completed/failed |
| `prompt` | TEXT | 提示词 |
| `base_image` | TEXT | 参考图（Base64 或 URL）|
| `encrypted_api_key` | TEXT | 加密的 API Key（任务完成后删除）|
| `image_url` | VARCHAR | 生成的图片 URL |
| `error_message` | TEXT | 错误信息 |
| `created_at` | TIMESTAMP | 创建时间 |
| `updated_at` | TIMESTAMP | 更新时间 |

**索引**：
- `idx_user_id`：user_id 字段索引（用于查询用户任务）
- `idx_status`：status 字段索引（用于查询待处理任务）
- `idx_created_at`：created_at 字段索引（用于清理过期任务）

### 4.2 数据清理策略

- **任务保留**：完成任务保留 24 小时
- **API Key 清理**：任务完成后立即删除 `encrypted_api_key` 字段
- **图片清理**：任务完成后保留 7 天，然后删除

---

## 5. API 接口设计

**说明**：本节重点描述**生图服务模块**的 API 接口，其他模块（认证、资源、社区）的接口设计参考 `backend_architecture.md`。

### 5.1 认证模块（简要）

- `POST /api/v1/auth/login`：用户登录，返回 JWT Token
- `GET /api/v1/auth/me`：获取当前用户信息

### 5.2 资源模块（简要）

- `POST /api/v1/assets/upload`：上传图片
- `GET /api/v1/assets/my`：获取我的资源列表

### 5.3 生图服务模块（核心）

#### 5.3.1 提交生图任务

**接口**：`POST /api/v1/generate/tasks`

**请求头**：
```
Content-Type: application/json
Authorization: Bearer <token>
```

**请求体**：
```json
{
  "encrypted_api_key": "base64_encrypted_api_key",
  "prompt": "A beautiful sunset",
  "base_image": "base64_string_or_url"
}
```

**响应**：
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "pending"
}
```

**处理流程**：
1. 验证 JWT Token
2. 验证请求参数
3. 解密 API Key
4. 创建任务记录（加密存储 API Key）
5. 将任务加入后台处理队列
6. 返回任务 ID

#### 5.3.2 轮询任务状态

**接口**：`GET /api/v1/generate/tasks/{task_id}/status`

**请求头**：
```
Authorization: Bearer <token>
```

**响应（待处理/处理中）**：
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "processing",
  "progress": 50
}
```

**响应（已完成）**：
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "completed",
  "image_url": "https://backend.example.com/images/550e8400-e29b-41d4-a716-446655440000.png"
}
```

**响应（失败）**：
```json
{
  "task_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "failed",
  "error_message": "Google API error: Invalid API key"
}
```

#### 5.3.3 下载生成的图片

**接口**：`GET /api/v1/images/{image_id}`

**响应**：图片二进制流

### 5.4 社区模块（简要）

- `GET /api/v1/feed`：获取社区动态
- `POST /api/v1/assets/{asset_id}/publish`：发布资源到社区

---

## 6. 核心服务实现

### 6.1 EncryptionService（加密服务）

**文件**：`src/backend/app/services/encryption.py`

```python
from cryptography.fernet import Fernet
import os

class EncryptionService:
    def __init__(self, secret_key: str):
        """
        初始化加密服务
        :param secret_key: 从环境变量获取的密钥
        """
        if not secret_key:
            raise ValueError("ENCRYPTION_SECRET_KEY environment variable is required")

        self.fernet = Fernet(secret_key.encode())

    def encrypt(self, plaintext: str) -> str:
        """
        加密明文
        :param plaintext: 明文字符串
        :return: Base64 编码的密文
        """
        encrypted = self.fernet.encrypt(plaintext.encode())
        return encrypted.decode()

    def decrypt(self, ciphertext: str) -> str:
        """
        解密密文
        :param ciphertext: Base64 编码的密文
        :return: 明文字符串
        """
        decrypted = self.fernet.decrypt(ciphertext.encode())
        return decrypted.decode()
```

### 6.2 TaskService（任务服务）

**文件**：`src/backend/app/services/task_service.py`

```python
import asyncio
from datetime import datetime
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.task import Task
from app.services.encryption import EncryptionService
from app.services.google_api import GoogleAPIClient

class TaskService:
    def __init__(
        self,
        db: AsyncSession,
        encryption_service: EncryptionService,
        google_client: GoogleAPIClient
    ):
        self.db = db
        self.encryption_service = encryption_service
        self.google_client = google_client

    async def create_task(
        self,
        encrypted_api_key: str,
        prompt: str,
        base_image: Optional[str] = None
    ) -> str:
        """
        创建生成任务
        :param encrypted_api_key: 加密的 API Key
        :param prompt: 提示词
        :param base_image: 参考图（可选）
        :return: 任务 ID
        """
        # 创建任务记录
        task = Task(
            encrypted_api_key=encrypted_api_key,
            prompt=prompt,
            base_image=base_image,
            status="pending"
        )

        self.db.add(task)
        await self.db.commit()
        await self.db.refresh(task)

        # 异步处理任务
        asyncio.create_task(self._process_task(task.id))

        return str(task.id)

    async def get_task_status(self, task_id: str) -> dict:
        """
        获取任务状态
        :param task_id: 任务 ID
        :return: 任务状态信息
        """
        from sqlalchemy import select

        result = await self.db.execute(
            select(Task).where(Task.id == task_id)
        )
        task = result.scalar_one_or_none()

        if not task:
            raise ValueError("Task not found")

        response = {
            "task_id": task.id,
            "status": task.status
        }

        if task.status == "completed":
            response["image_url"] = task.image_url
        elif task.status == "failed":
            response["error_message"] = task.error_message

        return response

    async def _process_task(self, task_id: str):
        """
        处理任务（后台异步执行）
        :param task_id: 任务 ID
        """
        try:
            # 更新状态为处理中
            await self._update_task_status(task_id, "processing")

            # 获取任务
            from sqlalchemy import select
            result = await self.db.execute(
                select(Task).where(Task.id == task_id)
            )
            task = result.scalar_one()

            # 解密 API Key
            api_key = self.encryption_service.decrypt(task.encrypted_api_key)

            # 调用 Google API 生成图片
            image_data = await self.google_client.generate_image(
                api_key=api_key,
                prompt=task.prompt,
                base_image=task.base_image
            )

            # 保存图片到本地存储
            image_url = await self._save_image(task_id, image_data)

            # 更新任务状态为完成
            await self._update_task_status(task_id, "completed", image_url=image_url)

            # 清除 API Key（安全措施）
            await self._clear_api_key(task_id)

        except Exception as e:
            # 更新任务状态为失败
            await self._update_task_status(
                task_id,
                "failed",
                error_message=str(e)
            )
            # 清除 API Key
            await self._clear_api_key(task_id)

    async def _update_task_status(
        self,
        task_id: str,
        status: str,
        image_url: Optional[str] = None,
        error_message: Optional[str] = None
    ):
        """
        更新任务状态
        """
        from sqlalchemy import select, update

        update_data = {"status": status, "updated_at": datetime.utcnow()}

        if image_url:
            update_data["image_url"] = image_url

        if error_message:
            update_data["error_message"] = error_message

        await self.db.execute(
            update(Task).where(Task.id == task_id).values(**update_data)
        )
        await self.db.commit()

    async def _clear_api_key(self, task_id: str):
        """
        清除 API Key（安全措施）
        """
        from sqlalchemy import update

        await self.db.execute(
            update(Task)
            .where(Task.id == task_id)
            .values(encrypted_api_key=None)
        )
        await self.db.commit()

    async def _save_image(self, task_id: str, image_data: bytes) -> str:
        """
        保存图片到本地存储
        """
        from app.storage.image_storage import ImageStorage

        storage = ImageStorage()
        return await storage.save_image(task_id, image_data)
```

### 6.3 GoogleAPIClient（Google API 客户端）

**文件**：`src/backend/app/services/google_api.py`

```python
import httpx
from typing import Optional

class GoogleAPIClient:
    def __init__(self):
        self.base_url = "https://generativelanguage.googleapis.com/v1beta"

    async def generate_image(
        self,
        api_key: str,
        prompt: str,
        base_image: Optional[str] = None
    ) -> bytes:
        """
        调用 Google Nano Banana Pro API 生成图片
        :param api_key: API Key
        :param prompt: 提示词
        :param base_image: 参考图（可选）
        :return: 图片二进制数据
        """
        url = f"{self.base_url}/models/gemini-2.0-flash-exp:generateContent?key={api_key}"

        # 构建请求体
        payload = {
            "contents": [{
                "parts": [{"text": prompt}]
            }]
        }

        if base_image:
            # 如果有参考图，添加到请求体
            payload["contents"][0]["parts"].append({
                "inline_data": {
                    "mime_type": "image/png",
                    "data": base_image
                }
            })

        # 发送请求
        async with httpx.AsyncClient(timeout=60.0) as client:
            response = await client.post(
                url,
                json=payload,
                headers={"Content-Type": "application/json"}
            )

            response.raise_for_status()
            data = response.json()

            # 提取图片数据
            # 注意：这里需要根据实际 API 响应格式调整
            image_base64 = data["candidates"][0]["content"]["parts"][0]["inline_data"]["data"]
            import base64
            return base64.b64decode(image_base64)
```

---

## 7. Docker Compose 部署

### 7.1 docker-compose.yml

**文件**：`src/backend/docker-compose.yml`

```yaml
version: '3.8'

services:
  backend:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: mindcanvas_backend
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://mindcanvas:your_secure_password@db:5432/mindcanvas
      - ENCRYPTION_SECRET_KEY=${ENCRYPTION_SECRET_KEY}
      - LOG_LEVEL=INFO
    volumes:
      - ./app:/app/app
      - ./storage:/app/storage
    depends_on:
      - db
      - redis
    restart: unless-stopped
    networks:
      - mindcanvas_network

  db:
    image: postgres:15-alpine
    container_name: mindcanvas_db
    environment:
      - POSTGRES_USER=mindcanvas
      - POSTGRES_PASSWORD=your_secure_password
      - POSTGRES_DB=mindcanvas
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./migrations:/docker-entrypoint-initdb.d
    restart: unless-stopped
    networks:
      - mindcanvas_network

  redis:
    image: redis:7-alpine
    container_name: mindcanvas_redis
    restart: unless-stopped
    networks:
      - mindcanvas_network

volumes:
  postgres_data:

networks:
  mindcanvas_network:
    driver: bridge
```

### 7.2 Dockerfile

**文件**：`src/backend/Dockerfile`

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# 复制依赖文件
COPY requirements.txt .

# 安装 Python 依赖
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用代码
COPY app ./app

# 创建存储目录
RUN mkdir -p /app/storage/images

# 暴露端口
EXPOSE 8000

# 启动命令
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### 7.3 requirements.txt

**文件**：`src/backend/requirements.txt`

```txt
fastapi==0.104.1
uvicorn[standard]==0.24.0
sqlalchemy[asyncio]==2.0.23
asyncpg==0.29.0
httpx==0.25.2
cryptography==41.0.7
python-dotenv==1.0.0
pydantic==2.5.0
pydantic-settings==2.1.0
```

### 7.4 .env.example

**文件**：`src/backend/.env.example`

```env
# 数据库配置
DATABASE_URL=postgresql://mindcanvas:your_secure_password@db:5432/mindcanvas

# 加密密钥（必须设置，使用：python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"）
ENCRYPTION_SECRET_KEY=your_generated_secret_key_here

# 日志级别
LOG_LEVEL=INFO

# 图片存储路径
IMAGE_STORAGE_PATH=/app/storage/images

# 任务清理间隔（秒）
TASK_CLEANUP_INTERVAL=3600
```

### 7.5 一键部署

**步骤**：

1. **生成加密密钥**：
```bash
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

2. **配置环境变量**：
```bash
cp .env.example .env
# 编辑 .env 文件，设置 ENCRYPTION_SECRET_KEY
```

3. **启动服务**：
```bash
docker-compose up -d
```

4. **查看日志**：
```bash
docker-compose logs -f backend
```

5. **停止服务**：
```bash
docker-compose down
```

---

## 8. 安全措施

### 8.1 API Key 安全

1. **传输安全**：
   - 强制 HTTPS（生产环境）
   - API Key 在 iOS APP 端加密后传输

2. **存储安全**：
   - API Key 使用 Fernet 加密存储
   - 任务完成后立即删除 API Key

3. **内存安全**：
   - API Key 只在任务处理时解密到内存
   - 使用后立即清除

4. **日志安全**：
   - 日志中不记录 API Key
   - 错误信息脱敏

### 8.2 网络安全

1. **HTTPS 强制**：
   - 生产环境配置 SSL 证书
   - 禁用 HTTP 访问

2. **防火墙规则**：
   - 只开放必要端口（8000）
   - 限制访问 IP（可选）

### 8.3 访问控制

1. **速率限制**：
   - 限制每个用户的任务提交频率
   - 防止 API 被滥用

2. **输入验证**：
   - 验证 API Key 格式
   - 验证提示词长度

---

## 9. 错误处理

### 9.1 错误类型

| 错误类型 | HTTP 状态码 | 说明 |
|---------|-----------|------|
| InvalidRequest | 400 | 请求参数无效 |
| TaskNotFound | 404 | 任务不存在 |
| InternalError | 500 | 服务器内部错误 |
| APIError | 502 | Google API 错误 |

### 9.2 错误响应格式

```json
{
  "error": {
    "code": "TASK_NOT_FOUND",
    "message": "Task not found",
    "details": {}
  }
}
```

---

## 10. 监控和日志

### 10.1 日志记录

- **访问日志**：记录所有 API 请求
- **错误日志**：记录所有错误和异常
- **任务日志**：记录任务处理过程

### 10.2 监控指标

- 任务数量（按状态分类）
- 任务处理时间
- API 调用成功率
- 错误率

---

## 11. 测试

### 11.1 单元测试

- 加密/解密功能测试
- 任务创建和状态更新测试
- Google API 客户端测试（Mock）

### 11.2 集成测试

- 端到端任务流程测试
- API Key 安全性测试
- 错误处理测试

---

## 12. 后续优化

### 12.1 生图服务优化

- 使用消息队列（Redis/Celery）处理任务
- 添加任务优先级
- 实现任务批处理
- 支持多个 AI 服务提供商
- 支持任务取消和重试

### 12.2 其他模块优化

参考 `backend_architecture.md` 中的扩展性设计：
- 认证模块：支持多种登录方式
- 资源模块：支持 CDN 加速
- 社区模块：实现点赞、评论等功能

### 12.3 安全增强

- 实现 API Key 轮换
- 添加审计日志
- 实现访问控制列表（ACL）
- 内容安全审核（UGC）

---

## 13. 附录

### 13.1 术语表

| 术语 | 说明 |
|------|------|
| Fernet | Python cryptography 库提供的对称加密实现 |
| AES-128-CBC | 高级加密标准，128 位密钥，密码分组链接模式 |
| HMAC-SHA256 | 基于哈希的消息认证码 |
| Docker Compose | Docker 容器编排工具 |

### 13.2 参考资料

- [FastAPI 官方文档](https://fastapi.tiangolo.com/)
- [cryptography 文档](https://cryptography.io/)
- [Google Gemini API 文档](https://ai.google.dev/docs)

---

## 14. 审批

| 角色 | 姓名 | 审批状态 | 日期 |
|------|------|----------|------|
| 架构师 | - | 待审批 | - |
| 安全主管 | - | 待审批 | - |
| 技术负责人 | - | 待审批 | - |