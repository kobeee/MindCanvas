# MindCanvas 后端优化改造方案

## 1. 现状分析

### 1.1 邮箱验证登录功能

**现有实现：**
- `auth_service.py` 中的 `login_with_provider` 方法支持邮箱登录
- `_verify_provider_token` 方法中邮箱登录是 Mock 实现，返回假的用户信息
- 没有真实的邮件发送功能
- 没有验证码生成和存储机制
- 没有验证码过期时间管理

**问题：**
- 邮箱验证登录功能不完整，缺少邮件发送功能
- 没有验证码生成、存储和验证机制
- Mock 实现无法用于生产环境

### 1.2 生图服务

**现有实现：**
- `task_service.py` 提供完整的生图任务创建、状态查询和异步处理功能
- 支持文本到图片生成和图片到图片生成
- API Key 加密存储，任务完成后立即删除
- 支持异步轮询（通过 `get_task_status` 接口）
- 图片保存到本地存储

**问题：**
- 生图服务本身设计良好，但缺少图片生命周期管理
- `cleanup_old_tasks` 方法存在，但没有定期执行机制
- 没有自动清理过期图片的后台任务
- 图片生命周期管理机制不完善

### 1.3 图片生命周期管理

**现有实现：**
- `image_storage.py` 提供图片保存、删除和获取功能
- `cleanup_old_images` 方法可以清理指定天数前的旧图片
- `task_service.py` 中的 `cleanup_old_tasks` 方法可以清理过期任务

**问题：**
- 清理功能存在但没有定期执行机制
- 没有自动清理的后台任务
- 图片和任务的清理是分离的，可能导致数据不一致

### 1.4 API Key 安全机制

**现有实现：**
- 使用 `EncryptionService` 加密 API Key
- 任务完成后立即删除 API Key
- API Key 只在内存中临时存在

**问题：**
- API Key 安全机制设计良好，但可以进一步优化
- 可以考虑使用更安全的加密算法或密钥管理服务

### 1.5 冗余功能

**冗余功能：**
- `feed_service.py` 和 `feed.py` 提供社区动态功能，但不是核心需求
- `asset_service.py` 提供资源上传功能，但不是核心需求

**处理方式：**
- 这些功能不影响核心功能，可以保留

---

## 2. 优化方案

### 2.1 邮箱验证登录流程设计

**流程：**
```
用户输入邮箱
    ↓
APP 调用 POST /api/v1/auth/send-verification-code
    ↓
后端生成 6 位数字验证码，存储到 Redis（5分钟过期）
    ↓
后端发送验证码到用户邮箱（使用 SMTP）
    ↓
用户在 APP 输入验证码
    ↓
APP 调用 POST /api/v1/auth/verify-email
    ↓
后端验证验证码是否正确和未过期
    ↓
验证成功后，查找或创建用户，返回 Access Token（7天）+ Refresh Token（30天）
```

**技术选型：**
- 邮件服务：`aiosmtplib`（异步 SMTP 客户端）
- 验证码存储：Redis，设置 5 分钟过期时间
- 验证码格式：6 位数字
- 邮件频率限制：同一邮箱 1 分钟内只能发送一次
- Token 机制：Access Token（7天）+ Refresh Token（30天）

**Token 刷新流程：**
```
Access Token 过期（7天后）
    ↓
APP 使用 Refresh Token 调用 POST /api/v1/auth/refresh
    ↓
后端验证 Refresh Token 是否有效且未过期
    ↓
验证成功，返回新的 Access Token（7天）
    ↓
用户无需重新输入邮箱和验证码 ✅
```

**时间线示意：**
```
登录 ──┬── Access Token (7天)
       │
       ├── 第7天: Refresh Token 刷新
       │
       ├── 第14天: Refresh Token 刷新
       │
       ├── 第21天: Refresh Token 刷新
       │
       ├── 第28天: Refresh Token 刷新
       │
       └── 第30天: Refresh Token 过期 ❌
                    ↓
              需要重新发送验证码
```

**API 接口设计：**

**发送验证码：**
```
POST /api/v1/auth/send-verification-code
Request Body:
{
    "email": "user@example.com"
}

Response:
{
    "message": "Verification code sent successfully",
    "expires_in": 300  // 5分钟，单位：秒
}
```

**验证邮箱并登录：**
```
POST /api/v1/auth/verify-email
Request Body:
{
    "email": "user@example.com",
    "code": "123456"
}

Response:
{
    "access_token": "jwt_token_string",
    "refresh_token": "refresh_token_string",
    "token_type": "bearer",
    "expires_in": 604800,  // 7天，单位：秒
    "user": {
        "id": "uuid",
        "email": "user@example.com",
        "username": "user123",
        "avatar_url": null
    }
}
```

**刷新 Token：**
```
POST /api/v1/auth/refresh
Request Body:
{
    "refresh_token": "refresh_token_string"
}

Response:
{
    "access_token": "new_jwt_token_string",
    "token_type": "bearer",
    "expires_in": 604800  // 7天，单位：秒
}
```

