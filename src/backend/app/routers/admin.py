"""
管理员路由模块

提供邮箱配额注入和管理的 API 接口。
"""

from typing import Annotated
from fastapi import APIRouter, HTTPException, status, Header, Depends
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
import logging

from app.database.connection import get_db
from app.config import settings

logger = logging.getLogger(__name__)

# 创建路由器
router = APIRouter(prefix="/api/v1/admin", tags=["Admin"])


class EmailQuotaInjectRequest(BaseModel):
    """邮箱配额注入请求"""
    email: str = Field(..., description="邮箱地址")
    quota: int = Field(..., gt=0, description="配额数量")


async def verify_admin(admin_secret: str = Header(...)) -> None:
    """验证管理员密钥"""
    if admin_secret != settings.ADMIN_SECRET_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid admin secret key"
        )


@router.post("/email-quota", status_code=status.HTTP_201_CREATED)
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

        return {
            "success": True,
            "message": "Email quota injected successfully"
        }

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


@router.delete("/email-quota", status_code=status.HTTP_200_OK)
async def delete_email_quota(
    email: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: None = Depends(verify_admin)
):
    """
    删除邮箱配额

    Args:
        email: 邮箱地址
        db: 数据库会话

    Returns:
        成功响应

    Raises:
        HTTPException: 如果删除失败
    """
    try:
        result = await db.execute(
            text("DELETE FROM email_quota_configs WHERE email = :email"),
            {"email": email}
        )
        await db.commit()

        if result.rowcount == 0:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Email quota not found"
            )

        logger.info(f"Email quota deleted: {email}")

        return {
            "success": True,
            "message": "Email quota deleted successfully"
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to delete email quota: {str(e)}")
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete email quota"
        )