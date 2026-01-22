# Laozhang API 集成设计方案

> **注意**：本方案为从0到1的设计，后端服务尚未部署上线，不涉及数据迁移。数据库表直接创建，无需迁移脚本。

## 1. 概述

### 1.1 目标

在现有 Google API 生图功能的基础上，集成 Laozhang API 作为备选方案，实现：

1. **多提供商支持**：支持 Google API 和 Laozhang API 两种生图方式
2. **用户隔离**：部分邮箱指定使用 Laozhang API，默认使用 Google API
3. **配额管理**：指定邮箱的用户享受 10 次免费额度
4. **订阅基础**：为未来订阅功能预留扩展空间
5. **默认配置**：Laozhang API 默认使用 2K 分辨率

### 1.2 设计原则

- **单一方案**：只提供最优方案，不提供多个选项
- **向后兼容**：不影响现有 Google API 用户的使用
- **可扩展性**：为未来订阅功能预留扩展空间
- **安全性**：API Key 加密存储，任务完成后清除
- **可维护性**：清晰的代码结构和完整的日志记录

---

## 2. 架构设计

### 2.1 整体架构

```
┌─────────────┐
│  iOS Client │
└──────┬──────┘
       │ POST /api/v1/generate/tasks
       │ { encrypted_api_key, prompt, base_image }
       ↓
┌─────────────────────────────────────┐
│         FastAPI Backend            │
│  ┌───────────────────────────────┐  │
│  │   Tasks Router                │  │
│  │   - create_task()             │  │
│  │   - get_task_status()         │  │
│  └───────────┬───────────────────┘  │
│              ↓                       │
│  ┌───────────────────────────────┐  │
│  │   TaskService                 │  │
│  │   - create_task()             │  │
│  │   - _process_task()           │  │
│  └───────────┬───────────────────┘  │
│              ↓                       │
│  ┌───────────────────────────────┐  │
│  │   ProviderFactory             │  │
│  │   - create_provider()         │  │
│  └───────────┬───────────────────┘  │
│              ↓                       │
│  ┌───────────────────────────────┐  │
│  │   ImageGenerationProvider     │  │
│  │   (Abstract Base Class)       │  │
│  └───────────────────────────────┘  │
│         ↓              ↓            │
│  ┌──────────┐    ┌──────────┐       │
│  │  Google  │    │ Laozhang │       │
│  │  Client  │    │  Client  │       │
│  └──────────┘    └──────────┘       │
│         ↓              ↓            │
│  ┌───────────────────────────────┐  │
│  │   QuotaService                │  │
│  │   - check_quota()             │  │
│  │   - decrement_quota()         │  │
│  │   - get_user_api_provider()   │  │
│  └───────────┬───────────────────┘  │
│              ↓                       │
│  ┌───────────────────────────────┐  │
│  │   Database (PostgreSQL)       │  │
│  │   - users                     │  │
│  │   - user_quotas               │  │
│  │   - generation_tasks          │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### 2.2 核心组件

#### 2.2.1 API 提供商抽象层

**设计目标**：统一不同 API 提供商的接口，便于扩展和管理

**抽象基类**：`ImageGenerationProvider`

```python
class ImageGenerationProvider(ABC):
    """图像生成提供商抽象基类"""

    @abstractmethod
    async def generate_image(
        self,
        api_key: str,
        prompt: str,
        base_image: Optional[str] = None,
        image_size: str = "2K"
    ) -> bytes:
        """
        生成图片

        Args:
            api_key: API Key
            prompt: 提示词
            base_image: 参考图的 Base64 编码（可选）
            image_size: 图片尺寸（1K, 2K, 4K）

        Returns:
            图片二进制数据
        """
        pass
```

**实现类**：
- `GoogleAPIClient`：Google API 客户端（已存在，需适配接口）
- `LaozhangAPIClient`：Laozhang API 客户端（新增）

#### 2.2.2 提供商工厂

**设计目标**：根据配置动态创建 API 提供商实例

```python
class ProviderFactory:
    """API 提供商工厂"""

    @staticmethod
    def create_provider(provider_name: str) -> ImageGenerationProvider:
        """
        创建 API 提供商实例

        Args:
            provider_name: 提供商名称（'google' or 'laozhang'）

        Returns:
            API 提供商实例

        Raises:
            ValueError: 如果提供商名称无效
        """
        providers = {
            "google": GoogleAPIClient,
            "laozhang": LaozhangAPIClient
        }

        provider_class = providers.get(provider_name)
        if not provider_class:
            raise ValueError(f"Unknown provider: {provider_name}")

        return provider_class()
```

#### 2.2.3 配额管理服务

**设计目标**：管理用户配额，支持免费额度和付费额度

```python
class QuotaService:
    """配额管理服务"""

    async def check_quota(self, user_id: UUID) -> QuotaInfo:
        """检查用户配额"""

    async def decrement_quota(self, user_id: UUID) -> bool:
        """扣减用户配额"""

    async def get_user_api_provider(self, user_id: UUID) -> str:
        """获取用户使用的 API 提供商"""
```

#### 2.2.4 任务服务改造

**设计目标**：集成提供商选择和配额管理

**主要改动**：
- 创建任务时自动选择 API 提供商
- 处理任务时使用工厂模式创建提供商实例
- Laozhang API 默认使用 2K 分辨率
- 任务完成后扣减配额

---

## 3. 数据库设计

### 3.1 User 表

```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    username VARCHAR(100),
    
    -- 认证信息
    auth_provider VARCHAR(50) NOT NULL,
    provider_id VARCHAR(255),
    refresh_token VARCHAR(500),
    refresh_token_expires_at TIMESTAMP WITH TIME ZONE,
    
    -- API 提供商配置
    api_provider VARCHAR(50) DEFAULT 'google',
    free_quota INTEGER DEFAULT 0,
    total_quota_used INTEGER DEFAULT 0,
    
    -- 订阅信息（为未来订阅功能预留）
    subscription_tier VARCHAR(50) DEFAULT 'free',
    subscription_expires_at TIMESTAMP WITH TIME ZONE,
    
    -- 头像
    avatar_url VARCHAR(500),
    
    -- 时间戳
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_api_provider ON users(api_provider);
CREATE INDEX idx_users_subscription_tier ON users(subscription_tier);
CREATE INDEX idx_users_provider_id ON users(provider_id);
CREATE INDEX idx_users_refresh_token ON users(refresh_token);
```

**字段说明**：
- `api_provider`：用户使用的 API 提供商（'google' or 'laozhang'）
- `free_quota`：免费额度（从 `email_quota_configs` 表读取）
- `total_quota_used`：总使用次数（用于统计）
- `subscription_tier`：订阅等级（'free', 'pro', 'enterprise'）
- `subscription_expires_at`：订阅过期时间

### 3.2 generation_tasks 表

```sql
CREATE TABLE generation_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    
    -- 任务状态
    status VARCHAR(50) NOT NULL,
    
    -- 生成参数
    prompt TEXT NOT NULL,
    base_image TEXT,
    
    -- API Key（加密存储，任务完成后删除）
    encrypted_api_key TEXT,
    
    -- API 提供商和图片尺寸
    api_provider VARCHAR(50) DEFAULT 'google',
    image_size VARCHAR(10) DEFAULT '1K',
    
    -- 生成结果
    image_url VARCHAR(500),
    image_expires_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    
    -- 时间戳
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_generation_tasks_user_id ON generation_tasks(user_id);
CREATE INDEX idx_generation_tasks_status ON generation_tasks(status);
CREATE INDEX idx_generation_tasks_api_provider ON generation_tasks(api_provider);
CREATE INDEX idx_generation_tasks_created_at ON generation_tasks(created_at);
CREATE INDEX idx_generation_tasks_image_expires_at ON generation_tasks(image_expires_at);
```

**字段说明**：
- `api_provider`：任务使用的 API 提供商
- `image_size`：生成的图片尺寸（1K, 2K, 4K）

### 3.3 email_quota_configs 表

```sql
CREATE TABLE email_quota_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    initial_quota INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by VARCHAR(100) DEFAULT 'admin'
);