### 2.2 生图服务流程设计

**流程：**
```
用户在 APP 输入提示词和 API Key
    ↓
APP 使用 RSA 公钥加密 API Key
    ↓
APP 调用 POST /api/v1/generate/tasks
    ↓
后端创建任务记录，状态为 pending
    ↓
后端启动异步任务处理生图请求
    ↓
APP 轮询 GET /api/v1/generate/tasks/{task_id}/status
    ↓
后端更新任务状态为 processing
    ↓
后端解密 API Key，调用 Google API 生成图片
    ↓
后端保存图片到本地存储，设置图片过期时间
    ↓
后端更新任务状态为 completed
    ↓
APP 轮询到 completed 状态，下载图片到本地
    ↓
后端清除 API Key（已完成）
```

**技术选型：**
- 异步任务处理：`asyncio.create_task`
- 图片存储：本地存储（预留云存储接口）
- API Key 加密：`EncryptionService`（Fernet 对称加密）
- 图片保留期：7 天

### 2.3 图片生命周期管理设计

**流程：**
```
任务完成，图片保存到本地存储
    ↓
设置图片过期时间（当前时间 + 7天）
    ↓
APP 下载图片后，图片进入 7 天保留期
    ↓
后台任务每天凌晨 3 点执行清理
    ↓
查询超过 7 天的图片
    ↓
删除图片文件
    ↓
删除数据库记录（可选）
```

**技术选型：**
- 后台任务调度：`apscheduler`（异步任务调度库）
- 图片保留期：7 天
- 清理策略：每天凌晨 3 点执行清理任务
- 清理范围：只清理已完成或失败的任务图片

### 2.4 API Key 安全机制设计

**流程：**
```
APP 使用 RSA 公钥加密 API Key
    ↓
APP 发送加密后的 API Key 到后端
    ↓
后端使用 Fernet 对称加密再次加密
    ↓
加密后的 API Key 存储到数据库
    ↓
任务处理时解密 API Key 到内存
    ↓
调用 Google API 完成后立即清除内存中的 API Key
    ↓
任务完成后清除数据库中的 API Key
```

**技术选型：**
- 客户端加密：RSA 非对称加密（公钥加密，私钥解密）
- 服务端加密：Fernet 对称加密（AES-128-CBC + HMAC-SHA256）
- 密钥管理：环境变量存储，不硬编码

### 2.5 数据库模型设计

**需要新增的字段：**

**users 表新增字段：**
```sql
ALTER TABLE users ADD COLUMN refresh_token VARCHAR(500);
ALTER TABLE users ADD COLUMN refresh_token_expires_at TIMESTAMP WITH TIME ZONE;

COMMENT ON COLUMN users.refresh_token IS '刷新令牌（30天有效期）';
COMMENT ON COLUMN users.refresh_token_expires_at IS '刷新令牌过期时间';

CREATE INDEX idx_users_refresh_token ON users(refresh_token);
```

**generation_tasks 表新增字段：**
```sql
ALTER TABLE generation_tasks ADD COLUMN image_expires_at TIMESTAMP WITH TIME ZONE;
COMMENT ON COLUMN generation_tasks.image_expires_at IS '图片过期时间（7天后自动清理）';
```

**需要新增的表：**

**email_verification_codes 表（可选，也可以只用 Redis）：**
```sql
CREATE TABLE IF NOT EXISTS email_verification_codes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL,
    code VARCHAR(6) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    used_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_email_verification_codes_email ON email_verification_codes(email);
CREATE INDEX idx_email_verification_codes_expires_at ON email_verification_codes(expires_at);
```

**说明：**
- 邮箱验证码可以只存储在 Redis 中，不需要持久化到数据库
- 如果需要审计日志，可以创建 `email_verification_codes` 表
- `refresh_token` 存储在 `users` 表中，用于刷新 Access Token

### 2.6 API 接口设计

**新增接口：**

| 接口 | 方法 | 描述 |
|------|------|------|
| `/api/v1/auth/send-verification-code` | POST | 发送验证码 |
| `/api/v1/auth/verify-email` | POST | 验证邮箱并登录 |
| `/api/v1/auth/refresh` | POST | 刷新 Access Token |

**修改接口：**

| 接口 | 修改内容 |
|------|----------|
| `/api/v1/auth/login` | 支持邮箱验证码登录，返回 refresh_token |

**保留接口：**

| 接口 | 描述 |
|------|------|
| `/api/v1/auth/me` | 获取当前用户信息 |
| `/api/v1/auth/logout` | 用户登出 |
| `/api/v1/generate/tasks` | 创建生图任务 |
| `/api/v1/generate/tasks/{task_id}/status` | 查询任务状态 |

---

## 3. 实施步骤

### Step 1: 添加邮件服务依赖

**文件：`src/backend/requirements.txt`**

添加以下依赖：
```
aiosmtplib==3.0.1
apscheduler==3.10.4
redis==5.0.1
```

### Step 2: 创建邮件服务

**文件：`src/backend/app/services/email_service.py`**

