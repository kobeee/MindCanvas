"""
资源服务模块

提供资源/图片的上传、查询、更新和删除功能。
整合 ImageStorage 实现图片的保存和管理。

安全特性：
- 文件类型验证（仅支持图片格式）
- 文件大小限制
- 权限检查（只能操作自己的资源）
- 完善的错误处理和日志记录
"""

import logging
from typing import Optional, Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, delete, func
from uuid import uuid4

from app.models.asset import Asset
from app.storage.image_storage import ImageStorage, ImageType

logger = logging.getLogger(__name__)


class AssetNotFoundError(Exception):
    """资源不存在异常"""
    pass


class AssetPermissionError(Exception):
    """资源权限异常"""
    pass


class AssetServiceError(Exception):
    """资源服务异常基类"""
    pass


class AssetService:
    """
    资源服务类

    提供资源/图片的上传、查询、更新和删除功能。
    整合 ImageStorage 实现图片的保存和管理。

    使用方法：
        # 初始化服务
        asset_service = AssetService(
            db=db_session,
            storage=image_storage
        )

        # 上传图片
        asset = await asset_service.upload_image(
            user_id="user123",
            image_data=b"...",
            filename="image.png"
        )

        # 获取用户资源列表
        result = await asset_service.get_user_assets(
            user_id="user123",
            page=1,
            size=20
        )
    """

    # 支持的图片格式
    ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "webp", "gif"}

    # 文件大小限制（10MB）
    MAX_FILE_SIZE = 10 * 1024 * 1024

    def __init__(
        self,
        db: AsyncSession,
        storage: Optional[ImageStorage] = None
    ):
        """
        初始化资源服务

        Args:
            db: 异步数据库会话
            storage: 图片存储服务实例（可选，默认创建新实例）

        注意：
            - 所有服务实例必须正确初始化
            - storage 参数可选，如果不提供会创建新实例
        """
        self.db = db
        self.storage = storage or ImageStorage()

        logger.info("AssetService initialized successfully")

    async def upload_image(
        self,
        user_id: str,
        image_data: bytes,
        filename: str
    ) -> Asset:
        """
        上传图片

        Args:
            user_id: 用户 ID
            image_data: 图片二进制数据
            filename: 文件名（用于提取扩展名）

        Returns:
            资源对象

        Raises:
            AssetServiceError: 如果上传失败

        注意：
            - 文件类型必须为支持的图片格式
            - 文件大小不能超过限制
            - 图片保存到本地存储
            - 资源类型为 'upload'
        """
        # 验证用户 ID
        if not user_id:
            logger.error("user_id is empty")
            raise AssetServiceError("user_id is required")

        # 验证图片数据
        if not image_data:
            logger.error("image_data is empty")
            raise AssetServiceError("image_data is required")

        # 验证文件大小
        if len(image_data) > self.MAX_FILE_SIZE:
            logger.error(f"File size exceeds limit: {len(image_data)} bytes")
            raise AssetServiceError(
                f"File size exceeds limit of {self.MAX_FILE_SIZE} bytes"
            )

        # 提取文件扩展名
        extension = self._extract_extension(filename)
        if not extension:
            logger.error(f"Invalid filename: {filename}")
            raise AssetServiceError("Invalid filename")

        # 验证文件类型
        if extension not in self.ALLOWED_EXTENSIONS:
            logger.error(f"Unsupported file type: {extension}")
            raise AssetServiceError(
                f"Unsupported file type: {extension}. "
                f"Allowed types: {', '.join(self.ALLOWED_EXTENSIONS)}"
            )

        try:
            # 生成资源 ID
            asset_id = str(uuid4())

            # 保存图片到存储
            image_url = await self.storage.save_image(
                image_id=asset_id,
                image_data=image_data,
                extension=extension,
                image_type=ImageType.UPLOADED
            )
            logger.info(f"Image saved to storage: {image_url}")

            # 创建资源记录
            asset = Asset(
                id=asset_id,
                user_id=user_id,
                url=image_url,
                type="upload"
            )

            # 保存到数据库
            self.db.add(asset)
            await self.db.commit()
            await self.db.refresh(asset)

            logger.info(
                f"Asset created: {asset.id}, user_id={user_id}, "
                f"filename={filename}, size={len(image_data)} bytes"
            )

            return asset

        except Exception as e:
            logger.error(f"Failed to upload image: {str(e)}")
            await self.db.rollback()
            raise AssetServiceError(f"Failed to upload image: {str(e)}")

    async def get_user_assets(
        self,
        user_id: str,
        page: int = 1,
        size: int = 20,
        asset_type: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        获取用户资源列表

        Args:
            user_id: 用户 ID
            page: 页码（从 1 开始）
            size: 每页数量
            asset_type: 资源类型过滤（upload/generated）

        Returns:
            资源列表字典，包含：
            - items: 资源列表
            - total: 总数量
            - page: 当前页码
            - size: 每页数量
            - total_pages: 总页数

        Raises:
            AssetServiceError: 如果查询失败

        注意：
            - 支持分页
            - 支持按类型过滤
            - 按创建时间倒序排列
        """
        # 验证用户 ID
        if not user_id:
            logger.error("user_id is empty")
            raise AssetServiceError("user_id is required")

        # 验证分页参数
        if page < 1:
            logger.error(f"Invalid page: {page}")
            raise AssetServiceError("page must be >= 1")

        if size < 1 or size > 100:
            logger.error(f"Invalid size: {size}")
            raise AssetServiceError("size must be between 1 and 100")

        # 验证资源类型
        if asset_type and asset_type not in ["upload", "generated"]:
            logger.error(f"Invalid asset_type: {asset_type}")
            raise AssetServiceError(
                "asset_type must be 'upload' or 'generated'"
            )

        try:
            # 构建查询
            query = select(Asset).where(Asset.user_id == user_id)

            # 添加类型过滤
            if asset_type:
                query = query.where(Asset.type == asset_type)

            # 按创建时间倒序排列
            query = query.order_by(Asset.created_at.desc())

            # 获取总数
            count_query = select(func.count()).select_from(
                query.subquery()
            )
            total_result = await self.db.execute(count_query)
            total = total_result.scalar() or 0

            # 计算偏移量
            offset = (page - 1) * size

            # 添加分页
            query = query.offset(offset).limit(size)

            # 执行查询
            result = await self.db.execute(query)
            assets = result.scalars().all()

            # 计算总页数
            total_pages = (total + size - 1) // size

            # 构建响应
            response = {
                "items": assets,
                "total": total,
                "page": page,
                "size": size,
                "total_pages": total_pages
            }

            logger.debug(
                f"Retrieved {len(assets)} assets for user {user_id}, "
                f"page={page}, total={total}"
            )

            return response

        except Exception as e:
            logger.error(f"Failed to get user assets: {str(e)}")
            raise AssetServiceError(f"Failed to get user assets: {str(e)}")

    async def get_asset_by_id(self, asset_id: str) -> Asset:
        """
        获取单个资源详情

        Args:
            asset_id: 资源 ID

        Returns:
            资源对象

        Raises:
            AssetNotFoundError: 如果资源不存在
            AssetServiceError: 如果查询失败

        注意：
            - 此方法不检查权限，任何用户都可以查询
            - 如果需要权限检查，请使用 check_ownership 方法
        """
        # 验证资源 ID
        if not asset_id:
            logger.error("asset_id is empty")
            raise AssetServiceError("asset_id is required")

        try:
            # 查询资源
            result = await self.db.execute(
                select(Asset).where(Asset.id == asset_id)
            )
            asset = result.scalar_one_or_none()

            if not asset:
                logger.warning(f"Asset not found: {asset_id}")
                raise AssetNotFoundError(f"Asset not found: {asset_id}")

            logger.debug(f"Asset retrieved: {asset_id}")
            return asset

        except AssetNotFoundError:
            raise
        except Exception as e:
            logger.error(f"Failed to get asset: {str(e)}")
            raise AssetServiceError(f"Failed to get asset: {str(e)}")

    async def delete_asset(self, asset_id: str, user_id: str) -> bool:
        """
        删除资源

        Args:
            asset_id: 资源 ID
            user_id: 用户 ID（用于权限检查）

        Returns:
            是否删除成功

        Raises:
            AssetNotFoundError: 如果资源不存在
            AssetPermissionError: 如果用户无权删除该资源
            AssetServiceError: 如果删除失败

        注意：
            - 只能删除自己的资源
            - 同时删除数据库记录和存储文件
        """
        # 验证参数
        if not asset_id:
            logger.error("asset_id is empty")
            raise AssetServiceError("asset_id is required")

        if not user_id:
            logger.error("user_id is empty")
            raise AssetServiceError("user_id is required")

        try:
            # 查询资源
            asset = await self.get_asset_by_id(asset_id)

            # 检查权限
            if asset.user_id != user_id:
                logger.warning(
                    f"User {user_id} attempted to delete asset {asset_id} "
                    f"owned by {asset.user_id}"
                )
                raise AssetPermissionError(
                    "You don't have permission to delete this asset"
                )

            # 删除存储文件
            if asset.url:
                await self.storage.delete_image(asset.url)
                logger.info(f"Image deleted from storage: {asset.url}")

            # 删除数据库记录
            await self.db.execute(
                delete(Asset).where(Asset.id == asset_id)
            )
            await self.db.commit()

            logger.info(f"Asset deleted: {asset_id}, user_id={user_id}")
            return True

        except AssetNotFoundError:
            raise
        except AssetPermissionError:
            raise
        except Exception as e:
            logger.error(f"Failed to delete asset: {str(e)}")
            await self.db.rollback()
            raise AssetServiceError(f"Failed to delete asset: {str(e)}")

    async def update_asset(
        self,
        asset_id: str,
        user_id: str,
        updates: Dict[str, Any]
    ) -> Asset:
        """
        更新资源信息

        Args:
            asset_id: 资源 ID
            user_id: 用户 ID（用于权限检查）
            updates: 更新字段字典

        Returns:
            更新后的资源对象

        Raises:
            AssetNotFoundError: 如果资源不存在
            AssetPermissionError: 如果用户无权更新该资源
            AssetServiceError: 如果更新失败

        注意：
            - 只能更新自己的资源
            - 可更新字段：is_public, prompt, model_version
            - 不可更新字段：id, user_id, url, type
        """
        # 验证参数
        if not asset_id:
            logger.error("asset_id is empty")
            raise AssetServiceError("asset_id is required")

        if not user_id:
            logger.error("user_id is empty")
            raise AssetServiceError("user_id is required")

        if not updates:
            logger.error("updates is empty")
            raise AssetServiceError("updates is required")

        try:
            # 查询资源
            asset = await self.get_asset_by_id(asset_id)

            # 检查权限
            if asset.user_id != user_id:
                logger.warning(
                    f"User {user_id} attempted to update asset {asset_id} "
                    f"owned by {asset.user_id}"
                )
                raise AssetPermissionError(
                    "You don't have permission to update this asset"
                )

            # 验证可更新字段
            allowed_fields = {"is_public", "prompt", "model_version"}
            invalid_fields = set(updates.keys()) - allowed_fields

            if invalid_fields:
                logger.error(f"Invalid update fields: {invalid_fields}")
                raise AssetServiceError(
                    f"Invalid update fields: {', '.join(invalid_fields)}. "
                    f"Allowed fields: {', '.join(allowed_fields)}"
                )

            # 更新字段
            for field, value in updates.items():
                setattr(asset, field, value)

            # 保存到数据库
            await self.db.commit()
            await self.db.refresh(asset)

            logger.info(
                f"Asset updated: {asset_id}, user_id={user_id}, "
                f"fields={list(updates.keys())}"
            )

            return asset

        except AssetNotFoundError:
            raise
        except AssetPermissionError:
            raise
        except Exception as e:
            logger.error(f"Failed to update asset: {str(e)}")
            await self.db.rollback()
            raise AssetServiceError(f"Failed to update asset: {str(e)}")

    async def check_ownership(self, asset_id: str, user_id: str) -> bool:
        """
        检查资源归属权

        Args:
            asset_id: 资源 ID
            user_id: 用户 ID

        Returns:
            是否为该用户的资源

        Raises:
            AssetServiceError: 如果查询失败

        注意：
            - 此方法用于权限检查
            - 如果资源不存在，返回 False
        """
        try:
            asset = await self.get_asset_by_id(asset_id)
            return asset.user_id == user_id
        except AssetNotFoundError:
            return False
        except Exception as e:
            logger.error(f"Failed to check ownership: {str(e)}")
            raise AssetServiceError(f"Failed to check ownership: {str(e)}")

    def _extract_extension(self, filename: str) -> Optional[str]:
        """
        从文件名提取扩展名

        Args:
            filename: 文件名

        Returns:
            扩展名（不包含点），如果没有则返回 None

        注意：
            - 扩展名转换为小写
            - 如果文件名不包含扩展名，返回 None
        """
        if not filename:
            return None

        # 分割文件名
        parts = filename.rsplit(".", 1)

        if len(parts) != 2:
            return None

        extension = parts[1].lower()

        # 验证扩展名
        if not extension:
            return None

        return extension

    async def get_public_assets(
        self,
        page: int = 1,
        size: int = 20,
        asset_type: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        获取公开资源列表

        Args:
            page: 页码（从 1 开始）
            size: 每页数量
            asset_type: 资源类型过滤（upload/generated）

        Returns:
            资源列表字典，包含：
            - items: 资源列表
            - total: 总数量
            - page: 当前页码
            - size: 每页数量
            - total_pages: 总页数

        Raises:
            AssetServiceError: 如果查询失败

        注意：
            - 只返回公开的资源
            - 支持分页
            - 支持按类型过滤
            - 按创建时间倒序排列
        """
        # 验证分页参数
        if page < 1:
            logger.error(f"Invalid page: {page}")
            raise AssetServiceError("page must be >= 1")

        if size < 1 or size > 100:
            logger.error(f"Invalid size: {size}")
            raise AssetServiceError("size must be between 1 and 100")

        # 验证资源类型
        if asset_type and asset_type not in ["upload", "generated"]:
            logger.error(f"Invalid asset_type: {asset_type}")
            raise AssetServiceError(
                "asset_type must be 'upload' or 'generated'"
            )

        try:
            # 构建查询
            query = select(Asset).where(Asset.is_public == True)

            # 添加类型过滤
            if asset_type:
                query = query.where(Asset.type == asset_type)

            # 按创建时间倒序排列
            query = query.order_by(Asset.created_at.desc())

            # 获取总数
            count_query = select(func.count()).select_from(
                query.subquery()
            )
            total_result = await self.db.execute(count_query)
            total = total_result.scalar() or 0

            # 计算偏移量
            offset = (page - 1) * size

            # 添加分页
            query = query.offset(offset).limit(size)

            # 执行查询
            result = await self.db.execute(query)
            assets = result.scalars().all()

            # 计算总页数
            total_pages = (total + size - 1) // size

            # 构建响应
            response = {
                "items": assets,
                "total": total,
                "page": page,
                "size": size,
                "total_pages": total_pages
            }

            logger.debug(
                f"Retrieved {len(assets)} public assets, "
                f"page={page}, total={total}"
            )

            return response

        except Exception as e:
            logger.error(f"Failed to get public assets: {str(e)}")
            raise AssetServiceError(f"Failed to get public assets: {str(e)}")