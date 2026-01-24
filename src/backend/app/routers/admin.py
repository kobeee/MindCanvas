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
    1. 允许重复注入邮箱配额
    2. 如果邮箱已存在，新的配额将累加到现有配额上
    3. 如果邮箱不存在，则创建新记录

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
            text("SELECT initial_quota FROM email_quota_configs WHERE email = :email"),
            {"email": request.email}
        )
        existing = result.fetchone()

        if existing:
            # 邮箱已存在，累加配额
            new_quota = existing[0] + request.quota
            await db.execute(
                text("""
                    UPDATE email_quota_configs
                    SET initial_quota = :new_quota
                    WHERE email = :email
                """),
                {"email": request.email, "new_quota": new_quota}
            )
            logger.info(f"Email quota updated: {request.email}, old_quota={existing[0]}, added={request.quota}, new_quota={new_quota}")
        else:
            # 邮箱不存在，创建新记录
            await db.execute(
                text("""
                    INSERT INTO email_quota_configs (email, initial_quota)
                    VALUES (:email, :quota)
                """),
                {"email": request.email, "quota": request.quota}
            )
            logger.info(f"Email quota injected: {request.email}, quota={request.quota}")

        await db.commit()

        return {
            "success": True,
            "message": "Email quota injected successfully"
        }

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


@router.get("/email-quota/{email}", status_code=status.HTTP_200_OK)
async def get_email_quota(
    email: str,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: None = Depends(verify_admin)
):
    """
    查询指定邮箱的配额信息

    Args:
        email: 邮箱地址
        db: 数据库会话

    Returns:
        邮箱配额信息

    Raises:
        HTTPException: 如果查询失败
    """
    try:
        # 查询邮箱配额配置
        quota_result = await db.execute(
            text("SELECT initial_quota, created_at FROM email_quota_configs WHERE email = :email"),
            {"email": email}
        )
        quota_row = quota_result.fetchone()

        if not quota_row:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Email quota not found"
            )

        initial_quota = quota_row[0]
        created_at = quota_row[1]

        # 查询用户的使用情况
        user_result = await db.execute(
            text("SELECT id, total_quota_used FROM users WHERE email = :email"),
            {"email": email}
        )
        user_row = user_result.fetchone()

        used_quota = user_row[1] if user_row else 0
        remaining_quota = initial_quota - used_quota

        return {
            "email": email,
            "initial_quota": initial_quota,
            "used_quota": used_quota,
            "remaining_quota": remaining_quota,
            "created_at": created_at.isoformat() if created_at else None
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to get email quota for {email}: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get email quota"
        )


class EmailQuotaReduceRequest(BaseModel):
    """邮箱配额减少请求"""
    email: str = Field(..., description="邮箱地址")
    amount: int = Field(..., gt=0, description="减少的配额数量")


@router.post("/email-quota/reduce", status_code=status.HTTP_200_OK)
async def reduce_email_quota(
    request: EmailQuotaReduceRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    _: None = Depends(verify_admin)
):
    """
    减少指定邮箱的初始配额

    规则：
    1. 减少的是初始配额（initial_quota）
    2. 减少后的初始配额不能小于 0
    3. 减少后的初始配额不能小于已使用配额（total_quota_used）

    Args:
        request: 邮箱配额减少请求
        db: 数据库会话

    Returns:
        成功响应

    Raises:
        HTTPException: 如果减少失败
    """
    try:
        # 查询邮箱的初始配额
        quota_result = await db.execute(
            text("SELECT initial_quota FROM email_quota_configs WHERE email = :email"),
            {"email": request.email}
        )
        quota_row = quota_result.fetchone()

        if not quota_row:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Email quota not found"
            )

        current_initial = quota_row[0]

        # 查询用户已使用的配额
        user_result = await db.execute(
            text("SELECT total_quota_used FROM users WHERE email = :email"),
            {"email": request.email}
        )
        user_row = user_result.fetchone()

        used_quota = user_row[0] if user_row else 0

        # 检查减少后的初始配额是否合法
        new_initial = current_initial - request.amount
        if new_initial < 0:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot reduce quota: current initial quota is {current_initial}, cannot reduce by {request.amount}"
            )

        if new_initial < used_quota:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot reduce quota: used quota is {used_quota}, cannot reduce initial quota below used quota"
            )

        # 更新初始配额
        await db.execute(
            text("""
                UPDATE email_quota_configs
                SET initial_quota = :new_initial
                WHERE email = :email
            """),
            {"email": request.email, "new_initial": new_initial}
        )
        await db.commit()

        logger.info(f"Email quota reduced: {request.email}, reduced_by={request.amount}, old_initial={current_initial}, new_initial={new_initial}")

        return {
            "success": True,
            "message": "Email quota reduced successfully",
            "old_initial": current_initial,
            "reduced_by": request.amount,
            "new_initial": new_initial,
            "used_quota": used_quota,
            "remaining_quota": new_initial - used_quota
        }

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Failed to reduce email quota for {request.email}: {str(e)}")
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to reduce email quota"
        )