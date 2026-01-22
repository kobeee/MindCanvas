"""
任务服务模块

提供生图任务的创建、状态查询和异步处理功能。
整合 EncryptionService、ProviderFactory、QuotaService、ImageStorage 实现完整的生图流程。

安全特性：
- API Key 加密存储，任务完成后立即删除
- API Key 只在任务处理时解密到内存，用完即销毁
- 完善的错误处理和日志记录
- 支持异步任务处理
- 支持多提供商（Google API、Laozhang API）
"""

import asyncio
import logging
from typing import Optional, Dict, Any
from datetime import datetime, timedelta, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update

from app.database.connection import AsyncSessionLocal
from app.models.task import Task
from app.services.rsa_encryption_service import RSAEncryptionService, RSAEncryptionError
from app.services.encryption import EncryptionService, EncryptionError, DecryptionError
from app.services.google_api import GoogleAPIClient, GoogleAPIError
from app.services.provider_factory import ProviderFactory
from app.services.quota_service import QuotaService
from app.storage.image_storage import ImageStorage, ImageType

logger = logging.getLogger(__name__)


class TaskNotFoundError(Exception):
    """任务不存在异常"""
    pass


class TaskServiceError(Exception):
    """任务服务异常基类"""
    pass


class TaskService:
    """
    任务服务类

    提供生图任务的创建、状态查询和异步处理功能。
    整合 EncryptionService、ProviderFactory、QuotaService、ImageStorage 实现完整的生图流程。

    使用方法：
        # 初始化服务
        task_service = TaskService(
            db=db_session,
            encryption_service=encryption_service,
            storage=image_storage
        )

        # 创建任务
        task_id = await task_service.create_task(
            user_id="user123",
            encrypted_api_key="encrypted_key",
            prompt="A beautiful sunset",
            base_image="base64_image"
        )

        # 查询任务状态
        status = await task_service.get_task_status(task_id)
    """

    def __init__(
        self,
        db: AsyncSession,
        encryption_service: RSAEncryptionService,
        storage: Optional[ImageStorage] = None
    ):
        """
        初始化任务服务

        Args:
            db: 异步数据库会话
            encryption_service: RSA 加密服务实例
            storage: 图片存储服务实例（可选，默认创建新实例）

        注意：
            - 所有服务实例必须正确初始化
            - storage 参数可选，如果不提供会创建新实例
            - 使用 ProviderFactory 动态创建 API 提供商实例
        """
        self.db = db
        self.encryption_service = encryption_service
        self.storage = storage or ImageStorage()
        self.quota_service = QuotaService(db)

        logger.info("TaskService initialized successfully")

    async def create_task(
        self,
        user_id: str,
        encrypted_api_key: Optional[str],
        prompt: str,
        base_image: Optional[str] = None
    ) -> str:
        """
        创建生图任务

        Args:
            user_id: 用户 ID
            encrypted_api_key: 加密的 API Key（从 iOS APP 传输，Google API 需要，Laozhang API 不需要）
            prompt: 提示词（描述要生成的图片）
            base_image: 参考图的 Base64 编码字符串（可选，用于图片到图片生成）

        Returns:
            任务 ID（UUID 字符串）

        Raises:
            TaskServiceError: 如果任务创建失败

        注意：
            - 任务创建后立即加入后台处理队列
            - Google API：API Key 加密存储到数据库，任务完成后会自动清除
            - Laozhang API：使用配置中的 API Key，不需要用户提供
            - 自动选择用户使用的 API 提供商
        """
        if not user_id:
            logger.error("user_id is empty")
            raise TaskServiceError("user_id is required")

        if not prompt:
            logger.error("prompt is empty")
            raise TaskServiceError("prompt is required")

        try:
            # 获取用户使用的 API 提供商
            api_provider = await self.quota_service.get_user_api_provider(user_id)
            logger.info(f"User {user_id} uses API provider: {api_provider}")

            # 确定图片尺寸
            image_size = "2K" if api_provider == "laozhang" else "1K"

            # 检查 API Key
            if api_provider == "google":
                if not encrypted_api_key:
                    raise TaskServiceError("encrypted_api_key is required for Google API")
            elif api_provider == "laozhang":
                # Laozhang API 不需要用户提供 API Key
                encrypted_api_key = None

            # 创建任务记录
            task = Task(
                user_id=user_id,
                encrypted_api_key=encrypted_api_key,
                prompt=prompt,
                base_image=base_image,
                status="pending",
                api_provider=api_provider,
                image_size=image_size
            )

            # 保存到数据库
            self.db.add(task)
            await self.db.commit()
            await self.db.refresh(task)

            logger.info(f"Task created: {task.id}, user_id={user_id}, prompt_length={len(prompt)}, provider={api_provider}, size={image_size}")

            # 异步处理任务（不等待完成）
            asyncio.create_task(self._process_task(str(task.id)))

            return str(task.id)

        except Exception as e:
            logger.error(f"Failed to create task: {str(e)}")
            await self.db.rollback()
            raise TaskServiceError(f"Failed to create task: {str(e)}")

    async def get_task_status(self, task_id: str) -> Dict[str, Any]:
        """
        获取任务状态

        Args:
            task_id: 任务 ID

        Returns:
            任务状态信息字典，包含：
            - task_id: 任务 ID
            - status: 任务状态（pending/processing/completed/failed）
            - image_url: 图片 URL（仅当 status=completed 时）
            - error_message: 错误信息（仅当 status=failed 时）

        Raises:
            TaskNotFoundError: 如果任务不存在

        注意：
            - 此方法不会返回 API Key（安全考虑）
            - 任务完成后 API Key 已被清除
        """
        if not task_id:
            logger.error("task_id is empty")
            raise TaskServiceError("task_id is required")

        try:
            # 查询任务
            result = await self.db.execute(
                select(Task).where(Task.id == task_id)
            )
            task = result.scalar_one_or_none()

            if not task:
                logger.warning(f"Task not found: {task_id}")
                raise TaskNotFoundError(f"Task not found: {task_id}")

            # 构建响应
            response: Dict[str, Any] = {
                "task_id": task.id,
                "status": task.status
            }

            # 根据状态添加额外信息
            if task.status == "completed":
                if task.image_url:
                    response["image_url"] = task.image_url
                else:
                    logger.warning(f"Task {task_id} is completed but has no image_url")

            elif task.status == "failed":
                if task.error_message:
                    response["error_message"] = task.error_message
                else:
                    logger.warning(f"Task {task_id} is failed but has no error_message")

            logger.debug(f"Task status retrieved: {task_id}, status={task.status}")
            return response

        except TaskNotFoundError:
            raise
        except Exception as e:
            logger.error(f"Failed to get task status: {str(e)}")
            raise TaskServiceError(f"Failed to get task status: {str(e)}")

    async def _process_task(self, task_id: str):
        """
        处理任务（后台异步执行）

        Args:
            task_id: 任务 ID

        注意：
            - 此方法在后台异步执行，不阻塞主线程
            - 处理流程：
              1. 更新状态为 processing
              2. 获取 API Key（Google API 解密用户密钥，Laozhang API 使用配置密钥）
              3. 使用工厂模式创建 API 提供商实例
              4. 调用 API 生成图片
              5. 保存图片到本地存储
              6. 更新状态为 completed
              7. 清除 API Key（安全措施）
            - 任何步骤失败都会更新状态为 failed 并清除 API Key
        """
        logger.info(f"Starting to process task: {task_id}")

        try:
            # 更新状态为处理中
            await self._update_task_status(task_id, "processing")
            logger.info(f"Task {task_id} status updated to processing")

            # 获取任务
            result = await self.db.execute(
                select(Task).where(Task.id == task_id)
            )
            task = result.scalar_one()

            # 获取 API Key
            api_key = None

            if task.api_provider == "google":
                # Google API：解密用户提供的 API Key
                if not task.encrypted_api_key:
                    raise TaskServiceError("Task has no encrypted_api_key for Google API")

                try:
                    # iOS 端发送的是 Base64 编码的 RSA 加密数据
                    import base64
                    logger.info(f"Task {task_id}: Starting API Key decryption, encrypted_api_key length={len(task.encrypted_api_key)}")
                    encrypted_bytes = base64.b64decode(task.encrypted_api_key)
                    logger.info(f"Task {task_id}: Base64 decoded, encrypted_bytes length={len(encrypted_bytes)}")
                    logger.debug(f"Task {task_id}: Encrypted bytes (first 50): {encrypted_bytes[:50].hex()}")
                    api_key = self.encryption_service.decrypt(encrypted_bytes)
                    logger.info(f"Task {task_id}: API Key decrypted successfully, length={len(api_key)}")
                    logger.debug(f"Task {task_id}: API Key (first 10 chars): {api_key[:10]}...")
                except RSAEncryptionError as e:
                    logger.error(f"Failed to decrypt API Key for task {task_id}: {str(e)}")
                    raise TaskServiceError(f"Failed to decrypt API Key: {str(e)}")

            elif task.api_provider == "laozhang":
                # Laozhang API：使用配置中的 API Key
                from app.config import settings
                if not settings.LAOZHANG_API_KEY:
                    raise TaskServiceError("Laozhang API Key not configured")

                api_key = settings.LAOZHANG_API_KEY
                logger.info(f"Task {task_id}: Using Laozhang API Key from config, length={len(api_key)}")

            else:
                raise TaskServiceError(f"Unknown API provider: {task.api_provider}")

            # 使用工厂模式创建 API 提供商实例
            try:
                provider = ProviderFactory.create_provider(task.api_provider)
                logger.info(f"Task {task_id}: Using API provider: {task.api_provider}")
            except ValueError as e:
                logger.error(f"Failed to create provider for task {task_id}: {str(e)}")
                raise TaskServiceError(f"Failed to create provider: {str(e)}")

            # 调用 API 生成图片
            try:
                image_data = await provider.generate_image(
                    api_key=api_key,
                    prompt=task.prompt,
                    base_image=task.base_image,
                    image_size=task.image_size
                )
                logger.info(f"Image generated successfully for task {task_id}, size={len(image_data)} bytes")
            except Exception as e:
                logger.error(f"API error for task {task_id}: {str(e)}")
                raise TaskServiceError(f"API error: {str(e)}")

            # 立即清除内存中的 API Key（安全措施）
            api_key = None
            logger.debug(f"API Key cleared from memory for task {task_id}")

            # 保存图片到本地存储
            try:
                image_url = await self._save_image(task_id, image_data)
                logger.info(f"Image saved for task {task_id}: {image_url}")
            except Exception as e:
                logger.error(f"Failed to save image for task {task_id}: {str(e)}")
                raise TaskServiceError(f"Failed to save image: {str(e)}")

            # 设置图片过期时间（7天后）
            image_expires_at = datetime.now(timezone.utc) + timedelta(days=7)

            # 更新任务状态为完成
            await self._update_task_status(
                task_id,
                "completed",
                image_url=image_url,
                image_expires_at=image_expires_at
            )
            logger.info(f"Task {task_id} completed successfully")

            # 扣减配额（Laozhang API）
            if task.api_provider == "laozhang":
                await self.quota_service.decrement_quota(task.user_id)
                logger.info(f"Quota decremented for user {task.user_id}")

            # 清除数据库中的 API Key（安全措施）
            await self._clear_api_key(task_id)
            logger.info(f"API Key cleared from database for task {task_id}")

        except Exception as e:
            # 更新任务状态为失败
            logger.error(f"Task {task_id} failed: {str(e)}")
            await self._update_task_status(
                task_id,
                "failed",
                error_message=str(e)
            )
            # 清除数据库中的 API Key（安全措施）
            await self._clear_api_key(task_id)
            logger.info(f"API Key cleared from database for failed task {task_id}")

    async def _update_task_status(
        self,
        task_id: str,
        status: str,
        image_url: Optional[str] = None,
        image_expires_at: Optional[datetime] = None,
        error_message: Optional[str] = None
    ):
        """
        更新任务状态

        Args:
            task_id: 任务 ID
            status: 新状态（pending/processing/completed/failed）
            image_url: 图片 URL（可选）
            image_expires_at: 图片过期时间（可选）
            error_message: 错误信息（可选）

        Raises:
            TaskServiceError: 如果更新失败

        注意：
            - 此方法使用新的独立会话，避免与外层会话冲突
        """
        async with AsyncSessionLocal() as session:
            try:
                update_data: Dict[str, Any] = {"status": status}

                if image_url:
                    update_data["image_url"] = image_url

                if image_expires_at:
                    update_data["image_expires_at"] = image_expires_at

                if error_message:
                    update_data["error_message"] = error_message

                await session.execute(
                    update(Task).where(Task.id == task_id).values(**update_data)
                )
                await session.commit()

                logger.debug(f"Task {task_id} status updated to {status}")

            except Exception as e:
                logger.error(f"Failed to update task status: {str(e)}")
                try:
                    await session.rollback()
                except Exception:
                    # 忽略 rollback 错误，可能 session 已经处于无效状态
                    pass
                raise TaskServiceError(f"Failed to update task status: {str(e)}")

    async def _clear_api_key(self, task_id: str):
        """
        清除 API Key（安全措施）

        Args:
            task_id: 任务 ID

        注意：
            - 任务完成后必须立即清除 API Key
            - 即使任务失败也要清除 API Key
            - 此操作不可逆
            - 此方法使用新的独立会话，避免与外层会话冲突
        """
        async with AsyncSessionLocal() as session:
            try:
                await session.execute(
                    update(Task)
                    .where(Task.id == task_id)
                    .values(encrypted_api_key=None)
                )
                await session.commit()

                logger.info(f"API Key cleared for task {task_id}")

            except Exception as e:
                logger.error(f"Failed to clear API Key for task {task_id}: {str(e)}")
                try:
                    await session.rollback()
                except Exception:
                    # 忽略 rollback 错误，可能 session 已经处于无效状态
                    pass
                # 不抛出异常，避免影响主流程

    async def _save_image(self, task_id: str, image_data: bytes) -> str:
        """
        保存图片到本地存储

        Args:
            task_id: 任务 ID（用作图片 ID）
            image_data: 图片二进制数据

        Returns:
            图片访问 URL

        Raises:
            TaskServiceError: 如果保存失败

        注意：
            - 图片使用任务 ID 作为文件名
            - 图片类型为 GENERATED
            - 图片格式为 PNG
        """
        try:
            image_url = await self.storage.save_image(
                image_id=task_id,
                image_data=image_data,
                extension="png",
                image_type=ImageType.GENERATED
            )

            logger.debug(f"Image saved: {image_url}")
            return image_url

        except Exception as e:
            logger.error(f"Failed to save image: {str(e)}")
            raise TaskServiceError(f"Failed to save image: {str(e)}")

    async def cleanup_old_tasks(self, hours: int = 24) -> int:
        """
        清理过期任务

        Args:
            hours: 保留小时数（默认 24 小时）

        Returns:
            删除的任务数量

        注意：
            - 只删除已完成或失败的任务
            - 保留 pending 和 processing 状态的任务
            - 同时删除关联的图片文件
        """
        from datetime import datetime, timedelta

        deleted_count = 0
        cutoff_time = datetime.utcnow() - timedelta(hours=hours)

        try:
            # 查询过期任务
            result = await self.db.execute(
                select(Task).where(
                    Task.created_at < cutoff_time,
                    Task.status.in_(["completed", "failed"])
                )
            )
            tasks = result.scalars().all()

            for task in tasks:
                try:
                    # 删除图片文件
                    if task.image_url:
                        await self.storage.delete_image(task.image_url)
                        logger.info(f"Deleted image for task {task.id}: {task.image_url}")

                    # 删除任务记录
                    await self.db.execute(
                        update(Task).where(Task.id == task.id).values(encrypted_api_key=None)
                    )
                    # 注意：这里不删除任务记录，只标记为已清理
                    # 实际删除可以由数据库定期清理任务完成

                    deleted_count += 1

                except Exception as e:
                    logger.error(f"Failed to cleanup task {task.id}: {str(e)}")
                    continue

            await self.db.commit()
            logger.info(f"Cleanup completed: {deleted_count} tasks cleaned")
            return deleted_count

        except Exception as e:
            logger.error(f"Failed to cleanup old tasks: {str(e)}")
            await self.db.rollback()
            raise TaskServiceError(f"Failed to cleanup old tasks: {str(e)}")

    async def get_user_tasks(
        self,
        user_id: str,
        status: Optional[str] = None,
        limit: int = 50
    ) -> list[Dict[str, Any]]:
        """
        获取用户的任务列表

        Args:
            user_id: 用户 ID
            status: 任务状态过滤（可选）
            limit: 返回数量限制（默认 50）

        Returns:
            任务列表

        注意：
            - 不返回 API Key
            - 按创建时间倒序排列
        """
        try:
            query = select(Task).where(Task.user_id == user_id)

            if status:
                query = query.where(Task.status == status)

            query = query.order_by(Task.created_at.desc()).limit(limit)

            result = await self.db.execute(query)
            tasks = result.scalars().all()

            # 构建响应
            response_list = []
            for task in tasks:
                task_dict = {
                    "task_id": task.id,
                    "status": task.status,
                    "prompt": task.prompt,
                    "created_at": task.created_at.isoformat(),
                    "updated_at": task.updated_at.isoformat()
                }

                if task.status == "completed" and task.image_url:
                    task_dict["image_url"] = task.image_url

                if task.status == "failed" and task.error_message:
                    task_dict["error_message"] = task.error_message

                response_list.append(task_dict)

            logger.debug(f"Retrieved {len(response_list)} tasks for user {user_id}")
            return response_list

        except Exception as e:
            logger.error(f"Failed to get user tasks: {str(e)}")
            raise TaskServiceError(f"Failed to get user tasks: {str(e)}")