"""
任务服务测试模块

测试 TaskService 的核心功能
"""

import pytest
import asyncio
from unittest.mock import AsyncMock, MagicMock, patch
from sqlalchemy.ext.asyncio import AsyncSession

from app.services.task_service import TaskService, TaskNotFoundError, TaskServiceError
from app.models.task import Task
from app.services.encryption import EncryptionService
from app.services.google_api import GoogleAPIClient
from app.storage.image_storage import ImageStorage


@pytest.fixture
def mock_db():
    """模拟数据库会话"""
    return AsyncMock(spec=AsyncSession)


@pytest.fixture
def mock_encryption_service():
    """模拟加密服务"""
    service = AsyncMock(spec=EncryptionService)
    service.encrypt = MagicMock(return_value="encrypted_key")
    service.decrypt = MagicMock(return_value="decrypted_api_key")
    return service


@pytest.fixture
def mock_google_client():
    """模拟 Google API 客户端"""
    client = AsyncMock(spec=GoogleAPIClient)
    client.generate_image = AsyncMock(return_value=b"fake_image_data")
    return client


@pytest.fixture
def mock_storage():
    """模拟图片存储"""
    storage = AsyncMock(spec=ImageStorage)
    storage.save_image = AsyncMock(return_value="http://localhost:8000/images/generated/task123.png")
    storage.delete_image = AsyncMock(return_value=True)
    return storage


@pytest.fixture
def task_service(mock_db, mock_encryption_service, mock_google_client, mock_storage):
    """创建 TaskService 实例"""
    return TaskService(
        db=mock_db,
        encryption_service=mock_encryption_service,
        google_client=mock_google_client,
        storage=mock_storage
    )


@pytest.mark.asyncio
async def test_create_task(task_service, mock_db):
    """测试创建任务"""
    # 模拟数据库操作
    mock_task = MagicMock()
    mock_task.id = "task-123"
    mock_db.add = MagicMock()
    mock_db.commit = AsyncMock()
    mock_db.refresh = AsyncMock()

    with patch('app.services.task_service.Task') as MockTask:
        MockTask.return_value = mock_task
        with patch('app.services.task_service.asyncio.create_task'):
            task_id = await task_service.create_task(
                user_id="user-123",
                encrypted_api_key="encrypted_key",
                prompt="A beautiful sunset"
            )

            assert task_id == "task-123"
            mock_db.add.assert_called_once()
            mock_db.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_create_task_missing_params(task_service):
    """测试缺少参数时创建任务"""
    with pytest.raises(TaskServiceError):
        await task_service.create_task(
            user_id="",
            encrypted_api_key="encrypted_key",
            prompt="A beautiful sunset"
        )

    with pytest.raises(TaskServiceError):
        await task_service.create_task(
            user_id="user-123",
            encrypted_api_key="",
            prompt="A beautiful sunset"
        )

    with pytest.raises(TaskServiceError):
        await task_service.create_task(
            user_id="user-123",
            encrypted_api_key="encrypted_key",
            prompt=""
        )


@pytest.mark.asyncio
async def test_get_task_status(task_service, mock_db):
    """测试获取任务状态"""
    # 模拟任务对象
    mock_task = MagicMock()
    mock_task.id = "task-123"
    mock_task.status = "completed"
    mock_task.image_url = "http://localhost:8000/images/generated/task123.png"
    mock_task.error_message = None

    # 模拟数据库查询
    mock_result = MagicMock()
    mock_result.scalar_one_or_none.return_value = mock_task
    mock_db.execute = AsyncMock(return_value=mock_result)

    status = await task_service.get_task_status("task-123")

    assert status["task_id"] == "task-123"
    assert status["status"] == "completed"
    assert status["image_url"] == "http://localhost:8000/images/generated/task123.png"


@pytest.mark.asyncio
async def test_get_task_status_not_found(task_service, mock_db):
    """测试获取不存在的任务状态"""
    mock_result = MagicMock()
    mock_result.scalar_one_or_none.return_value = None
    mock_db.execute = AsyncMock(return_value=mock_result)

    with pytest.raises(TaskNotFoundError):
        await task_service.get_task_status("nonexistent-task")


if __name__ == "__main__":
    pytest.main([__file__, "-v"])