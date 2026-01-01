"""
Google ID Token 验证服务

使用 Google 官方推荐的 google-auth 库验证 Google ID Token。

功能特性：
- 自动验证 Token 签名
- 自动验证 Token 声明（issuer, audience, exp 等）
- 提取用户信息（email, name, picture 等）

使用方法：
    validator = GoogleTokenValidator()
    user_info = await validator.validate_token(id_token, client_id)
"""

import logging
from typing import Dict, Any

from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests


logger = logging.getLogger(__name__)


class GoogleTokenValidationError(Exception):
    """Google Token 验证失败异常"""
    pass


class GoogleTokenValidator:
    """
    Google ID Token 验证器

    使用 Google 官方的 google-auth 库验证 ID Token。

    使用方法：
        validator = GoogleTokenValidator()
        user_info = await validator.validate_token(id_token, client_id)
    """

    def __init__(self):
        """初始化 Google Token 验证器"""
        logger.info("GoogleTokenValidator initialized")

    async def validate_token(self, id_token: str, client_id: str) -> Dict[str, Any]:
        """
        验证 Google ID Token 并提取用户信息

        Args:
            id_token: Google ID Token（JWT 字符串）
            client_id: Google OAuth 客户端 ID

        Returns:
            用户信息字典（email, name, picture, sub 等）

        Raises:
            GoogleTokenValidationError: 如果 Token 验证失败

        注意：
            - 自动验证 Token 签名
            - 自动验证 Token 声明（issuer, audience, exp 等）
            - 提取用户信息
        """
        if not id_token:
            raise GoogleTokenValidationError("ID Token is empty")

        if not client_id:
            raise GoogleTokenValidationError("Client ID is empty")

        try:
            logger.info("Validating Google ID Token...")

            # 使用 Google 官方库验证 Token
            # 这个方法会自动：
            # 1. 验证签名（使用 Google 的公钥）
            # 2. 验证 issuer（必须是 accounts.google.com 或 https://accounts.google.com）
            # 3. 验证 audience（必须匹配 client_id）
            # 4. 验证过期时间
            id_info = google_id_token.verify_oauth2_token(
                id_token,
                google_requests.Request(),
                client_id
            )

            # 提取用户信息
            user_info = {
                "email": id_info.get("email"),
                "username": id_info.get("name"),
                "provider_id": id_info.get("sub"),
                "avatar_url": id_info.get("picture"),
                "email_verified": id_info.get("email_verified", False)
            }

            logger.info(f"Successfully validated Google ID Token for email: {user_info.get('email')}")
            return user_info

        except ValueError as e:
            logger.error(f"Invalid Google ID Token: {e}")
            raise GoogleTokenValidationError(f"Invalid token: {str(e)}")
        except Exception as e:
            logger.error(f"Unexpected error validating Google ID Token: {e}")
            raise GoogleTokenValidationError(f"Unexpected error: {str(e)}")