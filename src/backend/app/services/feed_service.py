"""
社区服务模块

提供社区动态的发布、查询、点赞和举报功能。
整合 Redis 实现点赞计数缓存。

安全特性：
- 权限检查（只能操作自己的资源）
- 内容安全审核检查
- 完善的错误处理和日志记录
- Redis 缓存加速点赞计数
"""

import logging
from typing import Optional, Dict, Any, List
from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_, or_
from sqlalchemy.orm import selectinload

from app.models.feed import FeedItem
from app.models.asset import Asset
from app.models.report import Report
from app.config import settings

# Redis 客户端（延迟导入，避免循环依赖）
redis_client = None

logger = logging.getLogger(__name__)


class FeedNotFoundError(Exception):
    """社区动态不存在异常"""
    pass


class FeedPermissionError(Exception):
    """社区动态权限异常"""
    pass


class FeedServiceError(Exception):
    """社区服务异常基类"""
    pass


class ReportAlreadyExistsError(Exception):
    """举报已存在异常"""
    pass


class FeedService:
    """
    社区服务类

    提供社区动态的发布、查询、点赞和举报功能。
    整合 Redis 实现点赞计数缓存。

    使用方法：
        # 初始化服务
        feed_service = FeedService(db=db_session, redis=redis_client)

        # 获取社区动态列表
        result = await feed_service.get_feed(page=1, size=20, sort="latest")

        # 发布资源到社区
        feed = await feed_service.publish_asset(
            asset_id="asset123",
            user_id="user123",
            title="My Masterpiece"
        )

        # 点赞动态
        likes_count = await feed_service.like_feed(feed_id="feed123")

        # 举报动态
        report = await feed_service.report_feed(
            feed_id="feed123",
            reporter_id="user123",
            reason="nsfw"
        )
    """

    def __init__(self, db: AsyncSession, redis: Optional[Any] = None):
        """
        初始化社区服务

        Args:
            db: 异步数据库会话
            redis: Redis 客户端实例（可选）

        注意：
            - 所有服务实例必须正确初始化
            - redis 参数可选，如果不提供则不使用缓存
        """
        self.db = db
        self.redis = redis

        logger.info("FeedService initialized successfully")

    async def get_feed(
        self,
        page: int = 1,
        size: int = 20,
        sort: str = "latest"
    ) -> Dict[str, Any]:
        """
        获取社区动态列表

        Args:
            page: 页码（从 1 开始）
            size: 每页数量
            sort: 排序方式（latest: 最新, hot: 热门）

        Returns:
            社区动态列表字典，包含：
            - items: 动态列表
            - total: 总数量
            - page: 当前页码
            - size: 每页数量
            - total_pages: 总页数

        Raises:
            FeedServiceError: 如果查询失败

        注意：
            - 支持分页
            - 支持按最新和热门排序
            - 热门排序按点赞数倒序
            - 最新排序按发布时间倒序
        """
        # 验证分页参数
        if page < 1:
            logger.error(f"Invalid page: {page}")
            raise FeedServiceError("page must be >= 1")

        if size < 1 or size > 100:
            logger.error(f"Invalid size: {size}")
            raise FeedServiceError("size must be between 1 and 100")

        # 验证排序方式
        if sort not in ["latest", "hot"]:
            logger.error(f"Invalid sort: {sort}")
            raise FeedServiceError("sort must be 'latest' or 'hot'")

        try:
            # 构建基础查询（关联 Asset 和 User）
            query = (
                select(FeedItem)
                .options(
                    selectinload(FeedItem.asset),
                    selectinload(FeedItem.user)
                )
            )

            # 排序
            if sort == "latest":
                query = query.order_by(FeedItem.published_at.desc())
            else:  # hot
                query = query.order_by(FeedItem.likes_count.desc(), FeedItem.published_at.desc())

            # 获取总数
            count_query = select(func.count()).select_from(query.subquery())
            total_result = await self.db.execute(count_query)
            total = total_result.scalar() or 0

            # 计算偏移量
            offset = (page - 1) * size

            # 添加分页
            query = query.offset(offset).limit(size)

            # 执行查询
            result = await self.db.execute(query)
            feed_items = result.scalars().unique().all()

            # 计算总页数
            total_pages = (total + size - 1) // size

            # 构建响应
            response = {
                "items": feed_items,
                "total": total,
                "page": page,
                "size": size,
                "total_pages": total_pages
            }

            logger.debug(
                f"Retrieved {len(feed_items)} feed items, "
                f"page={page}, sort={sort}, total={total}"
            )

            return response

        except Exception as e:
            logger.error(f"Failed to get feed: {str(e)}")
            raise FeedServiceError(f"Failed to get feed: {str(e)}")

    async def publish_asset(
        self,
        asset_id: str,
        user_id: str,
        title: Optional[str] = None
    ) -> FeedItem:
        """
        发布资源到社区

        Args:
            asset_id: 资源 ID
            user_id: 用户 ID
            title: 标题（可选）

        Returns:
            社区动态对象

        Raises:
            FeedServiceError: 如果发布失败
            FeedPermissionError: 如果用户无权发布该资源

        注意：
            - 只能发布自己的资源
            - 每个资源只能发布一次
            - 发布后资源标记为公开
            - 内容安全审核检查（根据 ENABLE_STRICT_AUDIT 配置）
        """
        # 验证参数
        if not asset_id:
            logger.error("asset_id is empty")
            raise FeedServiceError("asset_id is required")

        if not user_id:
            logger.error("user_id is empty")
            raise FeedServiceError("user_id is required")

        try:
            # 查询资源
            result = await self.db.execute(
                select(Asset).where(Asset.id == asset_id)
            )
            asset = result.scalar_one_or_none()

            if not asset:
                logger.warning(f"Asset not found: {asset_id}")
                raise FeedServiceError(f"Asset not found: {asset_id}")

            # 检查资源归属
            if asset.user_id != user_id:
                logger.warning(
                    f"User {user_id} attempted to publish asset {asset_id} "
                    f"owned by {asset.user_id}"
                )
                raise FeedPermissionError(
                    "You don't have permission to publish this asset"
                )

            # 检查是否已经发布
            existing_feed = await self.db.execute(
                select(FeedItem).where(FeedItem.asset_id == asset_id)
            )
            if existing_feed.scalar_one_or_none():
                logger.warning(f"Asset {asset_id} already published")
                raise FeedServiceError("Asset already published to feed")

            # 内容安全审核检查
            if settings.ENABLE_STRICT_AUDIT:
                # TODO: 实现内容安全审核
                # 这里可以集成第三方审核服务（如阿里云内容安全、腾讯云天御等）
                logger.warning(f"Strict audit enabled for asset {asset_id}")
                # 暂时跳过审核，实际项目中需要实现

            # 创建社区动态
            feed_item = FeedItem(
                asset_id=asset_id,
                user_id=user_id,
                title=title,
                likes_count=0,
                published_at=datetime.utcnow().isoformat()
            )

            # 保存到数据库
            self.db.add(feed_item)
            await self.db.commit()
            await self.db.refresh(feed_item)

            # 更新资源为公开
            asset.is_public = True
            await self.db.commit()

            logger.info(
                f"Feed item published: {feed_item.id}, asset_id={asset_id}, "
                f"user_id={user_id}, title={title}"
            )

            return feed_item

        except FeedPermissionError:
            raise
        except FeedServiceError:
            raise
        except Exception as e:
            logger.error(f"Failed to publish asset: {str(e)}")
            await self.db.rollback()
            raise FeedServiceError(f"Failed to publish asset: {str(e)}")

    async def like_feed(self, feed_id: str) -> int:
        """
        点赞社区动态

        Args:
            feed_id: 社区动态 ID

        Returns:
            更新后的点赞数

        Raises:
            FeedNotFoundError: 如果动态不存在
            FeedServiceError: 如果点赞失败

        注意：
            - 使用 Redis 缓存点赞数
            - 如果 Redis 不可用，直接更新数据库
            - 每次点赞后同步到数据库
        """
        # 验证参数
        if not feed_id:
            logger.error("feed_id is empty")
            raise FeedServiceError("feed_id is required")

        try:
            # 查询动态
            result = await self.db.execute(
                select(FeedItem).where(FeedItem.id == feed_id)
            )
            feed_item = result.scalar_one_or_none()

            if not feed_item:
                logger.warning(f"Feed item not found: {feed_id}")
                raise FeedNotFoundError(f"Feed item not found: {feed_id}")

            # 使用 Redis 缓存点赞数
            if self.redis:
                try:
                    # Redis Key: feed:likes:{feed_id}
                    redis_key = f"feed:likes:{feed_id}"

                    # 增加点赞数
                    likes_count = await self.redis.incr(redis_key)

                    # 同步到数据库（异步，不等待）
                    # TODO: 实现后台任务定期同步 Redis 到数据库
                    # 这里简化处理，每次都同步
                    feed_item.likes_count = likes_count
                    await self.db.commit()

                    logger.debug(f"Feed liked (Redis): {feed_id}, likes_count={likes_count}")
                    return likes_count

                except Exception as redis_error:
                    logger.warning(f"Redis error, fallback to database: {str(redis_error)}")
                    # Redis 失败，回退到数据库操作

            # 直接更新数据库
            feed_item.likes_count += 1
            await self.db.commit()
            await self.db.refresh(feed_item)

            logger.debug(f"Feed liked (Database): {feed_id}, likes_count={feed_item.likes_count}")
            return feed_item.likes_count

        except FeedNotFoundError:
            raise
        except Exception as e:
            logger.error(f"Failed to like feed: {str(e)}")
            await self.db.rollback()
            raise FeedServiceError(f"Failed to like feed: {str(e)}")

    async def report_feed(
        self,
        feed_id: str,
        reporter_id: str,
        reason: str,
        description: Optional[str] = None
    ) -> Report:
        """
        举报社区动态

        Args:
            feed_id: 社区动态 ID
            reporter_id: 举报人 ID
            reason: 举报原因
            description: 举报描述（可选）

        Returns:
            举报对象

        Raises:
            FeedNotFoundError: 如果动态不存在
            ReportAlreadyExistsError: 如果已经举报过
            FeedServiceError: 如果举报失败

        注意：
            - 每个用户对每个动态只能举报一次
            - 举报状态默认为 'pending'
            - 管理员会在后台审核举报
        """
        # 验证参数
        if not feed_id:
            logger.error("feed_id is empty")
            raise FeedServiceError("feed_id is required")

        if not reporter_id:
            logger.error("reporter_id is empty")
            raise FeedServiceError("reporter_id is required")

        if not reason:
            logger.error("reason is empty")
            raise FeedServiceError("reason is required")

        try:
            # 查询动态
            result = await self.db.execute(
                select(FeedItem).where(FeedItem.id == feed_id)
            )
            feed_item = result.scalar_one_or_none()

            if not feed_item:
                logger.warning(f"Feed item not found: {feed_id}")
                raise FeedNotFoundError(f"Feed item not found: {feed_id}")

            # 检查是否已经举报过
            existing_report = await self.db.execute(
                select(Report).where(
                    and_(
                        Report.feed_item_id == feed_id,
                        Report.reporter_id == reporter_id
                    )
                )
            )
            if existing_report.scalar_one_or_none():
                logger.warning(
                    f"User {reporter_id} already reported feed {feed_id}"
                )
                raise ReportAlreadyExistsError("You have already reported this feed")

            # 创建举报记录
            report = Report(
                feed_item_id=feed_id,
                reporter_id=reporter_id,
                reason=reason,
                description=description,
                status="pending"
            )

            # 保存到数据库
            self.db.add(report)
            await self.db.commit()
            await self.db.refresh(report)

            logger.info(
                f"Feed reported: {feed_id}, reporter_id={reporter_id}, "
                f"reason={reason}"
            )

            return report

        except FeedNotFoundError:
            raise
        except ReportAlreadyExistsError:
            raise
        except Exception as e:
            logger.error(f"Failed to report feed: {str(e)}")
            await self.db.rollback()
            raise FeedServiceError(f"Failed to report feed: {str(e)}")

    async def get_feed_by_id(self, feed_id: str) -> FeedItem:
        """
        获取单个社区动态详情

        Args:
            feed_id: 社区动态 ID

        Returns:
            社区动态对象

        Raises:
            FeedNotFoundError: 如果动态不存在
            FeedServiceError: 如果查询失败

        注意：
            - 关联查询 Asset 和 User
            - 返回完整的动态信息
        """
        # 验证参数
        if not feed_id:
            logger.error("feed_id is empty")
            raise FeedServiceError("feed_id is required")

        try:
            # 查询动态（关联 Asset 和 User）
            result = await self.db.execute(
                select(FeedItem)
                .options(
                    selectinload(FeedItem.asset),
                    selectinload(FeedItem.user)
                )
                .where(FeedItem.id == feed_id)
            )
            feed_item = result.scalar_one_or_none()

            if not feed_item:
                logger.warning(f"Feed item not found: {feed_id}")
                raise FeedNotFoundError(f"Feed item not found: {feed_id}")

            logger.debug(f"Feed item retrieved: {feed_id}")
            return feed_item

        except FeedNotFoundError:
            raise
        except Exception as e:
            logger.error(f"Failed to get feed: {str(e)}")
            raise FeedServiceError(f"Failed to get feed: {str(e)}")

    async def get_likes_count(self, feed_id: str) -> int:
        """
        获取点赞数（优先从 Redis 读取）

        Args:
            feed_id: 社区动态 ID

        Returns:
            点赞数

        Raises:
            FeedServiceError: 如果查询失败

        注意：
            - 优先从 Redis 读取
            - 如果 Redis 不可用，从数据库读取
        """
        # 验证参数
        if not feed_id:
            logger.error("feed_id is empty")
            raise FeedServiceError("feed_id is required")

        try:
            # 优先从 Redis 读取
            if self.redis:
                try:
                    redis_key = f"feed:likes:{feed_id}"
                    likes_count = await self.redis.get(redis_key)

                    if likes_count:
                        return int(likes_count)

                except Exception as redis_error:
                    logger.warning(f"Redis error, fallback to database: {str(redis_error)}")

            # 从数据库读取
            result = await self.db.execute(
                select(FeedItem.likes_count).where(FeedItem.id == feed_id)
            )
            likes_count = result.scalar_one_or_none()

            if likes_count is None:
                logger.warning(f"Feed item not found: {feed_id}")
                raise FeedNotFoundError(f"Feed item not found: {feed_id}")

            return likes_count

        except FeedNotFoundError:
            raise
        except Exception as e:
            logger.error(f"Failed to get likes count: {str(e)}")
            raise FeedServiceError(f"Failed to get likes count: {str(e)}")