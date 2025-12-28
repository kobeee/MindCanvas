"""
社区路由模块

提供社区动态的发布、查询、点赞和举报相关的 API 接口。

功能特性：
- 获取社区动态列表（支持分页和排序）
- 发布资源到社区
- 点赞社区动态
- 举报社区动态
- 获取单个动态详情

API 接口：
- GET /api/v1/feed - 获取社区动态列表
- POST /api/v1/assets/{asset_id}/publish - 发布资源到社区
- POST /api/v1/feed/{feed_id}/like - 点赞动态
- POST /api/v1/feed/{feed_id}/report - 举报动态
- GET /api/v1/feed/{feed_id} - 获取单个动态详情
"""

from typing import Annotated, Optional

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
import logging

from app.database.connection import get_db
from app.models.schemas import (
    FeedItemResponse,
    FeedListResponse,
    PublishRequest,
    ReportRequest,
    SuccessResponse
)
from app.services.feed_service import (
    FeedService,
    FeedNotFoundError,
    FeedPermissionError,
    FeedServiceError,
    ReportAlreadyExistsError
)
from app.services.auth_service import AuthService, InvalidTokenError, UserNotFoundError
from app.models.user import User

logger = logging.getLogger(__name__)

# 创建路由器
router = APIRouter(prefix="/api/v1/feed", tags=["Feed"])

# HTTP Bearer 认证
security = HTTPBearer()


async def get_feed_service(
    db: Annotated[AsyncSession, Depends(get_db)]
) -> FeedService:
    """
    依赖注入：获取 FeedService 实例

    Args:
        db: 数据库会话

    Returns:
        FeedService 实例
    """
    # TODO: 注入 Redis 客户端
    # from app.database.redis import get_redis
    # redis = await get_redis()
    # return FeedService(db, redis)
    return FeedService(db)


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


async def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth_service: Annotated[AuthService, Depends(get_auth_service)]
) -> User:
    """
    依赖注入：从 JWT Token 获取当前用户

    Args:
        credentials: HTTP Bearer 认证凭证
        auth_service: 认证服务实例

    Returns:
        当前用户对象

    Raises:
        HTTPException: 如果 Token 无效或用户不存在
    """
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


@router.get("", response_model=FeedListResponse, status_code=status.HTTP_200_OK)
async def get_feed(
    feed_service: Annotated[FeedService, Depends(get_feed_service)],
    page: int = 1,
    size: int = 20,
    sort: str = "latest"
):
    """
    获取社区动态列表

    Args:
        page: 页码（从 1 开始，默认 1）
        size: 每页数量（默认 20，最大 100）
        sort: 排序方式（latest: 最新, hot: 热门，默认 latest）
        feed_service: 社区服务实例

    Returns:
        社区动态列表响应（包含分页信息）

    Raises:
        HTTPException: 如果查询失败

    示例：
        ```bash
        # 获取最新动态
        curl -X GET "http://localhost:8000/api/v1/feed?page=1&size=20&sort=latest"

        # 获取热门动态
        curl -X GET "http://localhost:8000/api/v1/feed?page=1&size=20&sort=hot"
        ```

    注意：
        - 此接口不需要认证
        - 支持分页
        - 支持按最新和热门排序
        - 热门排序按点赞数倒序
        - 最新排序按发布时间倒序
    """
    try:
        # 验证分页参数
        if page < 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="page must be >= 1"
            )

        if size < 1 or size > 100:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="size must be between 1 and 100"
            )

        # 验证排序方式
        if sort not in ["latest", "hot"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="sort must be 'latest' or 'hot'"
            )

        # 调用服务获取动态列表
        result = await feed_service.get_feed(
            page=page,
            size=size,
            sort=sort
        )

        # 构建响应
        return FeedListResponse(
            total=result["total"],
            page=result["page"],
            size=result["size"],
            items=[FeedItemResponse.model_validate(item) for item in result["items"]]
        )

    except FeedServiceError as e:
        logger.warning(f"Feed service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while getting feed: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while getting feed"
        )


