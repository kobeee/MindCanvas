"""
Pytest 配置文件

提供测试所需的 fixtures
"""

import asyncio
import pytest_asyncio
from typing import AsyncGenerator
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

from app.main import app
from app.models.user import User
from app.database.base import Base


# 测试数据库 URL - 使用实际数据库（127.0.0.1 避免 IPv6 问题）
TEST_DATABASE_URL = "postgresql+psycopg://mindcanvas:your_secure_password@127.0.0.1:5432/mindcanvas"


# 创建测试数据库引擎
test_engine = create_async_engine(
    TEST_DATABASE_URL,
    echo=False
)

# 创建测试数据库会话工厂
TestSessionLocal = async_sessionmaker(
    test_engine,
    class_=AsyncSession,
    expire_on_commit=False
)


@pytest_asyncio.fixture(scope="function")
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    """
    创建数据库会话

    在每个测试函数执行前创建新的数据库会话，
    测试完成后回滚所有更改。
    """
    async with test_engine.begin() as conn:
        # 创建所有表
        await conn.run_sync(Base.metadata.create_all)

    async with TestSessionLocal() as session:
        yield session
        await session.rollback()

    async with test_engine.begin() as conn:
        # 删除所有表
        await conn.run_sync(Base.metadata.drop_all)


@pytest_asyncio.fixture(scope="function")
async def async_client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    """
    创建异步 HTTP 客户端

    用于测试 FastAPI 接口
    """
    # 依赖注入：覆盖数据库会话
    async def override_get_db():
        yield db_session

    from app.database.connection import get_db
    app.dependency_overrides[get_db] = override_get_db

    async with AsyncClient(app=app, base_url="http://test") as client:
        yield client

    # 清理依赖注入
    app.dependency_overrides.clear()


@pytest_asyncio.fixture(scope="function")
async def test_user(db_session: AsyncSession) -> AsyncGenerator[User, None]:
    """
    创建测试用户

    返回一个测试用户对象
    """
    from app.models.schemas import UserCreate

    user_data = UserCreate(
        email="test@example.com",
        username="testuser",
        auth_provider="email"
    )
    user = User(**user_data.model_dump())
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)

    yield user

    # Cleanup
    await db_session.delete(user)
    await db_session.commit()