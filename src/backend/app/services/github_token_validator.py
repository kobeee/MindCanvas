"""
GitHub OAuth Token 验证服务

使用 GitHub OAuth API 验证 Access Token 并获取用户信息。

功能特性：
- 使用 GitHub API 验证 Access Token
- 获取用户基本信息（email, login, avatar_url 等）
- 支持获取用户公开邮箱

使用方法：
    validator = GitHubTokenValidator()
    user_info = await validator.validate_token(access_token, client_id, client_secret)
"""

import logging
from typing import Dict, Any, Optional

import httpx


logger = logging.getLogger(__name__)


class GitHubTokenValidationError(Exception):
    """GitHub Token 验证失败异常"""
    pass


class GitHubTokenValidator:
    """
    GitHub OAuth Access Token 验证器

    使用 GitHub API 验证 Access Token 并获取用户信息。

    使用方法：
        validator = GitHubTokenValidator()
        user_info = await validator.validate_token(access_token, client_id, client_secret)

    GitHub API 文档：
    - https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps
    - https://docs.github.com/en/rest/users/users#get-the-authenticated-user
    """

    def __init__(self):
        """初始化 GitHub Token 验证器"""
        self.user_api_url = "https://api.github.com/user"
        self.user_emails_url = "https://api.github.com/user/emails"
        logger.info("GitHubTokenValidator initialized")

    async def validate_token(
        self,
        access_token: str,
        client_id: str,
        client_secret: str
    ) -> Dict[str, Any]:
        """
        验证 GitHub Access Token 并获取用户信息

        Args:
            access_token: GitHub OAuth Access Token
            client_id: GitHub OAuth 客户端 ID（用于验证）
            client_secret: GitHub OAuth 客户端密钥（用于验证）

        Returns:
            用户信息字典（email, username, provider_id, avatar_url 等）

        Raises:
            GitHubTokenValidationError: 如果 Token 验证失败

        注意：
            - 使用 access_token 调用 GitHub API
            - 自动验证 Token 有效性
            - 获取用户公开信息
        """
        if not access_token:
            raise GitHubTokenValidationError("Access Token is empty")

        if not client_id:
            raise GitHubTokenValidationError("Client ID is empty")

        if not client_secret:
            raise GitHubTokenValidationError("Client Secret is empty")

        try:
            logger.info("Validating GitHub Access Token...")

            # 使用 access_token 获取用户信息
            async with httpx.AsyncClient() as client:
                # 1. 获取用户基本信息
                user_response = await client.get(
                    self.user_api_url,
                    headers={
                        "Authorization": f"Bearer {access_token}",
                        "Accept": "application/vnd.github+json",
                        "X-GitHub-Api-Version": "2022-11-28"
                    },
                    timeout=10.0
                )

                if user_response.status_code != 200:
                    logger.error(f"GitHub API error: {user_response.status_code} - {user_response.text}")
                    raise GitHubTokenValidationError(
                        f"Failed to get user info: {user_response.status_code}"
                    )

                user_data = user_response.json()

                # 提取用户信息
                username = user_data.get("login") or user_data.get("name")
                provider_id = str(user_data.get("id"))
                avatar_url = user_data.get("avatar_url")
                email = user_data.get("email")

                # 2. 如果用户邮箱为 None，尝试获取公开邮箱列表
                if not email:
                    logger.debug(f"Email not public for user {username}, fetching email list...")
                    email = await self._fetch_user_email(
                        client, access_token, client_id, client_secret
                    )

                # 3. 判断邮箱是否已验证
                email_verified = True  # GitHub 公开邮箱都是已验证的

                user_info = {
                    "email": email,
                    "username": username,
                    "provider_id": provider_id,
                    "avatar_url": avatar_url,
                    "email_verified": email_verified
                }

                logger.info(
                    f"Successfully validated GitHub Access Token for user: "
                    f"{username} ({email})"
                )
                return user_info

        except GitHubTokenValidationError:
            raise
        except httpx.TimeoutException as e:
            logger.error(f"GitHub API timeout: {str(e)}")
            raise GitHubTokenValidationError(f"Request timeout: {str(e)}")
        except httpx.HTTPError as e:
            logger.error(f"GitHub API error: {str(e)}")
            raise GitHubTokenValidationError(f"API error: {str(e)}")
        except Exception as e:
            logger.error(f"Unexpected error validating GitHub Access Token: {e}")
            raise GitHubTokenValidationError(f"Unexpected error: {str(e)}")

    async def _fetch_user_email(
        self,
        client: httpx.AsyncClient,
        access_token: str,
        client_id: str,
        client_secret: str
    ) -> Optional[str]:
        """
        获取用户公开邮箱列表

        Args:
            client: HTTP 客户端
            access_token: GitHub Access Token
            client_id: GitHub Client ID
            client_secret: GitHub Client Secret

        Returns:
            用户邮箱，如果获取失败返回 None
        """
        try:
            emails_response = await client.get(
                self.user_emails_url,
                headers={
                    "Authorization": f"Bearer {access_token}",
                    "Accept": "application/vnd.github+json",
                    "X-GitHub-Api-Version": "2022-11-28"
                },
                timeout=10.0
            )

            if emails_response.status_code != 200:
                logger.warning(f"Failed to fetch user emails: {emails_response.status_code}")
                return None

            emails = emails_response.json()

            # 查找已验证的公开邮箱
            for email_info in emails:
                if email_info.get("email") and email_info.get("verified"):
                    logger.debug(f"Found verified email: {email_info['email']}")
                    return email_info["email"]

            logger.warning("No verified email found for user")
            return None

        except Exception as e:
            logger.error(f"Error fetching user emails: {e}")
            return None

    async def verify_token_simple(
        self,
        access_token: str,
        client_id: str,
        client_secret: str
    ) -> bool:
        """
        简单验证 Token 是否有效

        Args:
            access_token: GitHub Access Token
            client_id: GitHub Client ID
            client_secret: GitHub Client Secret

        Returns:
            True 如果 Token 有效，False 如果无效
        """
        try:
            await self.validate_token(access_token, client_id, client_secret)
            return True
        except GitHubTokenValidationError:
            return False
