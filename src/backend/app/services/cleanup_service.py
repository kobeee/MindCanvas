"""
清理服务模块

提供定期清理过期图片和任务的功能。
使用 APScheduler 定期执行清理任务。
"""

import asyncio
from typing import Optional
from datetime import datetime, timedelta, timezone
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
        cutoff_time = datetime.now(timezone.utc) - timedelta(days=self.retention_days)

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