@router.post("/assets/{asset_id}/publish", response_model=FeedItemResponse, status_code=status.HTTP_201_CREATED)
async def publish_asset(
    asset_id: str,
    request: PublishRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    feed_service: Annotated[FeedService, Depends(get_feed_service)]
):
    """
    发布资源到社区

    Args:
        asset_id: 资源 ID
        request: 发布请求（包含标题）
        current_user: 当前用户（从 JWT Token 解析）
        feed_service: 社区服务实例

    Returns:
        社区动态响应

    Raises:
        HTTPException: 如果发布失败

    示例：
        ```bash
        curl -X POST "http://localhost:8000/api/v1/feed/assets/{asset_id}/publish" \
          -H "Authorization: Bearer <access_token>" \
          -H "Content-Type: application/json" \
          -d '{"title": "My Masterpiece"}'
        ```

    注意：
        - 需要在请求头中提供有效的 JWT Token
        - 只能发布自己的资源
        - 每个资源只能发布一次
        - 发布后资源标记为公开
        - 标题可选，如果未提供则为空
    """
    try:
        # 调用服务发布资源
        feed_item = await feed_service.publish_asset(
            asset_id=asset_id,
            user_id=str(current_user.id),
            title=request.title
        )

        # 返回响应
        return FeedItemResponse.model_validate(feed_item)

    except FeedPermissionError as e:
        logger.warning(f"Permission denied: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(e)
        )
    except FeedServiceError as e:
        logger.warning(f"Feed service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while publishing asset: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while publishing asset"
        )


@router.post("/{feed_id}/like", response_model=SuccessResponse, status_code=status.HTTP_200_OK)
async def like_feed(
    feed_id: str,
    feed_service: Annotated[FeedService, Depends(get_feed_service)]
):
    """
    点赞社区动态

    Args:
        feed_id: 社区动态 ID
        feed_service: 社区服务实例

    Returns:
        成功响应（包含点赞数）

    Raises:
        HTTPException: 如果点赞失败

    示例：
        ```bash
        curl -X POST "http://localhost:8000/api/v1/feed/{feed_id}/like"
        ```

    注意：
        - 此接口不需要认证（可根据需求调整）
        - 使用 Redis 缓存点赞数
        - 每次点赞后同步到数据库
        - 返回更新后的点赞数
    """
    try:
        # 调用服务点赞
        likes_count = await feed_service.like_feed(feed_id)

        # 返回成功响应
        return SuccessResponse(
            message=f"Feed liked successfully, likes_count={likes_count}"
        )

    except FeedNotFoundError as e:
        logger.warning(f"Feed not found: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    except FeedServiceError as e:
        logger.warning(f"Feed service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while liking feed: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while liking feed"
        )


@router.post("/{feed_id}/report", response_model=SuccessResponse, status_code=status.HTTP_201_CREATED)
async def report_feed(
    feed_id: str,
    request: ReportRequest,
    current_user: Annotated[User, Depends(get_current_user)],
    feed_service: Annotated[FeedService, Depends(get_feed_service)]
):
    """
    举报社区动态

    Args:
        feed_id: 社区动态 ID
        request: 举报请求（包含原因）
        current_user: 当前用户（从 JWT Token 解析）
        feed_service: 社区服务实例

    Returns:
        成功响应

    Raises:
        HTTPException: 如果举报失败

    示例：
        ```bash
        curl -X POST "http://localhost:8000/api/v1/feed/{feed_id}/report" \
          -H "Authorization: Bearer <access_token>" \
          -H "Content-Type: application/json" \
          -d '{"reason": "nsfw"}'
        ```

    注意：
        - 需要在请求头中提供有效的 JWT Token
        - 每个用户对每个动态只能举报一次
        - 举报状态默认为 'pending'
        - 管理员会在后台审核举报
        - 支持的举报原因：nsfw, spam, violence, copyright, other
    """
    try:
        # 调用服务举报
        report = await feed_service.report_feed(
            feed_id=feed_id,
            reporter_id=str(current_user.id),
            reason=request.reason
        )

        # 返回成功响应
        return SuccessResponse(
            message=f"Feed reported successfully, report_id={report.id}"
        )

    except FeedNotFoundError as e:
        logger.warning(f"Feed not found: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    except ReportAlreadyExistsError as e:
        logger.warning(f"Report already exists: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except FeedServiceError as e:
        logger.warning(f"Feed service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while reporting feed: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while reporting feed"
        )


@router.get("/{feed_id}", response_model=FeedItemResponse, status_code=status.HTTP_200_OK)
async def get_feed_item(
    feed_id: str,
    feed_service: Annotated[FeedService, Depends(get_feed_service)]
):
    """
    获取单个社区动态详情

    Args:
        feed_id: 社区动态 ID
        feed_service: 社区服务实例

    Returns:
        社区动态响应

    Raises:
        HTTPException: 如果动态不存在

    示例：
        ```bash
        curl -X GET "http://localhost:8000/api/v1/feed/{feed_id}"
        ```

    注意：
        - 此接口不需要认证
        - 返回完整的动态信息
        - 包含关联的 Asset 和 User 信息
    """
    try:
        # 调用服务获取动态
        feed_item = await feed_service.get_feed_by_id(feed_id)

        # 返回响应
        return FeedItemResponse.model_validate(feed_item)

    except FeedNotFoundError as e:
        logger.warning(f"Feed not found: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while getting feed item: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while getting feed item"
        )