创建邮件服务类，提供异步发送邮件功能：

```python
"""
邮件服务模块

提供异步发送邮件功能，使用 SMTP 协议。
支持发送验证码邮件、通知邮件等。
"""

import aiosmtplib
from email.message import EmailMessage
from typing import Optional
import logging

logger = logging.getLogger(__name__)


class EmailServiceError(Exception):
    """邮件服务异常基类"""
    pass


class EmailService:
    """
    邮件服务类

    使用 aiosmtplib 提供异步发送邮件功能。

    使用方法：
        # 初始化服务
        email_service = EmailService(
            host="smtp.gmail.com",
            port=587,
            username="your_email@gmail.com",
            password="your_password"
        )

        # 发送验证码邮件
        await email_service.send_verification_code(
            to_email="user@example.com",
            code="123456"
        )
    """

    def __init__(
        self,
        host: str,
        port: int,
        username: str,
        password: str,
        use_tls: bool = True
    ):
        """
        初始化邮件服务

        Args:
            host: SMTP 服务器地址
            port: SMTP 服务器端口
            username: 邮箱账号
            password: 邮箱密码或应用专用密码
            use_tls: 是否使用 TLS 加密
        """
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.use_tls = use_tls
        logger.info(f"EmailService initialized: {host}:{port}")

    async def send_verification_code(
        self,
        to_email: str,
        code: str,
        expiry_minutes: int = 5
    ) -> bool:
        """
        发送验证码邮件

        Args:
            to_email: 收件人邮箱
            code: 验证码
            expiry_minutes: 验证码过期时间（分钟）

        Returns:
            是否发送成功

        Raises:
            EmailServiceError: 如果发送失败
        """
        try:
            # 创建邮件消息
            message = EmailMessage()
            message["From"] = self.username
            message["To"] = to_email
            message["Subject"] = "MindCanvas 验证码"

            # 邮件正文
            body = f"""
            您的 MindCanvas 验证码是：{code}

            验证码有效期为 {expiry_minutes} 分钟，请尽快使用。

            如果这不是您的操作，请忽略此邮件。
            """

            message.set_content(body.strip())

            # 发送邮件
            await aiosmtplib.send(
                message,
                hostname=self.host,
                port=self.port,
                username=self.username,
                password=self.password,
                use_tls=self.use_tls
            )

            logger.info(f"Verification code sent to {to_email}")
            return True

        except Exception as e:
            logger.error(f"Failed to send email to {to_email}: {str(e)}")
            raise EmailServiceError(f"Failed to send email: {str(e)}")
```

### Step 3: 修改认证服务

**文件：`src/backend/app/services/auth_service.py`**

修改 `AuthService` 类，添加邮箱验证登录逻辑：

```python
# 在 AuthService 类中添加以下方法

async def send_verification_code(self, email: str, redis_client) -> str:
    """
    发送验证码到邮箱

    Args:
        email: 邮箱地址
        redis_client: Redis 客户端

    Returns:
        验证码

    Raises:
        AuthError: 如果发送失败
    """
    import random
    from datetime import timedelta

    # 检查发送频率限制（1分钟内只能发送一次）
    rate_limit_key = f"email_rate_limit:{email}"
    if await redis_client.exists(rate_limit_key):
        raise AuthError("Verification code already sent, please wait")

    # 生成 6 位数字验证码
    code = str(random.randint(100000, 999999))

    # 存储验证码到 Redis（5分钟过期）
    verification_key = f"email_verification:{email}"
    await redis_client.setex(verification_key, 300, code)

    # 设置发送频率限制（1分钟）
    await redis_client.setex(rate_limit_key, 60, "1")

    # 发送邮件
    from app.services.email_service import EmailService
    from app.config import settings

    email_service = EmailService(
        host=settings.SMTP_HOST,
        port=settings.SMTP_PORT,
        username=settings.SMTP_USERNAME,
        password=settings.SMTP_PASSWORD,
        use_tls=settings.SMTP_USE_TLS
    )

    await email_service.send_verification_code(email, code)

    logger.info(f"Verification code sent to {email}")
    return code


async def create_refresh_token(self, user_id: str) -> tuple[str, datetime]:
    """
    创建 Refresh Token

    Args:
        user_id: 用户 ID

    Returns:
        (refresh_token, expires_at)

    Raises:
        AuthError: 如果创建失败
    """
    import secrets
    from datetime import datetime, timedelta

    # 生成随机 Refresh Token
    refresh_token = secrets.token_urlsafe(64)

    # 设置过期时间（30天后）
    expires_at = datetime.utcnow() + timedelta(days=30)

    # 更新用户记录
    await self.db.execute(
        update(User).where(User.id == user_id).values(
            refresh_token=refresh_token,
            refresh_token_expires_at=expires_at
        )
    )
    await self.db.commit()

    logger.info(f"Refresh token created for user {user_id}")
    return refresh_token, expires_at


async def verify_email_code(self, email: str, code: str, redis_client) -> tuple[User, str, datetime]:
    """
    验证邮箱验证码并登录

    Args:
        email: 邮箱地址
        code: 验证码
        redis_client: Redis 客户端

    Returns:
        (用户对象, refresh_token, expires_at)

    Raises:
        AuthError: 如果验证失败
    """
    # 从 Redis 获取验证码
    verification_key = f"email_verification:{email}"
    stored_code = await redis_client.get(verification_key)

    if not stored_code:
        raise AuthError("Verification code expired or not found")

    if stored_code.decode() != code:
        raise AuthError("Invalid verification code")

    # 验证成功，删除验证码
    await redis_client.delete(verification_key)

    # 查找或创建用户
    result = await self.db.execute(
        select(User).where(User.email == email)
    )
    user = result.scalar_one_or_none()

    if not user:
        # 创建新用户
        user_data = UserCreate(
            email=email,
            username=email.split("@")[0],
            auth_provider="email",
            provider_id=None,
            avatar_url=None
        )

        new_user = User(**user_data.model_dump())
        self.db.add(new_user)
        await self.db.commit()
        await self.db.refresh(new_user)

        logger.info(f"Created new user: {new_user.id}")
        user = new_user

    # 创建 Refresh Token
    refresh_token, expires_at = await self.create_refresh_token(str(user.id))

    logger.info(f"User {user.id} logged in via email verification")
    return user, refresh_token, expires_at


async def refresh_access_token(self, refresh_token: str) -> tuple[str, datetime, User]:
    """
    使用 Refresh Token 刷新 Access Token

    Args:
        refresh_token: Refresh Token

    Returns:
        (access_token, expires_at, user)

    Raises:
        AuthError: 如果刷新失败
    """
    # 查找用户
    result = await self.db.execute(
        select(User).where(User.refresh_token == refresh_token)
    )
    user = result.scalar_one_or_none()

    if not user:
        raise AuthError("Invalid refresh token")

    # 检查 Refresh Token 是否过期
    if user.refresh_token_expires_at and user.refresh_token_expires_at < datetime.utcnow():
        raise AuthError("Refresh token expired")

    # 创建新的 Access Token
    access_token = await self.create_access_token(str(user.id))
    expires_at = datetime.utcnow() + timedelta(days=7)

    logger.info(f"Access token refreshed for user {user.id}")
    return access_token, expires_at, user
```

