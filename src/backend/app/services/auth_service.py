"""
认证服务模块

提供用户认证、JWT Token 管理和第三方登录验证功能。

功能特性：
- 支持多种登录方式（Apple、Google、GitHub、邮箱）
- JWT Token 签发和验证
- 第三方 Token 验证（当前为 Mock 实现）
- 用户查找或创建
- 密码哈希（使用 passlib）

安全特性：
- 使用 JWT 进行身份验证
- 密钥从环境变量获取
- Token 过期时间可配置
- 密码使用 bcrypt 哈希存储
"""

from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any
from uuid import UUID

import bcrypt
from jose import JWTError, jwt
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
import logging

from app.config import settings
from app.models.user import User
from app.models.schemas import UserCreate
from app.services.google_token_validator import GoogleTokenValidator, GoogleTokenValidationError
from app.services.github_token_validator import GitHubTokenValidator, GitHubTokenValidationError


logger = logging.getLogger(__name__)


class AuthError(Exception):
    """认证服务异常基类"""
    pass


class InvalidTokenError(AuthError):
    """无效 Token 异常"""
    pass


class ProviderTokenError(AuthError):
    """第三方 Token 验证失败异常"""
    pass


class UserNotFoundError(AuthError):
    """用户不存在异常"""
    pass


class AuthService:
    """
    认证服务类

    提供用户认证、JWT Token 管理和第三方登录验证功能。

    使用方法：
        # 初始化服务
        auth_service = AuthService(db)

        # 第三方登录
        result = await auth_service.login_with_provider("apple", "identity_token_string")

        # 获取当前用户
        user = await auth_service.get_current_user("jwt_token_string")

        # 创建访问令牌
        token = await auth_service.create_access_token(user_id)

        # 验证令牌
        user_id = await auth_service.verify_token("jwt_token_string")
    """

    def __init__(self, db: AsyncSession):
        """
        初始化认证服务

        Args:
            db: 异步数据库会话

        注意：
            - JWT 密钥从环境变量获取
            - Token 过期时间可配置
            - 密码哈希算法使用 bcrypt
        """
        self.db = db
        self.secret_key = settings.JWT_SECRET_KEY
        self.algorithm = settings.JWT_ALGORITHM
        self.expire_minutes = settings.JWT_EXPIRE_MINUTES
        self.google_token_validator = GoogleTokenValidator()
        self.github_token_validator = GitHubTokenValidator()

        if not self.secret_key or self.secret_key == "your-jwt-secret-key-change-in-production":
            logger.warning("JWT_SECRET_KEY is not set properly! Using default insecure key.")

    async def login_with_provider(self, provider: str, token: str) -> Dict[str, Any]:
        """
        使用第三方提供商登录

        Args:
            provider: 认证提供者（apple, google, github, email）
            token: 第三方 Token 或验证码

        Returns:
            包含 access_token, token_type, user 的字典

        Raises:
            ProviderTokenError: 如果第三方 Token 验证失败
            AuthError: 如果认证过程出错

        注意：
            - 当前实现为 Mock，实际需要调用各平台的验证接口
            - Apple: 验证 identity_token（JWT）
            - Google: 验证 id_token（JWT）
            - GitHub: 验证 access_token
            - Email: 验证验证码（需要集成邮件服务）
        """
        try:
            # 验证第三方 Token（Mock 实现）
            user_info = await self._verify_provider_token(provider, token)

            # 查找或创建用户
            user = await self._find_or_create_user(provider, user_info)

            # 创建 JWT Token
            access_token = await self.create_access_token(str(user.id))

            # 创建 Refresh Token（对于第三方登录也需要）
            refresh_token, refresh_expires_at = await self.create_refresh_token(str(user.id))

            # 刷新用户对象，确保所有属性都已加载
            await self.db.refresh(user)

            logger.info(f"User {user.id} logged in successfully via {provider}")

            return {
                "access_token": access_token,
                "refresh_token": refresh_token,
                "token_type": "bearer",
                "expires_in": self.expire_minutes * 60,  # 转换为秒
                "user": user
            }

        except ProviderTokenError as e:
            logger.error(f"Provider token verification failed: {str(e)}")
            raise
        except Exception as e:
            logger.error(f"Login failed: {str(e)}")
            raise AuthError(f"Login failed: {str(e)}")

    async def get_current_user(self, token: str) -> User:
        """
        根据 JWT Token 获取当前用户

        Args:
            token: JWT Token 字符串

        Returns:
            用户对象

        Raises:
            InvalidTokenError: 如果 Token 无效或过期
            UserNotFoundError: 如果用户不存在
        """
        try:
            # 验证 Token 并获取用户 ID
            user_id = await self.verify_token(token)

            # 查询用户
            result = await self.db.execute(
                select(User).where(User.id == UUID(user_id))
            )
            user = result.scalar_one_or_none()

            if not user:
                logger.warning(f"User not found: {user_id}")
                raise UserNotFoundError("User not found")

            return user

        except InvalidTokenError:
            raise
        except UserNotFoundError:
            raise
        except Exception as e:
            logger.error(f"Failed to get current user: {str(e)}")
            raise AuthError(f"Failed to get current user: {str(e)}")

    async def create_access_token(self, user_id: str) -> str:
        """
        创建 JWT 访问令牌

        Args:
            user_id: 用户 ID（UUID 字符串）

        Returns:
            JWT Token 字符串

        注意：
            - Token 包含用户 ID 和过期时间
            - 使用 HS256 算法签名
            - 过期时间从配置读取
        """
        try:
            # 计算 Token 过期时间
            expire = datetime.now(timezone.utc) + timedelta(minutes=self.expire_minutes)

            # 创建 Token 载荷
            payload = {
                "sub": user_id,  # subject: 用户 ID
                "exp": expire,    # expiration time: 过期时间
                "iat": datetime.now(timezone.utc),  # issued at: 签发时间
                "type": "access"  # token type: 访问令牌
            }

            # 签发 Token
            token = jwt.encode(payload, self.secret_key, algorithm=self.algorithm)

            logger.debug(f"Access token created for user {user_id}")
            return token

        except Exception as e:
            logger.error(f"Failed to create access token: {str(e)}")
            raise AuthError(f"Failed to create access token: {str(e)}")

    async def verify_token(self, token: str) -> Optional[str]:
        """
        验证 JWT Token 并返回用户 ID

        Args:
            token: JWT Token 字符串

        Returns:
            用户 ID（UUID 字符串），如果 Token 无效则返回 None

        Raises:
            InvalidTokenError: 如果 Token 无效或过期

        注意：
            - 验证 Token 签名和过期时间
            - 返回 Token 中的用户 ID
        """
        try:
            # 解码并验证 Token
            payload = jwt.decode(
                token,
                self.secret_key,
                algorithms=[self.algorithm]
            )

            # 提取用户 ID
            user_id = payload.get("sub")

            if not user_id:
                logger.warning("Token does not contain user_id")
                raise InvalidTokenError("Token does not contain user_id")

            # 验证 Token 类型
            token_type = payload.get("type")
            if token_type != "access":
                logger.warning(f"Invalid token type: {token_type}")
                raise InvalidTokenError(f"Invalid token type: {token_type}")

            logger.debug(f"Token verified successfully for user {user_id}")
            return user_id

        except JWTError as e:
            logger.warning(f"JWT verification failed: {str(e)}")
            raise InvalidTokenError("Invalid or expired token")
        except Exception as e:
            logger.error(f"Token verification error: {str(e)}")
            raise InvalidTokenError(f"Token verification failed: {str(e)}")

    async def _verify_provider_token(self, provider: str, token: str) -> Dict[str, Any]:
        """
        验证第三方 Token

        Args:
            provider: 认证提供者
            token: 第三方 Token

        Returns:
            用户信息字典（email, username, provider_id 等）

        Raises:
            ProviderTokenError: 如果 Token 验证失败

        注意：
            - Google: 使用真实的 Google Token 验证
            - GitHub: 使用真实的 GitHub OAuth Token 验证
            - Apple: Mock 实现（需要集成 Apple API）
            - Email: 验证验证码（需要集成邮件服务）
        """
        # 验证 Token 格式
        if not token or len(token) < 10:
            raise ProviderTokenError("Invalid token format")

        # 根据不同的提供者验证 Token
        if provider == "google":
            # Google 登录：使用真实的 Token 验证
            try:
                logger.info("Validating Google ID Token...")
                user_info = await self.google_token_validator.validate_token(
                    id_token=token,
                    client_id=settings.GOOGLE_CLIENT_ID
                )

                # 验证邮箱是否已验证
                if not user_info.get("email_verified", False):
                    raise ProviderTokenError("Email is not verified")

                logger.info(f"Google ID Token validated successfully for email: {user_info.get('email')}")
                return user_info

            except GoogleTokenValidationError as e:
                logger.error(f"Google Token validation failed: {str(e)}")
                raise ProviderTokenError(f"Google Token validation failed: {str(e)}")
            except Exception as e:
                logger.error(f"Unexpected error validating Google Token: {str(e)}")
                raise ProviderTokenError(f"Unexpected error: {str(e)}")

        elif provider == "apple":
            # Apple 登录 Mock（需要集成 Apple API）
            return {
                "email": f"user_{token[:8]}@icloud.com",
                "username": f"AppleUser_{token[:8]}",
                "provider_id": token[:32],
                "avatar_url": None
            }
        elif provider == "github":
            # GitHub 登录：使用真实的 Token 验证
            try:
                logger.info("Validating GitHub Access Token...")
                user_info = await self.github_token_validator.validate_token(
                    access_token=token,
                    client_id=settings.GITHUB_CLIENT_ID,
                    client_secret=settings.GITHUB_CLIENT_SECRET
                )

                logger.info(
                    f"GitHub Access Token validated successfully for user: "
                    f"{user_info.get('username')} ({user_info.get('email')})"
                )
                return user_info

            except GitHubTokenValidationError as e:
                logger.error(f"GitHub Token validation failed: {str(e)}")
                raise ProviderTokenError(f"GitHub Token validation failed: {str(e)}")
            except Exception as e:
                logger.error(f"Unexpected error validating GitHub Token: {str(e)}")
                raise ProviderTokenError(f"Unexpected error: {str(e)}")
        elif provider == "email":
            # 邮箱登录 Mock（需要集成邮件服务）
            return {
                "email": f"user_{token[:8]}@example.com",
                "username": f"EmailUser_{token[:8]}",
                "provider_id": None,
                "avatar_url": None
            }
        else:
            raise ProviderTokenError(f"Unsupported provider: {provider}")

    async def _find_or_create_user(self, provider: str, user_info: Dict[str, Any]) -> User:
        """
        查找或创建用户

        Args:
            provider: 认证提供者
            user_info: 用户信息字典

        Returns:
            用户对象

        注意：
            - 如果 provider_id 存在，根据 provider_id 查找用户
            - 如果用户不存在，创建新用户
            - 返回用户对象
        """
        try:
            # 尝试根据 provider_id 查找用户
            if user_info.get("provider_id"):
                result = await self.db.execute(
                    select(User).where(
                        User.auth_provider == provider,
                        User.provider_id == user_info["provider_id"]
                    )
                )
                user = result.scalar_one_or_none()

                if user:
                    logger.debug(f"Found existing user: {user.id}")
                    return user

            # 尝试根据 email 查找用户
            result = await self.db.execute(
                select(User).where(User.email == user_info["email"])
            )
            user = result.scalar_one_or_none()

            if user:
                logger.debug(f"Found existing user by email: {user.id}")
                return user

            # 创建新用户
            user_data = UserCreate(
                email=user_info["email"],
                username=user_info.get("username"),
                auth_provider=provider,
                provider_id=user_info.get("provider_id"),
                avatar_url=user_info.get("avatar_url")
            )

            new_user = User(**user_data.model_dump())
            self.db.add(new_user)
            await self.db.commit()
            await self.db.refresh(new_user)

            logger.info(f"Created new user: {new_user.id}")
            return new_user

        except Exception as e:
            logger.error(f"Failed to find or create user: {str(e)}")
            await self.db.rollback()
            raise AuthError(f"Failed to find or create user: {str(e)}")

    @staticmethod
    def hash_password(password: str) -> str:
        """
        哈希密码（使用 bcrypt）

        Args:
            password: 明文密码

        Returns:
            哈希后的密码

        注意：
            - 使用 bcrypt 算法
            - 自动生成 salt
        """
        password_bytes = password.encode('utf-8')
        salt = bcrypt.gensalt()
        hashed = bcrypt.hashpw(password_bytes, salt)
        return hashed.decode('utf-8')

    @staticmethod
    def verify_password(plain_password: str, hashed_password: str) -> bool:
        """
        验证密码

        Args:
            plain_password: 明文密码
            hashed_password: 哈希后的密码

        Returns:
            True 如果密码正确，False 如果密码错误
        """
        password_bytes = plain_password.encode('utf-8')
        hashed_bytes = hashed_password.encode('utf-8')
        return bcrypt.checkpw(password_bytes, hashed_bytes)

    async def send_verification_code(self, email: str, redis_client) -> str:
        """
        发送验证码到邮箱

        Args:
            email: 邮箱地址
            redis_client: Redis 客户端

        Returns:
            验证码

        Raises:
            AuthError: 如果发送失败
        """
        import random

        # 检查发送频率限制（1分钟内只能发送一次）
        rate_limit_key = f"email_rate_limit:{email}"
        if await redis_client.exists(rate_limit_key):
            raise AuthError("Verification code already sent, please wait")

        # 生成 6 位数字验证码
        code = str(random.randint(100000, 999999))

        # 存储验证码到 Redis（5分钟过期）
        verification_key = f"email_verification:{email}"
        await redis_client.setex(verification_key, 300, code)

        # 设置发送频率限制（1分钟）
        await redis_client.setex(rate_limit_key, 60, "1")

        # 发送邮件
        from app.services.email_service import EmailService

        email_service = EmailService(
            host=settings.SMTP_HOST,
            port=settings.SMTP_PORT,
            username=settings.SMTP_USERNAME,
            password=settings.SMTP_PASSWORD,
            use_tls=settings.SMTP_USE_TLS
        )

        await email_service.send_verification_code(email, code)

        logger.info(f"Verification code sent to {email}")
        return code

    async def create_refresh_token(self, user_id: str) -> tuple[str, datetime]:
        """
        创建 Refresh Token

        Args:
            user_id: 用户 ID

        Returns:
            (refresh_token, expires_at)

        Raises:
            AuthError: 如果创建失败
        """
        import secrets
        from sqlalchemy import update

        # 生成随机 Refresh Token
        refresh_token = secrets.token_urlsafe(64)

        # 设置过期时间（30天后）
        expires_at = datetime.now(timezone.utc) + timedelta(days=30)

        # 更新用户记录
        await self.db.execute(
            update(User).where(User.id == UUID(user_id)).values(
                refresh_token=refresh_token,
                refresh_token_expires_at=expires_at
            )
        )
        await self.db.commit()

        logger.info(f"Refresh token created for user {user_id}")
        return refresh_token, expires_at

    async def verify_email_code(self, email: str, code: str, redis_client) -> tuple[User, str, datetime]:
        """
        验证邮箱验证码并登录

        Args:
            email: 邮箱地址
            code: 验证码
            redis_client: Redis 客户端

        Returns:
            (用户对象, refresh_token, expires_at)

        Raises:
            AuthError: 如果验证失败
        """
        # 从 Redis 获取验证码
        verification_key = f"email_verification:{email}"
        stored_code = await redis_client.get(verification_key)

        if not stored_code:
            raise AuthError("Verification code expired or not found")

        if stored_code != code:
            raise AuthError("Invalid verification code")

        # 验证成功，删除验证码
        await redis_client.delete(verification_key)

        # 查找或创建用户
        result = await self.db.execute(
            select(User).where(User.email == email)
        )
        user = result.scalar_one_or_none()

        if not user:
            # 创建新用户
            user_data = UserCreate(
                email=email,
                username=email.split("@")[0],
                auth_provider="email",
                provider_id=None,
                avatar_url=None
            )

            new_user = User(**user_data.model_dump())
            self.db.add(new_user)
            await self.db.commit()
            await self.db.refresh(new_user)

            logger.info(f"Created new user: {new_user.id}")
            user = new_user

        # 创建 Refresh Token
        refresh_token, expires_at = await self.create_refresh_token(str(user.id))

        # 刷新用户对象，确保所有属性都已加载
        await self.db.refresh(user)

        logger.info(f"User {user.id} logged in via email verification")
        return user, refresh_token, expires_at

    async def refresh_access_token(self, refresh_token: str) -> tuple[str, datetime, User]:
        """
        使用 Refresh Token 刷新 Access Token

        Args:
            refresh_token: Refresh Token

        Returns:
            (access_token, expires_at, user)

        Raises:
            AuthError: 如果刷新失败
        """
        # 查找用户
        result = await self.db.execute(
            select(User).where(User.refresh_token == refresh_token)
        )
        user = result.scalar_one_or_none()

        if not user:
            raise AuthError("Invalid refresh token")

        # 检查 Refresh Token 是否过期
        if user.refresh_token_expires_at and user.refresh_token_expires_at < datetime.now(timezone.utc):
            raise AuthError("Refresh token expired")

        # 创建新的 Access Token
        access_token = await self.create_access_token(str(user.id))
        expires_at = datetime.now(timezone.utc) + timedelta(minutes=self.expire_minutes)

        logger.info(f"Access token refreshed for user {user.id}")
        return access_token, expires_at, user