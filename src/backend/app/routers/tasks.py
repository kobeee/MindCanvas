"""
任务路由模块

提供生图任务的创建、状态查询和删除相关的 API 接口。

功能特性：
- 创建生图任务（支持文本生成图片和图片到图片生成）
- 查询任务状态
- 获取用户任务列表
- 删除任务

API 接口：
- POST /api/v1/generate/tasks - 创建生图任务
- GET /api/v1/generate/tasks/{task_id}/status - 查询任务状态
- GET /api/v1/generate/tasks/user/{user_id} - 获取用户任务列表
- DELETE /api/v1/generate/tasks/{task_id} - 删除任务
"""

from typing import Annotated, Optional
import base64

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
import logging

from app.database.connection import get_db
from app.models.schemas import (
    TaskCreate,
    TaskResponse,
    TaskStatusResponse,
    TaskListResponse,
    SuccessResponse
)
from app.services.task_service import (
    TaskService,
    TaskNotFoundError,
    TaskServiceError
)
from app.services.rsa_encryption_service import RSAEncryptionService
from app.services.google_api import GoogleAPIClient
from app.storage.image_storage import ImageStorage
from app.services.auth_service import AuthService, InvalidTokenError, UserNotFoundError
from app.models.user import User
from app.config import settings

logger = logging.getLogger(__name__)

# 创建路由器
router = APIRouter(prefix="/api/v1/generate", tags=["Generation"])

# HTTP Bearer 认证
security = HTTPBearer()


async def get_task_service(
    db: Annotated[AsyncSession, Depends(get_db)]
) -> TaskService:
    """
    依赖注入：获取 TaskService 实例

    Args:
        db: 数据库会话

    Returns:
        TaskService 实例
    """
    # 初始化依赖服务
    # 从配置获取 RSA 私钥
    private_key_pem = base64.b64decode(settings.RSA_PRIVATE_KEY_BASE64)
    rsa_service = RSAEncryptionService(private_key_pem=private_key_pem)
    storage = ImageStorage()

    return TaskService(
        db=db,
        encryption_service=rsa_service,
        storage=storage
    )


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


