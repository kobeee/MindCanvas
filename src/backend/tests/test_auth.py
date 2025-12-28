"""
认证服务测试

测试 AuthService 的各项功能
"""

import pytest
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from app.services.auth_service import AuthService, AuthError, InvalidTokenError, UserNotFoundError
from app.models.user import User
from app.models.schemas import UserCreate


@pytest.mark.asyncio
class TestAuthService:
    """认证服务测试类"""

    async def test_login_with_provider_apple(self, db_session):
        """测试 Apple 登录"""
        auth_service = AuthService(db_session)

        # Mock Apple Token
        token = "apple_identity_token_mock_12345678"

        # 测试登录
        result = await auth_service.login_with_provider("apple", token)

        # 验证结果
        assert "access_token" in result
        assert "token_type" in result
        assert result["token_type"] == "bearer"
        assert "user" in result
        assert result["user"].auth_provider == "apple"
        assert result["user"].email is not None

    async def test_login_with_provider_google(self, db_session):
        """测试 Google 登录"""
        auth_service = AuthService(db_session)

        # Mock Google Token
        token = "google_id_token_mock_12345678"

        # 测试登录
        result = await auth_service.login_with_provider("google", token)

        # 验证结果
        assert "access_token" in result
        assert result["user"].auth_provider == "google"
        assert result["user"].email is not None

    async def test_login_with_provider_github(self, db_session):
        """测试 GitHub 登录"""
        auth_service = AuthService(db_session)

        # Mock GitHub Token
        token = "github_access_token_mock_12345678"

        # 测试登录
        result = await auth_service.login_with_provider("github", token)

        # 验证结果
        assert "access_token" in result
        assert result["user"].auth_provider == "github"
        assert result["user"].email is not None

    async def test_login_with_provider_email(self, db_session):
        """测试邮箱登录"""
        auth_service = AuthService(db_session)

        # Mock Email Token
        token = "email_verification_code_mock_12345678"

        # 测试登录
        result = await auth_service.login_with_provider("email", token)

        # 验证结果
        assert "access_token" in result
        assert result["user"].auth_provider == "email"
        assert result["user"].email is not None

    async def test_create_access_token(self, db_session):
        """测试创建访问令牌"""
        auth_service = AuthService(db_session)

        # 创建测试用户
        user_id = str(uuid4())
        token = await auth_service.create_access_token(user_id)

        # 验证 Token 格式
        assert token is not None
        assert isinstance(token, str)
        assert len(token) > 0

    async def test_verify_token(self, db_session):
        """测试验证令牌"""
        auth_service = AuthService(db_session)

        # 创建 Token
        user_id = str(uuid4())
        token = await auth_service.create_access_token(user_id)

        # 验证 Token
        verified_user_id = await auth_service.verify_token(token)

        # 验证结果
        assert verified_user_id == user_id

    async def test_verify_invalid_token(self, db_session):
        """测试验证无效令牌"""
        auth_service = AuthService(db_session)

        # 测试无效 Token
        with pytest.raises(InvalidTokenError):
            await auth_service.verify_token("invalid_token_string")

    async def test_get_current_user(self, db_session):
        """测试获取当前用户"""
        auth_service = AuthService(db_session)

        # 创建测试用户
        user_data = UserCreate(
            email="test@example.com",
            username="testuser",
            auth_provider="email"
        )
        user = User(**user_data.model_dump())
        db_session.add(user)
        await db_session.commit()
        await db_session.refresh(user)

        # 创建 Token
        token = await auth_service.create_access_token(str(user.id))

        # 获取当前用户
        current_user = await auth_service.get_current_user(token)

        # 验证结果
        assert current_user.id == user.id
        assert current_user.email == user.email

    async def test_get_current_user_invalid_token(self, db_session):
        """测试使用无效 Token 获取当前用户"""
        auth_service = AuthService(db_session)

        # 测试无效 Token
        with pytest.raises(InvalidTokenError):
            await auth_service.get_current_user("invalid_token_string")

    async def test_login_same_user_twice(self, db_session):
        """测试同一用户登录两次"""
        auth_service = AuthService(db_session)

        # 第一次登录
        token1 = "apple_identity_token_same_user_12345"
        result1 = await auth_service.login_with_provider("apple", token1)
        user_id_1 = result1["user"].id

        # 第二次登录（相同 Token）
        result2 = await auth_service.login_with_provider("apple", token1)
        user_id_2 = result2["user"].id

        # 验证返回的是同一个用户
        assert user_id_1 == user_id_2

    async def test_hash_password(self):
        """测试密码哈希"""
        password = "test_password_123"

        # 哈希密码
        hashed_password = AuthService.hash_password(password)

        # 验证哈希结果
        assert hashed_password is not None
        assert hashed_password != password
        assert hashed_password.startswith("$2b$")  # bcrypt 哈希格式

    async def test_verify_password(self):
        """测试密码验证"""
        password = "test_password_123"

        # 哈希密码
        hashed_password = AuthService.hash_password(password)

        # 验证正确密码
        assert AuthService.verify_password(password, hashed_password) is True

        # 验证错误密码
        assert AuthService.verify_password("wrong_password", hashed_password) is False


@pytest.mark.asyncio
class TestAuthRouter:
    """认证路由测试类"""

    async def test_login_endpoint(self, async_client):
        """测试登录接口"""
        response = await async_client.post(
            "/api/v1/auth/login",
            json={
                "provider": "apple",
                "token": "apple_identity_token_test_12345"
            }
        )

        # 验证响应
        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert "token_type" in data
        assert data["token_type"] == "bearer"
        assert "user" in data

    async def test_login_invalid_provider(self, async_client):
        """测试无效的提供者"""
        response = await async_client.post(
            "/api/v1/auth/login",
            json={
                "provider": "invalid_provider",
                "token": "some_token"
            }
        )

        # 验证响应
        assert response.status_code == 400

    async def test_get_me_endpoint(self, async_client):
        """测试获取当前用户信息接口"""
        # 先登录获取 Token
        login_response = await async_client.post(
            "/api/v1/auth/login",
            json={
                "provider": "google",
                "token": "google_id_token_test_12345"
            }
        )
        token = login_response.json()["access_token"]

        # 获取当前用户信息
        response = await async_client.get(
            "/api/v1/auth/me",
            headers={"Authorization": f"Bearer {token}"}
        )

        # 验证响应
        assert response.status_code == 200
        data = response.json()
        assert "id" in data
        assert "email" in data

    async def test_get_me_without_token(self, async_client):
        """测试不带 Token 获取当前用户信息"""
        response = await async_client.get("/api/v1/auth/me")

        # 验证响应
        assert response.status_code == 401

    async def test_get_me_invalid_token(self, async_client):
        """测试使用无效 Token 获取当前用户信息"""
        response = await async_client.get(
            "/api/v1/auth/me",
            headers={"Authorization": "Bearer invalid_token"}
        )

        # 验证响应
        assert response.status_code == 401

    async def test_logout_endpoint(self, async_client):
        """测试登出接口"""
        # 先登录获取 Token
        login_response = await async_client.post(
            "/api/v1/auth/login",
            json={
                "provider": "github",
                "token": "github_token_test_12345"
            }
        )
        token = login_response.json()["access_token"]

        # 登出
        response = await async_client.post(
            "/api/v1/auth/logout",
            headers={"Authorization": f"Bearer {token}"}
        )

        # 验证响应
        assert response.status_code == 200
        data = response.json()
        assert "message" in data