CREATE INDEX idx_email_quota_configs_email ON email_quota_configs(email);
```

**字段说明**：
- `email`：用户邮箱（唯一）
- `initial_quota`：初始配额（免费次数）
- `created_at`：创建时间
- `created_by`：创建者标识

**使用规则**：
- 已使用的邮箱再次注入无效
- 超过初始指定次数后无效，只能走 Google API Key 方式

### 3.4 user_quotas 表（可选）

```sql
CREATE TABLE user_quotas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    quota_type VARCHAR(50) NOT NULL,
    quota_amount INTEGER NOT NULL,
    used_amount INTEGER DEFAULT 0,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_user_quotas_user_id ON user_quotas(user_id);
CREATE INDEX idx_user_quotas_quota_type ON user_quotas(quota_type);

-- 唯一约束，防止重复配额
CREATE UNIQUE INDEX idx_user_quotas_unique ON user_quotas(user_id, quota_type);
```

**字段说明**：
- `user_id`：用户 ID
- `quota_type`：配额类型（'free', 'paid'）
- `quota_amount`：配额总量
- `used_amount`：已使用量
- `expires_at`：过期时间

---

## 4. 配置设计

### 4.1 环境变量

```bash
# Laozhang API 配置
LAOZHANG_API_KEY=sk-YOUR_LAOZHANG_API_KEY

# 管理员密钥（用于邮箱配额注入接口认证）
ADMIN_SECRET_KEY=your-admin-secret-key-change-in-production
```

### 4.2 动态邮箱配额注入

**设计目标**：通过 API 接口动态注入邮箱配额，无需修改环境变量

**特性**：
- 已使用的邮箱再次注入无效
- 超过初始指定次数后无效，只能走 Google API Key 方式
- 提供命令行脚本快速注入

**数据库表**：`email_quota_configs`

```sql
CREATE TABLE email_quota_configs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) NOT NULL UNIQUE,
    initial_quota INTEGER NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_by VARCHAR(100) DEFAULT 'admin'
);

CREATE INDEX idx_email_quota_configs_email ON email_quota_configs(email);
```

**字段说明**：
- `email`：用户邮箱（唯一）
- `initial_quota`：初始配额（免费次数）
- `created_at`：创建时间
- `created_by`：创建者标识

---

## 5. 管理员接口

### 5.1 邮箱配额注入接口

**路由**：`POST /api/v1/admin/email-quota`

**认证**：使用 `ADMIN_SECRET_KEY` 进行认证

**请求体**：
```json
{
  "email": "test@example.com",
  "quota": 10
}
```

**响应**：
```json
{
  "success": true,
  "message": "Email quota injected successfully"
}
```

**错误响应**：
```json
{
  "success": false,
  "error": "Email already has quota configured"
}
```

**文件**：`src/backend/app/routers/admin.py`

```python
"""
管理员路由模块

提供邮箱配额注入和管理的 API 接口。
"""

from typing import Annotated
from fastapi import APIRouter, HTTPException, status, Header
from sqlalchemy.ext.asyncio import AsyncSession
import logging

from app.database.connection import get_db
from app.models.schemas import EmailQuotaInjectRequest, SuccessResponse
from app.config import settings
from sqlalchemy import select, text

logger = logging.getLogger(__name__)

# 创建路由器
router = APIRouter(prefix="/api/v1/admin", tags=["Admin"])


async def verify_admin(admin_secret: str = Header(...)) -> None:
    """验证管理员密钥"""
    if admin_secret != settings.ADMIN_SECRET_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid admin secret key"
        )


@router.post("/email-quota", response_model=SuccessResponse, status_code=status.HTTP_201_CREATED)
async def inject_email_quota(
    request: EmailQuotaInjectRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: None = Depends(verify_admin)
):
    """
    注入邮箱配额

    规则：
    1. 已使用的邮箱再次注入无效
    2. 超过初始指定次数后无效，只能走 Google API Key 方式

    Args:
        request: 邮箱配额注入请求
        db: 数据库会话

    Returns:
        成功响应

    Raises:
        HTTPException: 如果注入失败
    """
    try:
        # 检查邮箱是否已经配置过配额
        result = await db.execute(
            text("SELECT * FROM email_quota_configs WHERE email = :email"),
            {"email": request.email}
        )
        existing = result.fetchone()

        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already has quota configured"
            )

        # 检查邮箱是否已经使用过（检查用户表）
        user_result = await db.execute(
            text("SELECT id, total_quota_used FROM users WHERE email = :email"),
            {"email": request.email}
        )
        user = user_result.fetchone()

        if user and user[1] > 0:  # total_quota_used > 0
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email has already been used, cannot inject quota"
            )

        # 注入邮箱配额
        await db.execute(
            text("""
                INSERT INTO email_quota_configs (email, initial_quota)
                VALUES (:email, :quota)
            """),
            {"email": request.email, "quota": request.quota}
        )
        await db.commit()

        logger.info(f"Email quota injected: {request.email}, quota={request.quota}")

        return SuccessResponse(message="Email quota injected successfully")

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to inject email quota: {str(e)}")
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to inject email quota"
        )


@router.get("/email-quota", status_code=status.HTTP_200_OK)
async def list_email_quotas(
    db: Annotated[AsyncSession, Depends(get_db)],
    _: None = Depends(verify_admin)
):
    """
    查询所有邮箱配额

    Returns:
        邮箱配额列表
    """
    try:
        result = await db.execute(
            text("""
                SELECT email, initial_quota, created_at
                FROM email_quota_configs
                ORDER BY created_at DESC
            """)
        )
        quotas = result.fetchall()

        return {
            "total": len(quotas),
            "items": [
                {
                    "email": row[0],
                    "initial_quota": row[1],
                    "created_at": row[2].isoformat() if row[2] else None
                }
                for row in quotas
            ]
        }

    except Exception as e:
        logger.error(f"Failed to list email quotas: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list email quotas"
        )
