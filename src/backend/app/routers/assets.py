"""
资源路由模块

提供资源/图片的上传、查询、更新和删除相关的 API 接口。

功能特性：
- 图片上传（支持多种格式）
- 获取用户资源列表（支持分页和过滤）
- 获取单个资源详情
- 删除资源（权限检查）
- 更新资源信息

API 接口：
- POST /api/v1/assets/upload - 上传图片
- GET /api/v1/assets/my - 获取用户资源列表
- GET /api/v1/assets/{asset_id} - 获取单个资源详情
- DELETE /api/v1/assets/{asset_id} - 删除资源
- PATCH /api/v1/assets/{asset_id} - 更新资源信息
"""

from typing import Annotated, Optional

from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File, Form
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
import logging

from app.database.connection import get_db
from app.models.schemas import (
    AssetResponse,
    AssetListResponse,
    AssetUpdate,
    SuccessResponse
)
from app.services.asset_service import (
    AssetService,
    AssetNotFoundError,
    AssetPermissionError,
    AssetServiceError
)
from app.services.auth_service import AuthService, InvalidTokenError, UserNotFoundError
from app.models.user import User

logger = logging.getLogger(__name__)

# 创建路由器
router = APIRouter(prefix="/api/v1/assets", tags=["Assets"])

# HTTP Bearer 认证
security = HTTPBearer()


async def get_asset_service(
    db: Annotated[AsyncSession, Depends(get_db)]
) -> AssetService:
    """
    依赖注入：获取 AssetService 实例

    Args:
        db: 数据库会话

    Returns:
        AssetService 实例
    """
    return AssetService(db)


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


@router.post("/upload", response_model=AssetResponse, status_code=status.HTTP_201_CREATED)
async def upload_image(
    file: Annotated[UploadFile, File(description="图片文件")],
    current_user: Annotated[User, Depends(get_current_user)],
    asset_service: Annotated[AssetService, Depends(get_asset_service)]
):
    """
    上传图片

    支持的图片格式：
    - PNG
    - JPG/JPEG
    - WebP
    - GIF

    文件大小限制：
    - 最大 10MB

    Args:
        file: 图片文件（multipart/form-data）
        current_user: 当前用户（从 JWT Token 解析）
        asset_service: 资源服务实例

    Returns:
        资源响应（包含 URL 和元数据）

    Raises:
        HTTPException: 如果上传失败

    示例：
        ```bash
        curl -X POST "http://localhost:8000/api/v1/assets/upload" \
          -H "Authorization: Bearer <access_token>" \
          -F "file=@/path/to/image.png"
        ```

    注意：
        - 需要在请求头中提供有效的 JWT Token
        - 文件类型必须为支持的图片格式
        - 文件大小不能超过 10MB
        - 图片保存到本地存储
        - 资源类型为 'upload'
    """
    try:
        # 验证文件
        if not file:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No file provided"
            )

        # 验证文件类型
        content_type = file.content_type or ""
        if not content_type.startswith("image/"):
            logger.warning(f"Invalid file type: {content_type}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid file type: {content_type}. Only image files are allowed"
            )

        # 读取文件内容
        image_data = await file.read()

        # 验证文件大小
        if len(image_data) == 0:
            logger.warning("Empty file uploaded")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Empty file"
            )

        logger.info(
            f"Uploading image: filename={file.filename}, "
            f"size={len(image_data)} bytes, "
            f"content_type={content_type}"
        )

        # 调用服务上传图片
        asset = await asset_service.upload_image(
            user_id=str(current_user.id),
            image_data=image_data,
            filename=file.filename or "image.png"
        )

        # 返回响应
        return AssetResponse.model_validate(asset)

    except AssetServiceError as e:
        logger.warning(f"Asset service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error during upload: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred during upload"
        )