### Step 4: 修改认证路由

**文件：`src/backend/app/routers/auth.py`**

添加发送验证码、验证邮箱和刷新 Token 接口：

```python
# 在 router 中添加以下接口

@router.post("/send-verification-code", status_code=status.HTTP_200_OK)
async def send_verification_code(
    request: SendVerificationCodeRequest,
    auth_service: Annotated[AuthService, Depends(get_auth_service)]
):
    """
    发送验证码到邮箱

    Args:
        request: 发送验证码请求（email）
        auth_service: 认证服务实例

    Returns:
        成功响应

    Raises:
        HTTPException: 如果发送失败

    示例：
        ```bash
        curl -X POST "http://localhost:8000/api/v1/auth/send-verification-code" \
          -H "Content-Type: application/json" \
          -d '{"email": "user@example.com"}'
        ```

    注意：
        - 同一邮箱 1 分钟内只能发送一次
        - 验证码有效期为 5 分钟
    """
    try:
        # 获取 Redis 客户端
        from app.database.redis import get_redis
        redis_client = await get_redis()

        # 发送验证码
        await auth_service.send_verification_code(request.email, redis_client)

        return {
            "message": "Verification code sent successfully",
            "expires_in": 300  # 5分钟
        }

    except AuthError as e:
        logger.warning(f"Failed to send verification code: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred"
        )


@router.post("/verify-email", response_model=LoginResponse, status_code=status.HTTP_200_OK)
async def verify_email(
    request: VerifyEmailRequest,
    auth_service: Annotated[AuthService, Depends(get_auth_service)]
):
    """
    验证邮箱验证码并登录

    Args:
        request: 验证邮箱请求（email, code）
        auth_service: 认证服务实例

    Returns:
        登录响应（access_token, refresh_token, token_type, expires_in, user）

    Raises:
        HTTPException: 如果验证失败

    示例：
        ```bash
        curl -X POST "http://localhost:8000/api/v1/auth/verify-email" \
          -H "Content-Type: application/json" \
          -d '{"email": "user@example.com", "code": "123456"}'
        ```

    注意：
        - 验证码有效期为 5 分钟
        - 验证码使用后立即失效
        - Access Token 有效期为 7 天
        - Refresh Token 有效期为 30 天
    """
    try:
        # 获取 Redis 客户端
        from app.database.redis import get_redis
        redis_client = await get_redis()

        # 验证邮箱
        user, refresh_token, expires_at = await auth_service.verify_email_code(request.email, request.code, redis_client)

        # 创建 Access Token
        access_token = await auth_service.create_access_token(str(user.id))

        # 返回登录响应
        return LoginResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            token_type="bearer",
            expires_in=604800,  # 7天，单位：秒
            user=UserResponse.model_validate(user)
        )

    except AuthError as e:
        logger.warning(f"Failed to verify email: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred"
        )


@router.post("/refresh", response_model=RefreshTokenResponse, status_code=status.HTTP_200_OK)
async def refresh_token(
    request: RefreshTokenRequest,
    auth_service: Annotated[AuthService, Depends(get_auth_service)]
):
    """
    使用 Refresh Token 刷新 Access Token

    Args:
        request: 刷新 Token 请求（refresh_token）
        auth_service: 认证服务实例

    Returns:
        刷新响应（access_token, token_type, expires_in）

    Raises:
        HTTPException: 如果刷新失败

    示例：
        ```bash
        curl -X POST "http://localhost:8000/api/v1/auth/refresh" \
          -H "Content-Type: application/json" \
          -d '{"refresh_token": "refresh_token_string"}'
        ```

    注意：
        - Refresh Token 有效期为 30 天
        - Refresh Token 过期后需要重新发送验证码
    """
    try:
        # 刷新 Access Token
        access_token, expires_at, user = await auth_service.refresh_access_token(request.refresh_token)

        # 返回刷新响应
        return RefreshTokenResponse(
            access_token=access_token,
            token_type="bearer",
            expires_in=604800  # 7天，单位：秒
        )

    except AuthError as e:
        logger.warning(f"Failed to refresh token: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred"
        )
```