```

### 5.2 命令行注入脚本

**文件**：`src/backend/scripts/inject_email_quota.py`

```python
#!/usr/bin/env python3
"""
邮箱配额注入脚本

使用方法：
    python inject_email_quota.py <email> <quota>

示例：
    python inject_email_quota.py test@example.com 10
"""

import sys
import asyncio
import httpx


async def inject_email_quota(email: str, quota: int, admin_secret: str):
    """注入邮箱配额"""
    url = "http://localhost:8000/api/v1/admin/email-quota"

    headers = {
        "admin-secret": admin_secret,
        "Content-Type": "application/json"
    }

    payload = {
        "email": email,
        "quota": quota
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, headers=headers, json=payload)

        if response.status_code == 201:
            result = response.json()
            print(f"✅ {result['message']}")
            print(f"   Email: {email}")
            print(f"   Quota: {quota}")
        else:
            error = response.json()
            print(f"❌ Failed: {error.get('detail', 'Unknown error')}")
            sys.exit(1)


def main():
    """主函数"""
    if len(sys.argv) < 3:
        print("Usage: python inject_email_quota.py <email> <quota>")
        print("Example: python inject_email_quota.py test@example.com 10")
        sys.exit(1)

    email = sys.argv[1]
    quota = int(sys.argv[2])

    # 从环境变量读取管理员密钥
    import os
    admin_secret = os.getenv("ADMIN_SECRET_KEY", "")

    if not admin_secret:
        print("Error: ADMIN_SECRET_KEY environment variable not set")
        sys.exit(1)

    asyncio.run(inject_email_quota(email, quota, admin_secret))


if __name__ == "__main__":
    main()
```

**使用方法**：

```bash
# 设置管理员密钥
export ADMIN_SECRET_KEY="your-admin-secret-key"

# 注入邮箱配额
python src/backend/scripts/inject_email_quota.py test@example.com 10
```

### 5.3 用户配额查询接口

**路由**：`GET /api/v1/users/me/quota`

**认证**：JWT Token

**响应**：
```json
{
  "api_provider": "laozhang",
  "has_free_quota": true,
  "max_quota": 10,
  "used_quota": 3,
  "remaining_quota": 7,
  "subscription_tier": "free"
}
```

**文件**：`src/backend/app/routers/users.py`（新增）

```python
"""
用户配额查询路由
"""

from typing import Annotated
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.connection import get_db
from app.models.schemas import UserQuotaResponse
from app.services.quota_service import QuotaService
from app.services.auth_service import AuthService

router = APIRouter(prefix="/api/v1/users", tags=["Users"])


@router.get("/me/quota", response_model=UserQuotaResponse, status_code=200)
async def get_user_quota(
    current_user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)]
):
    """
    获取当前用户的配额信息

    Returns:
        用户配额信息
    """
    quota_service = QuotaService(db)

    # 获取 API 提供商
    provider = await quota_service.get_user_api_provider(str(current_user.id))

    # 检查配额
    quota_info = await quota_service.check_quota(str(current_user.id))

    return UserQuotaResponse(
        api_provider=provider,
        has_free_quota=quota_info.max_quota > 0,
        max_quota=quota_info.max_quota,
        used_quota=quota_info.used_quota,
        remaining_quota=quota_info.remaining_quota,
        subscription_tier=current_user.subscription_tier
    )
```

---

## 6. 核心实现

### 6.1 Laozhang API 客户端

**文件**：`src/backend/app/services/laozhang_api.py`

```python
"""
Laozhang API 客户端模块

提供 Laozhang API 的异步调用功能，支持文本到图片生成和图片到图片生成。
"""

import httpx
import base64
import logging
from typing import Optional

logger = logging.getLogger(__name__)


class LaozhangAPIError(Exception):
    """Laozhang API 异常基类"""
    pass