@router.get("/my", response_model=AssetListResponse, status_code=status.HTTP_200_OK)
async def get_my_assets(
    current_user: Annotated[User, Depends(get_current_user)],
    asset_service: Annotated[AssetService, Depends(get_asset_service)],
    page: int = 1,
    size: int = 20,
    asset_type: Optional[str] = None
):
    """
    获取用户资源列表

    Args:
        page: 页码（从 1 开始，默认 1）
        size: 每页数量（默认 20，最大 100）
        asset_type: 资源类型过滤（upload/generated，可选）
        current_user: 当前用户（从 JWT Token 解析）
        asset_service: 资源服务实例

    Returns:
        资源列表响应（包含分页信息）

    Raises:
        HTTPException: 如果查询失败

    示例：
        ```bash
        # 获取所有资源
        curl -X GET "http://localhost:8000/api/v1/assets/my?page=1&size=20" \
          -H "Authorization: Bearer <access_token>"

        # 获取上传的资源
        curl -X GET "http://localhost:8000/api/v1/assets/my?page=1&size=20&type=upload" \
          -H "Authorization: Bearer <access_token>"

        # 获取生成的资源
        curl -X GET "http://localhost:8000/api/v1/assets/my?page=1&size=20&type=generated" \
          -H "Authorization: Bearer <access_token>"
        ```

    注意：
        - 需要在请求头中提供有效的 JWT Token
        - 只返回当前用户的资源
        - 支持分页
        - 支持按类型过滤
        - 按创建时间倒序排列
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

        # 验证资源类型
        if asset_type and asset_type not in ["upload", "generated"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="asset_type must be 'upload' or 'generated'"
            )

        # 调用服务获取资源列表
        result = await asset_service.get_user_assets(
            user_id=str(current_user.id),
            page=page,
            size=size,
            asset_type=asset_type
        )

        # 构建响应
        return AssetListResponse(
            total=result["total"],
            page=result["page"],
            size=result["size"],
            items=[AssetResponse.model_validate(asset) for asset in result["items"]]
        )

    except AssetServiceError as e:
        logger.warning(f"Asset service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while getting assets: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while getting assets"
        )


@router.get("/{asset_id}", response_model=AssetResponse, status_code=status.HTTP_200_OK)
async def get_asset(
    asset_id: str,
    asset_service: Annotated[AssetService, Depends(get_asset_service)]
):
    """
    获取单个资源详情

    Args:
        asset_id: 资源 ID
        asset_service: 资源服务实例

    Returns:
        资源响应

    Raises:
        HTTPException: 如果资源不存在

    示例：
        ```bash
        curl -X GET "http://localhost:8000/api/v1/assets/{asset_id}"
        ```

    注意：
        - 此接口不需要认证
        - 任何用户都可以查询资源详情
        - 如果资源不存在，返回 404
    """
    try:
        # 调用服务获取资源
        asset = await asset_service.get_asset_by_id(asset_id)

        # 返回响应
        return AssetResponse.model_validate(asset)

    except AssetNotFoundError as e:
        logger.warning(f"Asset not found: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while getting asset: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while getting asset"
        )


@router.delete("/{asset_id}", response_model=SuccessResponse, status_code=status.HTTP_200_OK)
async def delete_asset(
    asset_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    asset_service: Annotated[AssetService, Depends(get_asset_service)]
):
    """
    删除资源

    Args:
        asset_id: 资源 ID
        current_user: 当前用户（从 JWT Token 解析）
        asset_service: 资源服务实例

    Returns:
        成功响应

    Raises:
        HTTPException: 如果删除失败

    示例：
        ```bash
        curl -X DELETE "http://localhost:8000/api/v1/assets/{asset_id}" \
          -H "Authorization: Bearer <access_token>"
        ```

    注意：
        - 需要在请求头中提供有效的 JWT Token
        - 只能删除自己的资源
        - 同时删除数据库记录和存储文件
        - 删除操作不可逆
    """
    try:
        # 调用服务删除资源
        success = await asset_service.delete_asset(
            asset_id=asset_id,
            user_id=str(current_user.id)
        )

        if not success:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to delete asset"
            )

        # 返回成功响应
        return SuccessResponse(message="Asset deleted successfully")

    except AssetNotFoundError as e:
        logger.warning(f"Asset not found: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    except AssetPermissionError as e:
        logger.warning(f"Permission denied: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while deleting asset: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while deleting asset"
        )


@router.patch("/{asset_id}", response_model=AssetResponse, status_code=status.HTTP_200_OK)
async def update_asset(
    asset_id: str,
    updates: AssetUpdate,
    current_user: Annotated[User, Depends(get_current_user)],
    asset_service: Annotated[AssetService, Depends(get_asset_service)]
):
    """
    更新资源信息

    可更新字段：
    - is_public: 是否公开（布尔值）
    - prompt: 提示词（仅对生成的资源有效）
    - model_version: 模型版本（仅对生成的资源有效）

    Args:
        asset_id: 资源 ID
        updates: 更新字段
        current_user: 当前用户（从 JWT Token 解析）
        asset_service: 资源服务实例

    Returns:
        更新后的资源响应

    Raises:
        HTTPException: 如果更新失败

    示例：
        ```bash
        # 设置为公开
        curl -X PATCH "http://localhost:8000/api/v1/assets/{asset_id}" \
          -H "Authorization: Bearer <access_token>" \
          -H "Content-Type: application/json" \
          -d '{"is_public": true}'

        # 更新提示词
        curl -X PATCH "http://localhost:8000/api/v1/assets/{asset_id}" \
          -H "Authorization: Bearer <access_token>" \
          -H "Content-Type: application/json" \
          -d '{"prompt": "A beautiful sunset"}'
        ```

    注意：
        - 需要在请求头中提供有效的 JWT Token
        - 只能更新自己的资源
        - 不可更新字段：id, user_id, url, type
    """
    try:
        # 转换为字典
        update_dict = updates.model_dump(exclude_unset=True)

        if not update_dict:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No fields to update"
            )

        # 调用服务更新资源
        asset = await asset_service.update_asset(
            asset_id=asset_id,
            user_id=str(current_user.id),
            updates=update_dict
        )

        # 返回响应
        return AssetResponse.model_validate(asset)

    except AssetNotFoundError as e:
        logger.warning(f"Asset not found: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    except AssetPermissionError as e:
        logger.warning(f"Permission denied: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=str(e)
        )
    except AssetServiceError as e:
        logger.warning(f"Asset service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while updating asset: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while updating asset"
        )