在 `schemas.py` 中添加请求和响应模型：

```python
class SendVerificationCodeRequest(BaseModel):
    """发送验证码请求"""
    email: EmailStr


class VerifyEmailRequest(BaseModel):
    """验证邮箱请求"""
    email: EmailStr
    code: str = Field(..., min_length=6, max_length=6)


class RefreshTokenRequest(BaseModel):
    """刷新 Token 请求"""
    refresh_token: str


class RefreshTokenResponse(BaseModel):
    """刷新 Token 响应"""
    access_token: str
    token_type: str = "bearer"
    expires_in: int  # Access Token 过期时间（秒）


class LoginResponse(BaseModel):
    """登录响应"""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # Access Token 过期时间（秒）
    user: UserResponse
```

### Step 5: 修改任务模型

**文件：`src/backend/app/models/task.py`**

添加 `image_expires_at` 字段：

```python
# 在 Task 类中添加以下字段

# 生成结果
image_url: Mapped[str | None] = mapped_column(String(500))
image_expires_at: Mapped[datetime | None] = mapped_column(  # 新增
    TIMESTAMP(timezone=True),
    index=True
)
error_message: Mapped[str | None] = mapped_column(Text)
```

### Step 6: 修改任务服务

**文件：`src/backend/app/services/task_service.py`**

修改 `_process_task` 方法，在任务完成时设置图片过期时间：

```python
# 在 _process_task 方法中，保存图片后添加以下代码

# 保存图片到本地存储
try:
    image_url = await self._save_image(task_id, image_data)
    logger.info(f"Image saved for task {task_id}: {image_url}")
except Exception as e:
    logger.error(f"Failed to save image for task {task_id}: {str(e)}")
    raise TaskServiceError(f"Failed to save image: {str(e)}")

# 设置图片过期时间（7天后）
from datetime import datetime, timedelta
image_expires_at = datetime.utcnow() + timedelta(days=7)

# 更新任务状态为完成
await self._update_task_status(
    task_id,
    "completed",
    image_url=image_url,
    image_expires_at=image_expires_at  # 新增参数
)
```

修改 `_update_task_status` 方法，支持 `image_expires_at` 参数：

```python
async def _update_task_status(
    self,
    task_id: str,
    status: str,
    image_url: Optional[str] = None,
    image_expires_at: Optional[datetime] = None,  # 新增参数
    error_message: Optional[str] = None
):
    """
    更新任务状态

    Args:
        task_id: 任务 ID
        status: 新状态（pending/processing/completed/failed）
        image_url: 图片 URL（可选）
        image_expires_at: 图片过期时间（可选）
        error_message: 错误信息（可选）

    Raises:
        TaskServiceError: 如果更新失败
    """
    try:
        update_data: Dict[str, Any] = {"status": status}

        if image_url:
            update_data["image_url"] = image_url

        if image_expires_at:
            update_data["image_expires_at"] = image_expires_at

        if error_message:
            update_data["error_message"] = error_message

        await self.db.execute(
            update(Task).where(Task.id == task_id).values(**update_data)
        )
        await self.db.commit()

        logger.debug(f"Task {task_id} status updated to {status}")

    except Exception as e:
        logger.error(f"Failed to update task status: {str(e)}")
        await self.db.rollback()
        raise TaskServiceError(f"Failed to update task status: {str(e)}")
```

### Step 7: 创建清理服务

**文件：`src/backend/app/services/cleanup_service.py`**

创建清理服务类，提供定期清理过期图片功能：