class LaozhangAPIClient:
    """
    Laozhang API 客户端类

    使用 httpx 异步 HTTP 客户端调用 Laozhang API，
    支持文本到图片生成和图片到图片生成。

    API 文档：https://api.laozhang.ai/v1beta/models/gemini-3-pro-image-preview:generateContent

    特性：
    - 支持 1K, 2K, 4K 分辨率
    - 默认使用 2K 分辨率
    - 支持文生图和图生图
    """

    def __init__(self, timeout: float = 180.0):
        """
        初始化 Laozhang API 客户端

        Args:
            timeout: 请求超时时间（秒），默认 180 秒
        """
        self.base_url = "https://api.laozhang.ai/v1beta"
        self.model_name = "gemini-3-pro-image-preview"
        self.timeout = timeout
        logger.info(f"LaozhangAPIClient initialized with model={self.model_name}, timeout={timeout}s")

    async def generate_image(
        self,
        api_key: str,
        prompt: str,
        base_image: Optional[str] = None,
        image_size: str = "2K"
    ) -> bytes:
        """
        调用 Laozhang API 生成图片

        Args:
            api_key: Laozhang API Key
            prompt: 提示词
            base_image: 参考图的 Base64 编码（可选）
            image_size: 图片尺寸（1K, 2K, 4K），默认 2K

        Returns:
            图片二进制数据（PNG 格式）

        Raises:
            LaozhangAPIError: 如果 API 调用失败
        """
        if not api_key:
            logger.error("API Key is empty")
            raise LaozhangAPIError("API Key is required")

        if not prompt:
            logger.error("Prompt is empty")
            raise LaozhangAPIError("Prompt is required")

        # 构建 API URL
        url = f"{self.base_url}/models/{self.model_name}:generateContent"

        # 构建请求头
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }

        # 构建请求体
        payload = self._build_request_payload(prompt, base_image, image_size)

        logger.info(f"Generating image with prompt length={len(prompt)}, base_image={'yes' if base_image else 'no'}, image_size={image_size}")

        try:
            # 发送异步 HTTP 请求
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(url, headers=headers, json=payload)

                # 检查 HTTP 状态码
                if response.status_code == 401:
                    logger.error("Laozhang API returned 401 Unauthorized")
                    raise LaozhangAPIError("Invalid API Key")

                elif response.status_code == 429:
                    logger.error("Laozhang API returned 429 Rate Limit Exceeded")
                    raise LaozhangAPIError("Rate limit exceeded, please try again later")

                elif response.status_code == 400:
                    logger.error(f"Laozhang API returned 400 Bad Request: {response.text}")
                    raise LaozhangAPIError(f"Invalid request: {response.text}")

                elif response.status_code >= 500:
                    logger.error(f"Laozhang API returned {response.status_code}: {response.text}")
                    raise LaozhangAPIError(f"Laozhang API internal error: {response.status_code}")

                # 检查响应是否成功
                response.raise_for_status()

                # 解析响应
                data = response.json()

                # 提取图片数据
                image_data = self._extract_image_data(data)

                logger.info("Image generated successfully")
                return image_data

        except httpx.TimeoutException:
            logger.error(f"Request timed out after {self.timeout}s")
            raise LaozhangAPIError(f"Request timed out after {self.timeout}s")

        except httpx.HTTPStatusError as e:
            logger.error(f"HTTP error occurred: {e}")
            raise LaozhangAPIError(f"HTTP error: {str(e)}")

        except httpx.RequestError as e:
            logger.error(f"Request error occurred: {e}")
            raise LaozhangAPIError(f"Request error: {str(e)}")

        except LaozhangAPIError:
            raise

        except Exception as e:
            logger.error(f"Unexpected error occurred: {e}")
            raise LaozhangAPIError(f"Unexpected error: {str(e)}")

    def _build_request_payload(
        self,
        prompt: str,
        base_image: Optional[str],
        image_size: str
    ) -> dict:
        """
        构建请求体

        Args:
            prompt: 提示词
            base_image: 参考图的 Base64 编码
            image_size: 图片尺寸

        Returns:
            请求体字典
        """
        payload = {
            "contents": [{
                "parts": [{"text": prompt}]
            }],
            "generationConfig": {
                "responseModalities": ["IMAGE"],
                "imageConfig": {
                    "aspectRatio": "1:1",
                    "imageSize": image_size
                }
            }
        }

        # 如果有参考图，添加到请求体
        if base_image:
            try:
                # 验证 base_image 是否为有效的 Base64 字符串
                base64.b64decode(base_image, validate=True)
                payload["contents"][0]["parts"].append({
                    "inline_data": {
                        "mime_type": "image/jpeg",
                        "data": base_image
                    }
                })
                logger.debug("Base image added to request payload")
            except Exception as e:
                logger.error(f"Invalid base64 image data: {e}")
                raise LaozhangAPIError("Invalid base64 image data")

        return payload

    def _extract_image_data(self, response_data: dict) -> bytes:
        """
        从 API 响应中提取图片数据

        Args:
            response_data: API 响应数据

        Returns:
            图片二进制数据

        Raises:
            LaozhangAPIError: 如果响应格式无效或无法提取图片数据
        """
        try:
            # 检查响应结构
            if "candidates" not in response_data or not response_data["candidates"]:
                logger.error("No candidates in response")
                raise LaozhangAPIError("No candidates in response")

            candidate = response_data["candidates"][0]

            if "content" not in candidate:
                logger.error("No content in candidate")
                raise LaozhangAPIError("No content in candidate")

            content = candidate["content"]

            if "parts" not in content or not content["parts"]:
                logger.error("No parts in content")
                raise LaozhangAPIError("No parts in content")

            parts = content["parts"]

            # 遍历所有 parts，找到包含 inlineData 的 part
            image_base64 = None
            for part in parts:
                if "inlineData" in part:
                    inline_data = part["inlineData"]
                    if "data" in inline_data:
                        image_base64 = inline_data["data"]
                        logger.info("Found inlineData in response")
                        break

            if image_base64 is None:
                logger.error("No inlineData found in response")
                raise LaozhangAPIError("No image data in response")

            # 解码为二进制数据
            image_data = base64.b64decode(image_base64)

            logger.debug(f"Image data extracted: {len(image_data)} bytes")
            return image_data

        except LaozhangAPIError:
            raise

        except Exception as e:
            logger.error(f"Failed to extract image data from response: {e}")
            raise LaozhangAPIError(f"Failed to extract image data: {str(e)}")
```

### 5.2 配额管理服务

**文件**：`src/backend/app/services/quota_service.py`

```python
"""
配额管理服务模块

提供用户配额的查询、扣减和管理功能。
"""

import logging
from typing import Dict
from datetime import datetime, timezone
from sqlalchemy import select, update, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User

logger = logging.getLogger(__name__)


class QuotaInfo:
    """配额信息"""
    max_quota: int
    used_quota: int
    remaining_quota: int

    def __init__(self, max_quota: int, used_quota: int, remaining_quota: int):
        self.max_quota = max_quota
        self.used_quota = used_quota
        self.remaining_quota = remaining_quota


class QuotaService:
    """配额管理服务类"""

    def __init__(self, db: AsyncSession):
        """
        初始化配额服务

        Args:
            db: 异步数据库会话
        """
        self.db = db
        logger.info("QuotaService initialized")

    async def check_quota(self, user_id: str) -> QuotaInfo:
        """
        检查用户配额

        Args:
            user_id: 用户 ID

        Returns:
            配额信息

        注意：
            - 如果使用 Google API，不限制配额（用户提供自己的 API Key）
            - 如果使用 Laozhang API，根据订阅等级和免费额度计算
        """
        try:
            # 查询用户
            result = await self.db.execute(
                select(User).where(User.id == user_id)
            )
            user = result.scalar_one()

            # 根据订阅等级和 API 提供商确定配额
            if user.api_provider == "google":
                # Google API 不限制配额（用户提供自己的 API Key）
                max_quota = -1  # -1 表示无限制
            elif user.api_provider == "laozhang":
                # Laozhang API 根据订阅等级确定配额
                if user.subscription_tier == "free":
                    max_quota = user.free_quota
                elif user.subscription_tier == "pro":
                    max_quota = 100  # Pro 用户 100 次
                elif user.subscription_tier == "enterprise":
                    max_quota = 1000  # 企业用户 1000 次
                else:
                    max_quota = 0
            else:
                max_quota = 0

            remaining_quota = max_quota - user.total_quota_used if max_quota != -1 else -1

            return QuotaInfo(
                max_quota=max_quota,
                used_quota=user.total_quota_used,
                remaining_quota=remaining_quota
            )

        except Exception as e:
            logger.error(f"Failed to check quota for user {user_id}: {str(e)}")
            raise

    async def decrement_quota(self, user_id: str) -> bool:
        """
        扣减用户配额

        Args:
            user_id: 用户 ID

        Returns:
            True 如果扣减成功，False 如果配额不足

        注意：
            - Google API 不扣减配额
            - Laozhang API 扣减配额
            - 使用原子操作确保并发安全
        """
        try:
            # 查询用户
            result = await self.db.execute(
                select(User).where(User.id == user_id)
            )
            user = result.scalar_one()

            # Google API 不扣减配额
            if user.api_provider == "google":
                return True

            # 检查配额
            quota_info = await self.check_quota(user_id)
            if quota_info.remaining_quota <= 0:
                logger.warning(f"User {user_id} has no remaining quota")
                return False

            # 扣减配额（原子操作）
            user.total_quota_used += 1
            await self.db.commit()

            logger.info(f"Quota decremented for user {user_id}, remaining: {quota_info.remaining_quota - 1}")
            return True

        except Exception as e:
            logger.error(f"Failed to decrement quota for user {user_id}: {str(e)}")
            await self.db.rollback()
            return False

    async def get_user_api_provider(self, user_id: str) -> str:
        """
        获取用户使用的 API 提供商

        Args:
            user_id: 用户 ID

        Returns:
            API 提供商名称（'google' or 'laozhang'）

        注意：
            - 如果用户未设置 api_provider，默认使用 Google
            - 如果用户邮箱在 email_quota_configs 表中，自动设置为 Laozhang
            - 已使用的邮箱再次注入无效，超过初始指定次数后无效
        """
        try:
            # 查询用户
            result = await self.db.execute(
                select(User).where(User.id == user_id)
            )
            user = result.scalar_one()

            # 如果用户已设置 api_provider，直接返回
            if user.api_provider:
                return user.api_provider

            # 从 email_quota_configs 表查询邮箱配额配置
            quota_result = await self.db.execute(
                text("SELECT initial_quota FROM email_quota_configs WHERE email = :email"),
                {"email": user.email}
            )
            quota_row = quota_result.fetchone()

            if quota_row:
                # 用户邮箱在配置中，自动设置为 Laozhang
                user.api_provider = "laozhang"
                user.free_quota = quota_row[0]
                await self.db.commit()
                logger.info(f"Auto-set user {user_id} ({user.email}) to use Laozhang API with quota {user.free_quota}")
            else:
                # 默认使用 Google API
                user.api_provider = "google"
                await self.db.commit()
                logger.info(f"User {user_id} ({user.email}) uses Google API (no quota config found)")

            return user.api_provider

        except Exception as e:
            logger.error(f"Failed to get API provider for user {user_id}: {str(e)}")
            return "google"  # 默认返回 Google
