"""
认证路由模块

提供用户认证相关的 API 接口。

功能特性：
- 第三方登录（Apple、Google、GitHub、邮箱）
- 获取当前用户信息
- JWT Token 验证

API 接口：
- POST /api/v1/auth/login - 用户登录
- GET /api/v1/auth/me - 获取当前用户信息
"""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
import logging

from app.database.connection import get_db
from app.models.schemas import (
    LoginRequest,
    LoginResponse,
    UserResponse,
    SendVerificationCodeRequest,
    VerifyEmailRequest,
    RefreshTokenRequest,
    RefreshTokenResponse
)
from app.services.auth_service import AuthService, AuthError, InvalidTokenError, UserNotFoundError


logger = logging.getLogger(__name__)

# 创建路由器
router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])

# HTTP Bearer 认证（配置为返回 401 而非 403）
security = HTTPBearer(auto_error=False)


async def get_auth_service(
    db: Annotated[AsyncSession, Depends(get_db)]
) -> AuthService:
    """
    依赖注入：获取 AuthService 实例

    Args:
        db: 数据库会话

    Returns:
        AuthService 实例
    """
    return AuthService(db)


async def get_current_user_from_token(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
    auth_service: Annotated[AuthService, Depends(get_auth_service)]
) -> UserResponse:
    """
    依赖注入：从 JWT Token 获取当前用户

    Args:
        credentials: HTTP Bearer 认证凭证
        auth_service: 认证服务实例

    Returns:
        当前用户信息

    Raises:
        HTTPException: 如果 Token 无效或用户不存在
    """
    # 如果没有提供凭证，返回 401
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        token = credentials.credentials
        user = await auth_service.get_current_user(token)
        return UserResponse.model_validate(user)
    except InvalidTokenError as e:
        logger.warning(f"Invalid token: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    except UserNotFoundError as e:
        logger.warning(f"User not found: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    except Exception as e:
        logger.error(f"Failed to get current user: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to authenticate user",
        )


@router.post("/login", response_model=LoginResponse, status_code=status.HTTP_200_OK)
async def login(
    request: LoginRequest,
    auth_service: Annotated[AuthService, Depends(get_auth_service)]
):
    """
    用户登录

    支持多种登录方式：
    - Apple: 使用 Apple Identity Token
    - Google: 使用 Google ID Token
    - GitHub: 使用 GitHub Access Token
    - Email: 使用邮箱验证码（Mock 实现）

    Args:
        request: 登录请求（provider, token）
        auth_service: 认证服务实例

    Returns:
        登录响应（access_token, token_type, user）

    Raises:
        HTTPException: 如果登录失败

    示例：
        ```bash
        curl -X POST "http://localhost:8000/api/v1/auth/login" \
          -H "Content-Type: application/json" \
          -d '{
            "provider": "apple",
            "token": "identity_token_string"
          }'
        ```

    注意：
        - 当前实现为 Mock，实际需要调用各平台的验证接口
        - 返回的 access_token 需要在后续请求中通过 Authorization header 传递
    """
    # 验证 provider 参数
    valid_providers = ["apple", "google", "github", "email"]
    if request.provider not in valid_providers:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid provider. Must be one of: {', '.join(valid_providers)}"
        )

    try:
        # 调用认证服务进行登录
        result = await auth_service.login_with_provider(request.provider, request.token)

        # 返回登录响应
        return LoginResponse(
            access_token=result["access_token"],
            refresh_token=result["refresh_token"],
            token_type=result["token_type"],
            expires_in=result["expires_in"],
            user=UserResponse.model_validate(result["user"])
        )

    except AuthError as e:
        logger.warning(f"Login failed: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
            headers={"WWW-Authenticate": "Bearer"},
        )
    except Exception as e:
        logger.error(f"Unexpected error during login: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred during login",
        )


@router.get("/me", response_model=UserResponse, status_code=status.HTTP_200_OK)
async def get_current_user(
    current_user: Annotated[UserResponse, Depends(get_current_user_from_token)]
):
    """
    获取当前用户信息

    需要在请求头中提供有效的 JWT Token：
    ```
    Authorization: Bearer <access_token>
    ```

    Args:
        current_user: 当前用户信息（从 Token 解析）

    Returns:
        当前用户信息

    Raises:
        HTTPException: 如果 Token 无效或用户不存在

    示例：
        ```bash
        curl -X GET "http://localhost:8000/api/v1/auth/me" \
          -H "Authorization: Bearer <access_token>"
        ```

    注意：
        - 需要先调用 /login 接口获取 access_token
        - access_token 有效期为 7 天（可配置）
    """
    return current_user


@router.post("/logout", status_code=status.HTTP_200_OK)
async def logout(
    current_user: Annotated[UserResponse, Depends(get_current_user_from_token)]
):
    """
    用户登出

    注意：
        - JWT Token 是无状态的，服务端无法主动撤销 Token
        - 客户端应删除本地存储的 Token
        - 实际生产环境可能需要实现 Token 黑名单机制

    Args:
        current_user: 当前用户信息

    Returns:
        成功消息

    示例：
        ```bash
        curl -X POST "http://localhost:8000/api/v1/auth/logout" \
          -H "Authorization: Bearer <access_token>"
        ```
    """
    # JWT Token 是无状态的，服务端无法主动撤销 Token
    # 客户端应删除本地存储的 Token
    logger.info(f"User {current_user.id} logged out")

    return {"message": "Logged out successfully"}


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