```python
"""
清理服务模块

提供定期清理过期图片和任务的功能。
使用 APScheduler 定期执行清理任务。
"""

import asyncio
from typing import Optional
from datetime import datetime, timedelta
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete
import logging

from app.models.task import Task
from app.storage.image_storage import ImageStorage

logger = logging.getLogger(__name__)


class CleanupService:
    """
    清理服务类

    提供定期清理过期图片和任务的功能。
    使用 APScheduler 定期执行清理任务。

    使用方法：
        # 初始化服务
        cleanup_service = CleanupService(db=db_session, storage=image_storage)

        # 执行清理
        await cleanup_service.cleanup_expired_images()
    """

    def __init__(
        self,
        db: AsyncSession,
        storage: Optional[ImageStorage] = None,
        retention_days: int = 7
    ):
        """
        初始化清理服务

        Args:
            db: 异步数据库会话
            storage: 图片存储服务实例（可选）
            retention_days: 图片保留天数（默认 7 天）
        """
        self.db = db
        self.storage = storage or ImageStorage()
        self.retention_days = retention_days

        logger.info(f"CleanupService initialized with retention_days={retention_days}")

    async def cleanup_expired_images(self) -> int:
        """
        清理过期的图片

        Returns:
            删除的图片数量

        注意：
            - 清理超过 retention_days 天的图片
            - 只清理已完成或失败的任务图片
            - 同时删除图片文件和数据库记录
        """
        deleted_count = 0
        cutoff_time = datetime.utcnow() - timedelta(days=self.retention_days)

        logger.info(f"Starting cleanup of images older than {cutoff_time}")

        try:
            # 查询过期任务
            result = await self.db.execute(
                select(Task).where(
                    Task.image_expires_at < cutoff_time,
                    Task.status.in_(["completed", "failed"]),
                    Task.image_url.isnot(None)
                )
            )
            tasks = result.scalars().all()

            logger.info(f"Found {len(tasks)} expired images to clean up")

            for task in tasks:
                try:
                    # 删除图片文件
                    if task.image_url:
                        success = await self.storage.delete_image(task.image_url)
                        if success:
                            logger.info(f"Deleted image for task {task.id}: {task.image_url}")
                        else:
                            logger.warning(f"Failed to delete image: {task.image_url}")

                    # 删除任务记录（可选，也可以只清空 image_url）
                    await self.db.execute(
                        delete(Task).where(Task.id == task.id)
                    )

                    deleted_count += 1

                except Exception as e:
                    logger.error(f"Failed to cleanup task {task.id}: {str(e)}")
                    continue

            await self.db.commit()
            logger.info(f"Cleanup completed: {deleted_count} images deleted")
            return deleted_count

        except Exception as e:
            logger.error(f"Failed to cleanup expired images: {str(e)}")
            await self.db.rollback()
            raise Exception(f"Failed to cleanup expired images: {str(e)}")


def start_cleanup_scheduler(cleanup_service: CleanupService):
    """
    启动清理调度器

    Args:
        cleanup_service: 清理服务实例

    注意：
        - 每天凌晨 3 点执行清理任务
        - 使用 APScheduler 进行任务调度
    """
    from apscheduler.schedulers.asyncio import AsyncIOScheduler

    scheduler = AsyncIOScheduler()

    # 每天凌晨 3 点执行清理任务
    scheduler.add_job(
        cleanup_service.cleanup_expired_images,
        'cron',
        hour=3,
        minute=0,
        id='cleanup_expired_images'
    )

    scheduler.start()
    logger.info("Cleanup scheduler started, job will run at 3:00 AM daily")
```

### Step 8: 修改主应用

**文件：`src/backend/app/main.py`**

在应用启动时启动清理调度器：

```python
# 在 lifespan 函数中添加以下代码

@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理"""
    logger.info("Starting MindCanvas Backend...")

    # 启动清理调度器
    from app.services.cleanup_service import CleanupService
    from app.storage.image_storage import ImageStorage

    # 创建清理服务
    cleanup_service = CleanupService(
        db=None,  # 需要在实际使用时注入
        storage=ImageStorage(),
        retention_days=settings.IMAGE_RETENTION_DAYS
    )

    # 启动调度器（需要注入数据库会话）
    # start_cleanup_scheduler(cleanup_service)

    yield
    logger.info("Shutting down MindCanvas Backend...")
```

### Step 9: 创建 Redis 连接

**文件：`src/backend/app/database/redis.py`**

创建 Redis 连接模块：

```python
"""
Redis 连接模块

提供 Redis 客户端连接和初始化功能。
"""

import redis.asyncio as redis
from typing import Optional
import logging

logger = logging.getLogger(__name__)

_redis_client: Optional[redis.Redis] = None


async def get_redis() -> redis.Redis:
    """
    获取 Redis 客户端实例

    Returns:
        Redis 客户端实例

    注意：
        - 使用单例模式
        - 连接池自动管理
    """
    global _redis_client

    if _redis_client is None:
        from app.config import settings

        _redis_client = redis.from_url(
            settings.REDIS_URL,
            encoding="utf-8",
            decode_responses=True
        )

        logger.info(f"Redis client initialized: {settings.REDIS_URL}")

    return _redis_client


async def close_redis():
    """关闭 Redis 连接"""
    global _redis_client

    if _redis_client:
        await _redis_client.close()
        _redis_client = None
        logger.info("Redis client closed")
```