```

### 5.3 任务服务改造

**文件**：`src/backend/app/services/task_service.py`

**主要改动**：

1. 添加 `QuotaService` 依赖
2. 添加 `ProviderFactory` 依赖
3. 创建任务时自动选择 API 提供商
4. 处理任务时使用工厂模式创建提供商实例
5. Laozhang API 默认使用 2K 分辨率

```python
class TaskService:
    """
    任务服务类（改造后）

    提供生图任务的创建、状态查询和异步处理功能。
    集成 EncryptionService、QuotaService、ProviderFactory、ImageStorage 实现完整的生图流程。
    """

    def __init__(
        self,
        db: AsyncSession,
        encryption_service: RSAEncryptionService,
        storage: Optional[ImageStorage] = None,
        quota_service: Optional[QuotaService] = None
    ):
        """
        初始化任务服务

        Args:
            db: 异步数据库会话
            encryption_service: RSA 加密服务实例
            storage: 图片存储服务实例（可选）
            quota_service: 配额管理服务实例（可选）
        """
        self.db = db
        self.encryption_service = encryption_service
        self.storage = storage or ImageStorage()
        self.quota_service = quota_service or QuotaService(db)
        self.provider_factory = ProviderFactory()

        logger.info("TaskService initialized successfully")

    async def create_task(
        self,
        user_id: str,
        encrypted_api_key: str,
        prompt: str,
        base_image: Optional[str] = None
    ) -> str:
        """
        创建生图任务（改造后）

        改动：
        1. 自动选择 API 提供商
        2. 检查配额（仅 Laozhang API）
        3. 记录 API 提供商到任务

        Args:
            user_id: 用户 ID
            encrypted_api_key: 加密的 API Key
            prompt: 提示词
            base_image: 参考图的 Base64 编码（可选）

        Returns:
            任务 ID

        Raises:
            TaskServiceError: 如果任务创建失败或配额不足
        """
        # ... 参数验证 ...

        try:
            # 自动选择 API 提供商
            provider_name = await self.quota_service.get_user_api_provider(user_id)

            # 检查配额（仅 Laozhang API）
            if provider_name == "laozhang":
                quota_info = await self.quota_service.check_quota(user_id)
                if quota_info.remaining_quota <= 0:
                    logger.warning(f"User {user_id} has exceeded quota for Laozhang API")
                    raise TaskServiceError("Quota exceeded. Please upgrade your subscription.")

            # 创建任务记录
            task = Task(
                user_id=user_id,
                encrypted_api_key=encrypted_api_key,
                prompt=prompt,
                base_image=base_image,
                status="pending",
                api_provider=provider_name,
                image_size="2K" if provider_name == "laozhang" else "1K"
            )

            # 保存到数据库
            self.db.add(task)
            await self.db.commit()
            await self.db.refresh(task)

            logger.info(f"Task created: {task.id}, user_id={user_id}, provider={provider_name}, image_size={task.image_size}")

            # 异步处理任务
            asyncio.create_task(self._process_task(str(task.id)))

            return str(task.id)

        except Exception as e:
            logger.error(f"Failed to create task: {str(e)}")
            await self.db.rollback()
            raise TaskServiceError(f"Failed to create task: {str(e)}")

    async def _process_task(self, task_id: str):
        """
        处理任务（改造后）

        改动：
        1. 使用工厂模式创建提供商实例
        2. 根据提供商选择图片尺寸
        3. 任务完成后扣减配额（仅 Laozhang API）

        Args:
            task_id: 任务 ID
        """
        logger.info(f"Starting to process task: {task_id}")

        try:
            # 更新状态为处理中
            await self._update_task_status(task_id, "processing")

            # 获取任务
            result = await self.db.execute(
                select(Task).where(Task.id == task_id)
            )
            task = result.scalar_one()

            # 解密 API Key
            try:
                import base64
                encrypted_bytes = base64.b64decode(task.encrypted_api_key)
                api_key = self.encryption_service.decrypt(encrypted_bytes)
                logger.info(f"API Key decrypted for task {task_id}")
            except RSAEncryptionError as e:
                logger.error(f"Failed to decrypt API Key for task {task_id}: {str(e)}")
                raise TaskServiceError(f"Failed to decrypt API Key: {str(e)}")

            # 使用工厂模式创建提供商实例
            provider = self.provider_factory.create_provider(task.api_provider)
            logger.info(f"Using provider: {task.api_provider} for task {task_id}")

            # 调用 API 生成图片
            try:
                image_data = await provider.generate_image(
                    api_key=api_key,
                    prompt=task.prompt,
                    base_image=task.base_image,
                    image_size=task.image_size
                )
                logger.info(f"Image generated successfully for task {task_id}, size={len(image_data)} bytes")
            except Exception as e:
                logger.error(f"API error for task {task_id}: {str(e)}")
                raise TaskServiceError(f"API error: {str(e)}")

            # 立即清除内存中的 API Key
            api_key = None

            # 保存图片到本地存储
            try:
                image_url = await self._save_image(task_id, image_data)
                logger.info(f"Image saved for task {task_id}: {image_url}")
            except Exception as e:
                logger.error(f"Failed to save image for task {task_id}: {str(e)}")
                raise TaskServiceError(f"Failed to save image: {str(e)}")

            # 设置图片过期时间（7天后）
            image_expires_at = datetime.now(timezone.utc) + timedelta(days=7)

            # 更新任务状态为完成
            await self._update_task_status(
                task_id,
                "completed",
                image_url=image_url,
                image_expires_at=image_expires_at
            )
            logger.info(f"Task {task_id} completed successfully")

            # 扣减配额（仅 Laozhang API）
            if task.api_provider == "laozhang":
                await self.quota_service.decrement_quota(task.user_id)
                logger.info(f"Quota decremented for user {task.user_id}")

            # 清除数据库中的 API Key
            await self._clear_api_key(task_id)

        except Exception as e:
            # 更新任务状态为失败
            logger.error(f"Task {task_id} failed: {str(e)}")
            await self._update_task_status(
                task_id,
                "failed",
                error_message=str(e)
            )
            # 清除数据库中的 API Key
            await self._clear_api_key(task_id)
