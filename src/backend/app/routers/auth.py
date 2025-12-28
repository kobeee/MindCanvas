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
from app.models.schemas import LoginRequest, LoginResponse, UserResponse
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
            token_type=result["token_type"],
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