### Step 10: 更新配置

**文件：`src/backend/app/config.py`**

添加邮件服务配置：

```python
# 在 Settings 类中添加以下配置

# 邮件服务配置
SMTP_HOST: str = "smtp.gmail.com"
SMTP_PORT: int = 587
SMTP_USERNAME: str = ""
SMTP_PASSWORD: str = ""
SMTP_USE_TLS: bool = True

# Redis 配置
REDIS_URL: str = "redis://localhost:6379/0"

# 图片保留天数
IMAGE_RETENTION_DAYS: int = 7
```

### Step 11: 数据库迁移

**文件：`src/backend/migrations/002_add_refresh_token.sql`**

创建数据库迁移脚本（添加 Refresh Token 支持）：

```sql
-- 添加 Refresh Token 字段到 users 表
ALTER TABLE users ADD COLUMN IF NOT EXISTS refresh_token VARCHAR(500);
ALTER TABLE users ADD COLUMN IF NOT EXISTS refresh_token_expires_at TIMESTAMP WITH TIME ZONE;

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_users_refresh_token ON users(refresh_token);

-- 添加注释
COMMENT ON COLUMN users.refresh_token IS '刷新令牌（30天有效期）';
COMMENT ON COLUMN users.refresh_token_expires_at IS '刷新令牌过期时间';
```

执行迁移：
```bash
psql -U mindcanvas -d mindcanvas -f migrations/002_add_refresh_token.sql
```

**文件：`src/backend/migrations/003_add_image_expires_at.sql`**

创建数据库迁移脚本（添加图片过期时间）：

```sql
-- 添加图片过期时间字段
ALTER TABLE generation_tasks ADD COLUMN IF NOT EXISTS image_expires_at TIMESTAMP WITH TIME ZONE;

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_generation_tasks_image_expires_at ON generation_tasks(image_expires_at);

-- 添加注释
COMMENT ON COLUMN generation_tasks.image_expires_at IS '图片过期时间（7天后自动清理）';
```

执行迁移：
```bash
psql -U mindcanvas -d mindcanvas -f migrations/003_add_image_expires_at.sql
```

### Step 12: 更新环境变量

**文件：`src/backend/.env`**

添加以下环境变量：

```bash
# 邮件服务配置
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your_email@gmail.com
SMTP_PASSWORD=your_app_password
SMTP_USE_TLS=true

# Redis 配置
REDIS_URL=redis://localhost:6379/0

# 图片保留天数
IMAGE_RETENTION_DAYS=7
```

### Step 13: 更新 Docker Compose

**文件：`src/backend/docker-compose.yml`**

添加 Redis 服务：

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    container_name: mindcanvas_postgres
    environment:
      POSTGRES_DB: mindcanvas
      POSTGRES_USER: mindcanvas
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    container_name: mindcanvas_redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  backend:
    build: .
    container_name: mindcanvas_backend
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql+asyncpg://mindcanvas:${POSTGRES_PASSWORD}@postgres:5432/mindcanvas
      REDIS_URL: redis://redis:6379/0
      SMTP_HOST: ${SMTP_HOST}
      SMTP_PORT: ${SMTP_PORT}
      SMTP_USERNAME: ${SMTP_USERNAME}
      SMTP_PASSWORD: ${SMTP_PASSWORD}
      SMTP_USE_TLS: ${SMTP_USE_TLS}
      IMAGE_RETENTION_DAYS: ${IMAGE_RETENTION_DAYS}
    depends_on:
      - postgres
      - redis
    volumes:
      - ./storage:/app/storage

volumes:
  postgres_data:
  redis_data:
```

---

## 4. 技术选型

| 技术 | 用途 | 版本 |
|------|------|------|
| FastAPI | Web 框架 | 0.104.1 |
| SQLAlchemy | ORM | 2.0.36+ |
| asyncpg | PostgreSQL 异步驱动 | 0.29.0 |
| Redis | 验证码存储 | 5.0.1 |
| aiosmtplib | 异步 SMTP 客户端 | 3.0.1 |
| apscheduler | 异步任务调度 | 3.10.4 |
| python-jose | JWT | 3.3.0 |
| cryptography | 加密 | 41.0.7 |
| httpx | HTTP 客户端 | 0.25.2 |

---

## 5. 注意事项

### 5.1 邮件发送注意事项

1. **邮件服务配置**
   - 使用 Gmail 需要启用"应用专用密码"
   - 使用企业邮箱需要配置正确的 SMTP 服务器
   - 建议使用第三方邮件服务（如 SendGrid、阿里云邮件推送）

2. **发送频率限制**
   - 同一邮箱 1 分钟内只能发送一次验证码
   - 使用 Redis 存储发送记录
   - 超过限制时返回友好的错误信息

3. **验证码安全**
   - 验证码使用 6 位数字
   - 验证码 5 分钟过期
   - 验证码使用后立即失效
   - 不在日志中记录验证码

### 5.2 API Key 安全注意事项

1. **加密存储**
   - 客户端使用 RSA 公钥加密
   - 服务端使用 Fernet 对称加密
   - 任务完成后立即删除 API Key

2. **密钥管理**
   - 加密密钥从环境变量获取
   - 不在代码中硬编码密钥
   - 定期轮换密钥

3. **日志安全**
   - 不在日志中记录 API Key
   - 不在日志中记录加密后的 API Key
   - 使用日志脱敏

### 5.3 图片清理注意事项

1. **清理策略**
   - 每天凌晨 3 点执行清理任务
   - 只清理已完成或失败的任务图片
   - 清理前检查图片是否真的过期

2. **错误处理**
   - 清理失败时记录日志
   - 不影响主业务流程
   - 支持手动重试

3. **数据备份**
   - 清理前可以备份重要数据（可选）
   - 使用软删除而非硬删除（可选）

### 5.4 性能优化注意事项

1. **异步 IO**
   - 使用异步 IO 提高性能
   - 避免阻塞操作
   - 使用连接池

2. **缓存优化**
   - 使用 Redis 缓存验证码
   - 使用 Redis 缓存点赞数
   - 定期清理过期缓存

3. **批量操作**
   - 图片清理使用批量操作
   - 避免频繁的数据库查询
   - 使用事务保证数据一致性

### 5.5 错误处理注意事项

1. **友好错误信息**
   - 返回用户友好的错误信息
   - 不暴露系统内部错误
   - 记录详细的错误日志

2. **重试机制**
   - 邮件发送失败时重试
   - API 调用失败时重试
   - 设置合理的重试次数

3. **监控告警**
   - 监控清理任务执行情况
   - 监控邮件发送成功率
   - 监控 API 调用成功率

---

## 6. 成功标准

- [ ] 邮箱验证登录功能完整可用
- [ ] 验证码能够正确发送到用户邮箱
- [ ] 验证码验证逻辑正确
- [ ] Access Token 有效期为 7 天
- [ ] Refresh Token 有效期为 30 天
- [ ] Access Token 过期后可以使用 Refresh Token 自动刷新
- [ ] Refresh Token 过期后需要重新发送验证码
- [ ] 生图服务支持异步轮询
- [ ] API Key 加密存储，任务完成后立即删除
- [ ] 图片能够自动清理（7天后）
- [ ] 清理任务能够定期执行（每天凌晨 3 点）
- [ ] 所有接口经过测试，功能正常
- [ ] 错误处理完善，日志记录完整

---

## 7. 关键文件清单

| 文件路径 | 修改内容 |
|----------|----------|
| `src/backend/requirements.txt` | 添加 aiosmtplib、apscheduler、redis |
| `src/backend/app/services/email_service.py` | 新增邮件服务 |
| `src/backend/app/services/auth_service.py` | 添加邮箱验证登录、Refresh Token 逻辑 |
| `src/backend/app/routers/auth.py` | 添加发送验证码、验证邮箱、刷新 Token 接口 |
| `src/backend/app/models/task.py` | 添加 image_expires_at 字段 |
| `src/backend/app/services/task_service.py` | 修改任务处理逻辑 |
| `src/backend/app/services/cleanup_service.py` | 新增清理服务 |
| `src/backend/app/database/redis.py` | 新增 Redis 连接 |
| `src/backend/app/config.py` | 添加邮件服务配置 |
| `src/backend/app/models/schemas.py` | 添加请求和响应模型（RefreshTokenRequest, RefreshTokenResponse, LoginResponse） |
| `src/backend/migrations/002_add_refresh_token.sql` | 数据库迁移脚本（添加 Refresh Token） |
| `src/backend/migrations/003_add_image_expires_at.sql` | 数据库迁移脚本（添加图片过期时间） |
| `src/backend/.env` | 添加环境变量 |
| `src/backend/docker-compose.yml` | 添加 Redis 服务 |

---

## 8. 总结

本方案从第一性原理出发，重新设计了 MindCanvas 后端的邮箱验证登录和图片生命周期管理功能。方案的核心特点：

1. **邮箱验证登录**：使用 Redis 存储验证码，异步发送邮件，支持频率限制和过期时间管理
2. **Refresh Token 机制**：Access Token（7天）+ Refresh Token（30天），提升用户体验，减少验证码发送频率
3. **Token 刷新流程**：Access Token 过期后自动刷新，Refresh Token 过期后需要重新验证
4. **生图服务**：保持现有设计，添加图片过期时间字段
5. **图片生命周期管理**：使用 APScheduler 定期清理过期图片，每天凌晨 3 点执行
6. **API Key 安全**：双重加密（RSA + Fernet），任务完成后立即删除
7. **技术选型**：使用成熟的技术栈，确保稳定性和可维护性

执行人员可以按照本方案的步骤逐步实施，确保每个步骤都经过测试验证，最终实现完整的邮箱验证登录、Refresh Token 机制和图片生命周期管理功能。