```

### 5.4 提供商工厂

**文件**：`src/backend/app/services/provider_factory.py`

```python
"""
API 提供商工厂模块

提供统一的 API 提供商创建接口。
"""

import logging

from app.services.google_api import GoogleAPIClient
from app.services.laozhang_api import LaozhangAPIClient

logger = logging.getLogger(__name__)


class ProviderFactory:
    """API 提供商工厂类"""

    @staticmethod
    def create_provider(provider_name: str):
        """
        创建 API 提供商实例

        Args:
            provider_name: 提供商名称（'google' or 'laozhang'）

        Returns:
            API 提供商实例

        Raises:
            ValueError: 如果提供商名称无效

        支持的提供商：
        - google: Google API (gemini-3-pro-image-preview)
        - laozhang: Laozhang API (gemini-3-pro-image-preview)
        """
        providers = {
            "google": GoogleAPIClient,
            "laozhang": LaozhangAPIClient
        }

        provider_class = providers.get(provider_name)
        if not provider_class:
            logger.error(f"Unknown provider: {provider_name}")
            raise ValueError(f"Unknown provider: {provider_name}")

        logger.info(f"Created provider: {provider_name}")
        return provider_class()
```

---

## 7. 数据模型

### 7.1 请求模型

**接口**：`POST /api/v1/admin/email-quota`

**认证**：使用 `ADMIN_SECRET_KEY` 进行认证

**请求头**：
```
admin-secret: your-admin-secret-key
```

**请求体**：
```json
{
  "email": "test@example.com",
  "quota": 10
}
```

**响应**：
```json
{
  "success": true,
  "message": "Email quota injected successfully"
}
```

**错误响应**：
```json
{
  "success": false,
  "error": "Email already has quota configured"
}
```

**规则**：
- 已使用的邮箱再次注入无效
- 超过初始指定次数后无效，只能走 Google API Key 方式

#### 7.1.2 查询邮箱配额列表

**接口**：`GET /api/v1/admin/email-quota`

**认证**：使用 `ADMIN_SECRET_KEY` 进行认证

**请求头**：
```
admin-secret: your-admin-secret-key
```

**响应**：
```json
{
  "total": 2,
  "items": [
    {
      "email": "test@example.com",
      "initial_quota": 10,
      "created_at": "2026-01-22T10:00:00Z"
    },
    {
      "email": "another@example.com",
      "initial_quota": 10,
      "created_at": "2026-01-22T11:00:00Z"
    }
  ]
}
```

### 6.2 用户接口

#### 7.2.1 查询用户配额

**接口**：`GET /api/v1/users/me/quota`

**认证**：JWT Token

**请求头**：
```
Authorization: Bearer <access_token>
```

**响应**：
```json
{
  "api_provider": "laozhang",
  "has_free_quota": true,
  "max_quota": 10,
  "used_quota": 3,
  "remaining_quota": 7,
  "subscription_tier": "free"
}
```

**字段说明**：
- `api_provider`：用户使用的 API 提供商（'google' or 'laozhang'）
- `has_free_quota`：是否有免费额度
- `max_quota`：最大配额（-1 表示无限制）
- `used_quota`：已使用配额
- `remaining_quota`：剩余配额
- `subscription_tier`：订阅等级（'free', 'pro', 'enterprise'）

---

## 7. 数据模型

### 8.1 请求模型

#### EmailQuotaInjectRequest

```python
class EmailQuotaInjectRequest(BaseModel):
    """邮箱配额注入请求"""
    email: str
    quota: int
    
    class Config:
        json_schema_extra = {
            "example": {
                "email": "test@example.com",
                "quota": 10
            }
        }
```

### 8.2 响应模型

#### UserQuotaResponse

```python
class UserQuotaResponse(BaseModel):
    """用户配额响应"""
    api_provider: str
    has_free_quota: bool
    max_quota: int
    used_quota: int
    remaining_quota: int
    subscription_tier: str
    
    class Config:
        json_schema_extra = {
            "example": {
                "api_provider": "laozhang",
                "has_free_quota": True,
                "max_quota": 10,
                "used_quota": 3,
                "remaining_quota": 7,
                "subscription_tier": "free"
            }
        }
```

---

## 8. 文件结构

### 8.1 后端文件结构

```
src/backend/
├── app/
│   ├── routers/
│   │   ├── admin.py                    # 新增：管理员接口
│   │   ├── users.py                    # 新增：用户接口
│   │   └── tasks.py                    # 修改：任务接口
│   ├── services/
│   │   ├── laozhang_api.py             # 新增：Laozhang API 客户端
│   │   ├── quota_service.py            # 新增：配额管理服务
│   │   ├── provider_factory.py         # 新增：提供商工厂
│   │   └── task_service.py             # 修改：任务服务
│   ├── models/
│   │   ├── user.py                     # 修改：用户模型
│   │   └── task.py                     # 修改：任务模型
│   ├── config.py                       # 修改：配置
│   └── main.py                         # 修改：注册新路由
└── scripts/
    ├── inject_email_quota.py           # 新增：邮箱配额注入脚本
    └── list_email_quotas.py            # 新增：邮箱配额查询脚本
```

### 8.2 iOS 文件结构

```
src/MindCanvas/MindCanvas/
├── Services/
│   ├── QuotaService.swift              # 新增：配额查询服务
│   └── RealGenerationService.swift     # 修改：生图服务
├── ViewModels/
│   └── NativeEditorViewModel.swift     # 修改：编辑器视图模型
└── Views/
    └── Editor/
        └── NativeEditorView.swift      # 修改：编辑器视图
```

---

## 9. 环境配置

### 9.1 .env 文件更新

```bash
# ... 现有配置 ...

# ==================== Laozhang API 配置 ====================
LAOZHANG_API_KEY=sk-YOUR_LAOZHANG_API_KEY

