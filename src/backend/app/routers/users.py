"""
用户相关 API 接口

提供用户信息管理、API Key 配置等功能。
"""

from typing import Annotated, Optional
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
import logging

from app.database.connection import get_db
from app.models.schemas import SuccessResponse
from app.services.auth_service import AuthService, InvalidTokenError, UserNotFoundError
from app.services.rsa_encryption_service import load_public_key_from_base64, RSAEncryptionError
from app.config import settings
from app.models.user import User

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/v1/users", tags=["Users"])

security = HTTPBearer()


async def get_auth_service(
    db: Annotated[AsyncSession, Depends(get_db)]
) -> AuthService:
    return AuthService(db)


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth_service: Annotated[AuthService, Depends(get_auth_service)]
) -> User:
    try:
        token = credentials.credentials
        user = await auth_service.get_current_user(token)
        return user
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


class PublicKeyUpdate(BaseModel):
    """更新公钥请求"""
    public_key: str = Field(..., description="Base64 编码的 RSA 公钥")


class PublicKeyResponse(BaseModel):
    """公钥响应"""
    has_public_key: bool
    public_key: Optional[str] = None


@router.get("/public-key", response_model=PublicKeyResponse)
async def get_public_key():
    """
    获取后端 RSA 公钥

    iOS 端调用此接口获取后端的 RSA 公钥，用于加密 API Key。

    Returns:
        包含 has_public_key 和 public_key 的响应

    注意：
        - 此接口不需要认证
        - 公钥通过配置提供，不存储在数据库中
        - public_key 是 PEM 格式的公钥的 Base64 编码
    """
    # 从配置获取公钥的 Base64 编码
    public_key_base64 = getattr(settings, "RSA_PUBLIC_KEY_BASE64", None)
    
    return PublicKeyResponse(
        has_public_key=bool(public_key_base64),
        public_key=public_key_base64
    )


@router.post("/public-key", response_model=SuccessResponse)
async def update_public_key(
    request: PublicKeyUpdate,
    current_user: Annotated[User, Depends(get_current_user)]
):
    """
    存储用户的 RSA 公钥

    iOS 端生成 RSA 密钥对后，调用此接口将公钥注册到后端。
    后端使用此公钥加密 API Key 后返回给 iOS 端。

    Args:
        request: 包含 Base64 编码的公钥
        current_user: 当前用户

    Returns:
        成功响应

    Raises:
        HTTPException: 如果公钥无效
    """
    try:
        # 验证公钥格式
        load_public_key_from_base64(request.public_key)
        logger.info(f"User {current_user.id} updated public key")
        
        # TODO: 存储公钥到用户表或单独的配置表
        # 目前先记录日志，后续实现存储逻辑
        
        return SuccessResponse(message="Public key updated successfully")
        
    except RSAEncryptionError as e:
        logger.warning(f"Invalid public key from user {current_user.id}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid public key format"
        )
    except Exception as e:
        logger.error(f"Failed to update public key: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update public key"
        )


@router.get("/me", response_model=dict)
async def get_current_user_info(
    current_user: Annotated[User, Depends(get_current_user)]
):
    """
    获取当前用户信息

    Returns:
        用户信息字典
    """
    return {
        "id": str(current_user.id),
        "email": current_user.email,
        "username": current_user.username,
        "avatar_url": current_user.avatar_url,
        "auth_provider": current_user.auth_provider
    }