@router.post("/tasks", response_model=TaskResponse, status_code=status.HTTP_201_CREATED)
async def create_task(
    request: TaskCreate,
    current_user: Annotated[User, Depends(get_current_user)],
    task_service: Annotated[TaskService, Depends(get_task_service)]
):
    """
    创建生图任务

    支持两种生成模式：
    - 文本生成图片（Text-to-Image）：仅提供 prompt
    - 图片到图片生成（Image-to-Image）：提供 prompt 和 base_image

    Args:
        request: 任务创建请求（包含 encrypted_api_key, prompt, base_image）
        current_user: 当前用户（从 JWT Token 解析）
        task_service: 任务服务实例

    Returns:
        任务响应（包含任务 ID 和初始状态）

    Raises:
        HTTPException: 如果任务创建失败

    示例：
        ```bash
        # 文本生成图片
        curl -X POST "http://localhost:8000/api/v1/generate/tasks" \
          -H "Authorization: Bearer <access_token>" \
          -H "Content-Type: application/json" \
          -d '{
            "encrypted_api_key": "encrypted_key_string",
            "prompt": "A beautiful sunset over the ocean",
            "base_image": null
          }'

        # 图片到图片生成
        curl -X POST "http://localhost:8000/api/v1/generate/tasks" \
          -H "Authorization: Bearer <access_token>" \
          -H "Content-Type: application/json" \
          -d '{
            "encrypted_api_key": "encrypted_key_string",
            "prompt": "Make it look like a watercolor painting",
            "base_image": "base64_encoded_image_string"
          }'
        ```

    注意：
        - 需要在请求头中提供有效的 JWT Token
        - encrypted_api_key 必须在客户端使用 RSA 公钥加密
        - 任务创建后立即加入后台处理队列
        - API Key 加密存储到数据库，任务完成后立即删除
        - 任务状态：pending -> processing -> completed/failed
    """
    try:
        # 验证请求参数
        if not request.prompt:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="prompt is required"
            )

        if len(request.prompt) > 2000:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="prompt must be less than 2000 characters"
            )

        # 调用服务创建任务
        task_id = await task_service.create_task(
            user_id=str(current_user.id),
            encrypted_api_key=request.encrypted_api_key,
            prompt=request.prompt,
            base_image=request.base_image
        )

        # 构建响应
        response = TaskResponse(
            id=task_id,
            user_id=current_user.id,
            prompt=request.prompt,
            base_image=request.base_image,
            status="pending",
            created_at=None,
            updated_at=None
        )

        logger.info(f"Task created: {task_id}, user_id={current_user.id}")

        # 返回响应
        return response

    except TaskServiceError as e:
        logger.warning(f"Task service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        import traceback
        logger.error(f"Unexpected error while creating task: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An unexpected error occurred while creating task: {str(e)}"
        )


@router.get("/tasks/{task_id}/status", response_model=TaskStatusResponse, status_code=status.HTTP_200_OK)
async def get_task_status(
    task_id: str,
    task_service: Annotated[TaskService, Depends(get_task_service)]
):
    """
    查询任务状态

    Args:
        task_id: 任务 ID
        task_service: 任务服务实例

    Returns:
        任务状态响应（包含状态、进度、图片 URL、错误信息）

    Raises:
        HTTPException: 如果任务不存在

    示例：
        ```bash
        curl -X GET "http://localhost:8000/api/v1/generate/tasks/{task_id}/status"
        ```

    注意：
        - 此接口不需要认证
        - 任务状态：
          - pending: 等待处理
          - processing: 正在处理
          - completed: 已完成，image_url 可用
          - failed: 失败，error_message 包含错误信息
        - image_url 仅在 status=completed 时返回
        - error_message 仅在 status=failed 时返回
    """
    try:
        # 调用服务获取任务状态
        status_info = await task_service.get_task_status(task_id)

        # 构建响应
        response = TaskStatusResponse(
            task_id=status_info["task_id"],
            status=status_info["status"],
            image_url=status_info.get("image_url"),
            error_message=status_info.get("error_message")
        )

        return response

    except TaskNotFoundError as e:
        logger.warning(f"Task not found: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    except TaskServiceError as e:
        logger.warning(f"Task service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while getting task status: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while getting task status"
        )


@router.get("/tasks/user/{user_id}", response_model=TaskListResponse, status_code=status.HTTP_200_OK)
async def get_user_tasks(
    user_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    task_service: Annotated[TaskService, Depends(get_task_service)],
    page: int = 1,
    size: int = 20,
    status_filter: Optional[str] = None
):
    """
    获取用户任务列表

    Args:
        user_id: 用户 ID
        page: 页码（从 1 开始，默认 1）
        size: 每页数量（默认 20，最大 100）
        status_filter: 任务状态过滤（pending/processing/completed/failed，可选）
        current_user: 当前用户（从 JWT Token 解析）
        task_service: 任务服务实例

    Returns:
        任务列表响应（包含分页信息）

    Raises:
        HTTPException: 如果查询失败

    示例：
        ```bash
        # 获取所有任务
        curl -X GET "http://localhost:8000/api/v1/generate/tasks/user/{user_id}?page=1&size=20" \
          -H "Authorization: Bearer <access_token>"

        # 获取已完成的任务
        curl -X GET "http://localhost:8000/api/v1/generate/tasks/user/{user_id}?page=1&size=20&status=completed" \
          -H "Authorization: Bearer <access_token>"
        ```

    注意：
        - 需要在请求头中提供有效的 JWT Token
        - 只能查询自己的任务
        - 支持分页
        - 支持按状态过滤
        - 按创建时间倒序排列
        - 不返回 API Key（安全考虑）
    """
    try:
        # 验证权限
        if str(current_user.id) != user_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only view your own tasks"
            )

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

        # 验证状态过滤
        if status_filter and status_filter not in ["pending", "processing", "completed", "failed"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="status must be one of: pending, processing, completed, failed"
            )

        # 调用服务获取任务列表
        tasks = await task_service.get_user_tasks(
            user_id=user_id,
            status=status_filter,
            limit=size
        )

        # 计算分页
        total = len(tasks)
        start = (page - 1) * size
        end = start + size
        page_tasks = tasks[start:end]

        # 构建响应
        response = TaskListResponse(
            total=total,
            page=page,
            size=size,
            items=[]
        )

        for task_dict in page_tasks:
            task_response = TaskResponse(
                id=task_dict["task_id"],
                user_id=current_user.id,
                prompt=task_dict["prompt"],
                status=task_dict["status"],
                created_at=None,
                updated_at=None
            )

            if "image_url" in task_dict:
                task_response.image_url = task_dict["image_url"]

            if "error_message" in task_dict:
                task_response.error_message = task_dict["error_message"]

            response.items.append(task_response)

        return response

    except TaskServiceError as e:
        logger.warning(f"Task service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        logger.error(f"Unexpected error while getting user tasks: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while getting user tasks"
        )


@router.delete("/tasks/{task_id}", response_model=SuccessResponse, status_code=status.HTTP_200_OK)
async def delete_task(
    task_id: str,
    current_user: Annotated[User, Depends(get_current_user)],
    task_service: Annotated[TaskService, Depends(get_task_service)]
):
    """
    删除任务

    Args:
        task_id: 任务 ID
        current_user: 当前用户（从 JWT Token 解析）
        task_service: 任务服务实例

    Returns:
        成功响应

    Raises:
        HTTPException: 如果删除失败

    示例：
        ```bash
        curl -X DELETE "http://localhost:8000/api/v1/generate/tasks/{task_id}" \
          -H "Authorization: Bearer <access_token>"
        ```

    注意：
        - 需要在请求头中提供有效的 JWT Token
        - 只能删除自己的任务
        - 只能删除已完成或失败的任务
        - 删除任务会同时清除 API Key（如果还存在）
        - 删除任务不会删除关联的图片文件
    """
    try:
        from sqlalchemy import select, delete
        from app.models.task import Task

        # 查询任务
        result = await task_service.db.execute(
            select(Task).where(Task.id == task_id)
        )
        task = result.scalar_one_or_none()

        if not task:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Task not found: {task_id}"
            )

        # 验证权限
        if str(task.user_id) != str(current_user.id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You can only delete your own tasks"
            )

        # 验证状态
        if task.status not in ["completed", "failed"]:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Cannot delete task with status: {task.status}. Only completed or failed tasks can be deleted."
            )

        # 删除任务
        await task_service.db.execute(
            delete(Task).where(Task.id == task_id)
        )
        await task_service.db.commit()

        logger.info(f"Task deleted: {task_id}, user_id={current_user.id}")

        return SuccessResponse(message="Task deleted successfully")

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error while deleting task: {str(e)}")
        await task_service.db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="An unexpected error occurred while deleting task"
        )