# ==================== 管理员密钥 ====================
# 用于邮箱配额注入接口认证
ADMIN_SECRET_KEY=your-admin-secret-key-change-in-production
```

### 9.2 docker-compose.yml 更新

```yaml
services:
  backend:
    # ... 现有配置 ...
    environment:
      # ... 现有环境变量 ...
      # Laozhang API 配置
      - LAOZHANG_API_KEY=${LAOZHANG_API_KEY}
      # 管理员密钥
      - ADMIN_SECRET_KEY=${ADMIN_SECRET_KEY}
```

---

## 10. iOS 客户端适配

### 10.1 无需修改

由于 API 接口保持不变，iOS 客户端无需任何修改：

1. **API 接口不变**：`POST /api/v1/generate/tasks` 接口参数和返回值不变
2. **加密方式不变**：继续使用 RSA 公钥加密 API Key
3. **流程不变**：创建任务 → 轮询状态 → 获取图片

### 10.2 后端自动处理

后端会自动处理以下逻辑：

1. **提供商选择**：根据用户邮箱自动选择 API 提供商
2. **配额管理**：自动检查和扣减配额
3. **图片尺寸**：Laozhang API 默认使用 2K 分辨率

---

## 11. 管理工具

### 11.1 邮箱配额注入脚本

**文件**：`src/backend/scripts/inject_email_quota.py`

```python
#!/usr/bin/env python3
"""
邮箱配额注入脚本

使用方法：
    python inject_email_quota.py <email> <quota>

示例：
    python inject_email_quota.py test@example.com 10
"""

import sys
import asyncio
import httpx


async def inject_email_quota(email: str, quota: int, admin_secret: str):
    """注入邮箱配额"""
    url = "http://localhost:8000/api/v1/admin/email-quota"

    headers = {
        "admin-secret": admin_secret,
        "Content-Type": "application/json"
    }

    payload = {
        "email": email,
        "quota": quota
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, headers=headers, json=payload)

        if response.status_code == 201:
            result = response.json()
            print(f"✅ {result['message']}")
            print(f"   Email: {email}")
            print(f"   Quota: {quota}")
        else:
            error = response.json()
            print(f"❌ Failed: {error.get('detail', 'Unknown error')}")
            sys.exit(1)


def main():
    """主函数"""
    if len(sys.argv) < 3:
        print("Usage: python inject_email_quota.py <email> <quota>")
        print("Example: python inject_email_quota.py test@example.com 10")
        sys.exit(1)

    email = sys.argv[1]
    quota = int(sys.argv[2])

    # 从环境变量读取管理员密钥
    import os
    admin_secret = os.getenv("ADMIN_SECRET_KEY", "")

    if not admin_secret:
        print("Error: ADMIN_SECRET_KEY environment variable not set")
        sys.exit(1)

    asyncio.run(inject_email_quota(email, quota, admin_secret))


if __name__ == "__main__":
    main()
```

### 11.2 使用示例

```bash
# 设置管理员密钥
export ADMIN_SECRET_KEY="your-admin-secret-key"

# 注入邮箱配额
python src/backend/scripts/inject_email_quota.py test@example.com 10
```

### 11.3 邮箱配额查询脚本

**文件**：`src/backend/scripts/list_email_quotas.py`

```python
#!/usr/bin/env python3
"""
邮箱配额查询脚本

使用方法：
    python list_email_quotas.py
"""

import sys
import asyncio
import httpx


async def list_email_quotas(admin_secret: str):
    """查询所有邮箱配额"""
    url = "http://localhost:8000/api/v1/admin/email-quota"

    headers = {
        "admin-secret": admin_secret
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, headers=headers)

        if response.status_code == 200:
            result = response.json()
            print(f"\n=== Email Quotas ({result['total']}) ===")
            for item in result['items']:
                print(f"  - {item['email']}: {item['initial_quota']} (created at {item['created_at']})")
        else:
            error = response.json()
            print(f"❌ Failed: {error.get('detail', 'Unknown error')}")
            sys.exit(1)


def main():
    """主函数"""
    # 从环境变量读取管理员密钥
    import os
    admin_secret = os.getenv("ADMIN_SECRET_KEY", "")

    if not admin_secret:
        print("Error: ADMIN_SECRET_KEY environment variable not set")
        sys.exit(1)

    asyncio.run(list_email_quotas(admin_secret))


if __name__ == "__main__":
    main()
```

---

## 12. 测试方案

### 10.1 单元测试

**文件**：`src/backend/tests/test_laozhang_api.py`

```python
"""
Laozhang API 客户端单元测试
"""

import pytest
from app.services.laozhang_api import LaozhangAPIClient, LaozhangAPIError


@pytest.mark.asyncio
async def test_laozhang_generate_image_text_to_image():
    """测试文生图"""
    client = LaozhangAPIClient()

    image_data = await client.generate_image(
        api_key="test_api_key",
        prompt="A beautiful sunset",
        image_size="2K"
    )

    assert len(image_data) > 0


@pytest.mark.asyncio
async def test_laozhang_generate_image_image_to_image():
    """测试图生图"""
    client = LaozhangAPIClient()

    import base64
    with open("test_image.png", "rb") as f:
        base_image = base64.b64encode(f.read()).decode()

    image_data = await client.generate_image(
        api_key="test_api_key",
        prompt="Make it more colorful",
        base_image=base_image,
        image_size="2K"
    )

    assert len(image_data) > 0


@pytest.mark.asyncio
async def test_laozhang_invalid_api_key():
    """测试无效 API Key"""
    client = LaozhangAPIClient()

    with pytest.raises(LaozhangAPIError):
        await client.generate_image(
            api_key="invalid_key",
            prompt="A beautiful sunset"
        )
```

**文件**：`src/backend/tests/test_quota_service.py`

```python
"""
配额管理服务单元测试
"""

import pytest
from app.services.quota_service import QuotaService, QuotaInfo


@pytest.mark.asyncio
async def test_check_quota_google_user():
    """测试 Google 用户配额（无限制）"""
    # ... 测试代码 ...


@pytest.mark.asyncio
async def test_check_quota_laozhang_user():
    """测试 Laozhang 用户配额"""
    # ... 测试代码 ...


@pytest.mark.asyncio
async def test_decrement_quota():
    """测试扣减配额"""
    # ... 测试代码 ...
```

### 10.2 集成测试

**文件**：`src/backend/tests/test_task_integration.py`

```python
"""
任务集成测试
"""

import pytest
from app.services.task_service import TaskService


@pytest.mark.asyncio
async def test_create_task_with_laozhang_provider():
    """测试使用 Laozhang API 创建任务"""
    # ... 测试代码 ...


@pytest.mark.asyncio
async def test_quota_exceeded():
    """测试配额超限"""
    # ... 测试代码 ...
