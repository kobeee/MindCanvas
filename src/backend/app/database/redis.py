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