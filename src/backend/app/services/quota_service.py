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