```

### 10.3 手动测试

```bash
# 1. 配置环境变量
export LAOZHANG_API_KEY="sk-YOUR_API_KEY"
export LAOZHANG_ALLOWED_EMAILS="test@example.com:10"

# 2. 重启后端服务
docker-compose restart backend

# 3. 创建测试用户（test@example.com）
# 4. 使用 iOS 客户端创建任务
# 5. 验证任务使用 Laozhang API
# 6. 验证配额扣减
# 7. 验证图片尺寸为 2K
```

---

## 13. 监控和日志

### 11.1 关键指标

1. **API 提供商分布**：Google vs Laozhang 使用比例
2. **配额使用率**：免费额度使用情况
3. **任务成功率**：按提供商统计
4. **响应时间**：按提供商统计

### 11.2 日志记录

```python
# 任务创建时
logger.info(f"Task created: {task_id}, user_id={user_id}, provider={provider_name}, image_size={task.image_size}")

# API 调用时
logger.info(f"Using provider: {provider_name} for task {task_id}")

# 配额扣减时
logger.info(f"Quota decremented for user {user_id}, remaining: {remaining}")

# 错误时
logger.error(f"Task {task_id} failed: {error}")
```

---

## 14. 未来扩展

### 12.1 订阅功能

**设计基础**：User 表已预留 `subscription_tier` 和 `subscription_expires_at` 字段

**实现方案**：
1. 添加订阅等级配置（Pro: 100 次/月，Enterprise: 1000 次/月）
2. 添加订阅支付接口
3. 添加订阅管理接口
4. 配额计算逻辑已支持订阅等级

### 12.2 更多 API 提供商

**扩展方案**：
1. 实现新的 `ImageGenerationProvider` 子类
2. 在 `ProviderFactory` 中注册新提供商
3. 在 `QuotaService` 中添加配额计算逻辑

### 12.3 用户可选图片尺寸

**扩展方案**：
1. 在 TaskCreate 请求中添加 `image_size` 参数
2. 在任务创建时使用用户指定的尺寸
3. 不同尺寸可能消耗不同配额

---

## 15. 风险和注意事项

### 13.1 安全风险

1. **API Key 泄露**：
   - 已实现：RSA 加密存储
   - 已实现：任务完成后清除
   - 注意：日志中不记录 API Key

2. **配额滥用**：
   - 已实现：配额检查
   - 已实现：原子操作扣减
   - 注意：监控异常使用模式

### 13.2 性能风险

1. **Laozhang API 响应慢**：
   - 已设置：超时时间 180 秒
   - 建议：监控响应时间
   - 建议：考虑添加重试机制

2. **数据库并发**：
   - 已实现：原子操作扣减配额
   - 建议：添加数据库连接池监控

### 13.3 业务风险

1. **配额不足用户体验**：
   - 建议：提前提示用户配额即将用完
   - 建议：提供配额购买入口

2. **API 提供商故障**：
   - 建议：添加提供商健康检查
   - 建议：考虑自动切换到备用提供商

---

## 16. 部署清单

### 16.1 代码修改

**后端**：
- [ ] 创建 `src/backend/app/services/laozhang_api.py`
- [ ] 创建 `src/backend/app/services/quota_service.py`
- [ ] 创建 `src/backend/app/services/provider_factory.py`
- [ ] 创建 `src/backend/app/routers/admin.py`
- [ ] 创建 `src/backend/app/routers/users.py`
- [ ] 修改 `src/backend/app/services/task_service.py`
- [ ] 修改 `src/backend/app/config.py`
- [ ] 修改 `src/backend/app/models/user.py`
- [ ] 修改 `src/backend/app/models/task.py`
- [ ] 修改 `src/backend/app/models/schemas.py`
- [ ] 修改 `src/backend/app/main.py`（注册新路由）
- [ ] 创建 `src/backend/scripts/inject_email_quota.py`
- [ ] 创建 `src/backend/scripts/list_email_quotas.py`

**iOS**：
- [ ] 创建 `src/MindCanvas/MindCanvas/Services/QuotaService.swift`
- [ ] 修改 `src/MindCanvas/MindCanvas/ViewModels/NativeEditorViewModel.swift`
- [ ] 修改 `src/MindCanvas/MindCanvas/Views/Editor/NativeEditorView.swift`
- [ ] 修改 `src/MindCanvas/MindCanvas/Services/RealGenerationService.swift`

### 16.2 数据库初始化

- [ ] 创建数据库表（参考"3. 数据库设计"章节）
- [ ] 执行初始化 SQL 脚本

### 16.3 配置更新

- [ ] 更新 `src/backend/.env`
- [ ] 更新 `src/backend/docker-compose.yml`

### 16.4 测试

**后端**：
- [ ] 单元测试
- [ ] 集成测试
- [ ] 手动测试

**iOS**：
- [ ] 功能测试
- [ ] 边界测试
- [ ] UI 测试

### 14.5 文档

- [ ] 更新 API 文档
- [ ] 更新部署文档
- [ ] 更新运维手册
- [ ] 更新用户手册

---

## 17. 总结

### 15.1 核心特性

1. **多提供商支持**：Google API + Laozhang API
2. **动态邮箱注入**：通过 API 接口动态注入邮箱配额，无需修改环境变量
3. **自动提供商选择**：根据邮箱自动选择
4. **配额管理**：免费额度 + 订阅等级
5. **默认 2K 分辨率**：Laozhang API 默认使用 2K
6. **iOS 配额提醒**：在 iOS 端显示配额提示信息

### 15.2 技术亮点

1. **抽象工厂模式**：统一的 API 提供商接口
2. **配额原子操作**：确保并发安全
3. **安全加密**：RSA 加密存储 API Key
4. **可扩展设计**：为未来订阅功能预留
5. **动态配置**：邮箱配额动态注入，无需重启服务
6. **智能提示**：根据配额状态显示不同的提示信息

### 15.3 实施优先级

**P0（必须）**：
- Laozhang API 客户端
- 配额管理服务
- 任务服务改造
- 数据库迁移
- 管理员接口
- 命令行注入脚本

**P1（重要）**：
- 用户配额查询接口
- iOS 配额查询服务
- iOS 编辑器视图更新
- 单元测试
- 日志和监控

**P2（可选）**：
- 集成测试
- 性能优化
- 更多提供商支持
- 配额历史记录

### 15.4 关键约束

1. **已使用的邮箱再次注入无效**：
   - 检查 `total_quota_used > 0`
   - 返回错误提示

2. **超过初始指定次数后无效**：
   - 检查 `total_quota_used >= initial_quota`
   - 引导用户配置 Google API Key

3. **不影响现有功能**：
   - 所有改动都是增量式的
   - 不修改现有 API Key 配置流程
   - iOS 端改动最小化

4. **UI 风格一致性**：
   - 使用现有的主题颜色和样式
   - 保持与现有设计风格一致