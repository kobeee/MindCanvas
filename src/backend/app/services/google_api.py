"""
Google API 客户端模块

提供 Google Nano Banana Pro API (Gemini 2.0 Flash) 的异步调用功能，
支持文本到图片生成和图片到图片生成。

安全特性：
- 使用 httpx 异步 HTTP 客户端
- 设置合理的超时时间（60秒）
- 完善的错误处理
- 日志中不泄露 API Key
"""

import httpx
import base64
import logging
from typing import Optional

logger = logging.getLogger(__name__)


class GoogleAPIError(Exception):
    """Google API 异常基类"""
    pass


class InvalidAPIKeyError(GoogleAPIError):
    """无效 API Key 异常"""
    pass


class RateLimitError(GoogleAPIError):
    """速率限制异常"""
    pass


class InvalidRequestError(GoogleAPIError):
    """无效请求异常"""
    pass


class InternalServerError(GoogleAPIError):
    """Google API 内部错误"""
    pass


class GoogleAPIClient:
    """
    Google API 客户端类

    使用 httpx 异步 HTTP 客户端调用 Google Nano Banana Pro API (Gemini 2.0 Flash)，
    支持文本到图片生成和图片到图片生成。

    使用方法：
        # 初始化客户端
        google_client = GoogleAPIClient()

        # 文本到图片生成
        image_data = await google_client.generate_image(
            api_key="your_api_key",
            prompt="A beautiful sunset"
        )

        # 图片到图片生成
        image_data = await google_client.generate_image(
            api_key="your_api_key",
            prompt="Make this image more colorful",
            base_image="base64_encoded_image"
        )

        # 保存图片
        with open("output.png", "wb") as f:
            f.write(image_data)
    """

    def __init__(self, timeout: float = 60.0):
        """
        初始化 Google API 客户端

        Args:
            timeout: 请求超时时间（秒），默认 60 秒

        注意：
            - 使用 httpx.AsyncClient 进行异步 HTTP 请求
            - 超时时间设置为 60 秒，适用于生图任务
        """
        self.base_url = "https://generativelanguage.googleapis.com/v1beta"
        self.model_name = "gemini-2.0-flash-exp"
        self.timeout = timeout
        logger.info(f"GoogleAPIClient initialized with timeout={timeout}s")

    async def generate_image(
        self,
        api_key: str,
        prompt: str,
        base_image: Optional[str] = None
    ) -> bytes:
        """
        调用 Google Nano Banana Pro API 生成图片

        Args:
            api_key: Google API Key（不记录在日志中）
            prompt: 提示词（描述要生成的图片）
            base_image: 参考图的 Base64 编码字符串（可选，用于图片到图片生成）

        Returns:
            图片二进制数据（PNG 格式）

        Raises:
            InvalidAPIKeyError: 如果 API Key 无效
            RateLimitError: 如果超过速率限制
            InvalidRequestError: 如果请求参数无效
            InternalServerError: 如果 Google API 内部错误
            GoogleAPIError: 其他 Google API 错误

        注意：
            - 如果提供 base_image，则执行图片到图片生成
            - 如果不提供 base_image，则执行文本到图片生成
            - API Key 不会记录在日志中
            - 超时时间为 60 秒
            - 返回的图片为 PNG 格式
        """
        if not api_key:
            logger.error("API Key is empty")
            raise InvalidAPIKeyError("API Key is required")

        if not prompt:
            logger.error("Prompt is empty")
            raise InvalidRequestError("Prompt is required")

        # 构建 API URL
        url = f"{self.base_url}/models/{self.model_name}:generateContent?key={api_key}"

        # 构建请求体
        payload = self._build_request_payload(prompt, base_image)

        logger.info(f"Generating image with prompt length={len(prompt)}, base_image={'yes' if base_image else 'no'}")

        try:
            # 发送异步 HTTP 请求
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(
                    url,
                    json=payload,
                    headers={
                        "Content-Type": "application/json"
                    }
                )

                # 检查 HTTP 状态码
                if response.status_code == 401:
                    logger.error("Google API returned 401 Unauthorized")
                    raise InvalidAPIKeyError("Invalid API Key")

                elif response.status_code == 429:
                    logger.error("Google API returned 429 Rate Limit Exceeded")
                    raise RateLimitError("Rate limit exceeded, please try again later")

                elif response.status_code == 400:
                    logger.error(f"Google API returned 400 Bad Request: {response.text}")
                    raise InvalidRequestError(f"Invalid request: {response.text}")

                elif response.status_code >= 500:
                    logger.error(f"Google API returned {response.status_code}: {response.text}")
                    raise InternalServerError(f"Google API internal error: {response.status_code}")

                # 检查响应是否成功
                response.raise_for_status()

                # 解析响应
                data = response.json()

                # 提取图片数据
                image_data = self._extract_image_data(data)

                logger.info("Image generated successfully")
                return image_data

        except httpx.TimeoutException:
            logger.error(f"Request timed out after {self.timeout}s")
            raise GoogleAPIError(f"Request timed out after {self.timeout}s")

        except httpx.HTTPStatusError as e:
            logger.error(f"HTTP error occurred: {e}")
            raise GoogleAPIError(f"HTTP error: {str(e)}")

        except httpx.RequestError as e:
            logger.error(f"Request error occurred: {e}")
            raise GoogleAPIError(f"Request error: {str(e)}")

        except Exception as e:
            logger.error(f"Unexpected error occurred: {e}")
            raise GoogleAPIError(f"Unexpected error: {str(e)}")

    def _build_request_payload(
        self,
        prompt: str,
        base_image: Optional[str] = None
    ) -> dict:
        """
        构建请求体

        Args:
            prompt: 提示词
            base_image: 参考图的 Base64 编码字符串（可选）

        Returns:
            请求体字典
        """
        # 构建基础请求体
        payload = {
            "contents": [{
                "parts": [{"text": prompt}]
            }]
        }

        # 如果有参考图，添加到请求体
        if base_image:
            # 验证 base_image 是否为有效的 Base64 字符串
            try:
                # 尝试解码以验证 Base64 格式
                base64.b64decode(base_image, validate=True)
                payload["contents"][0]["parts"].append({
                    "inline_data": {
                        "mime_type": "image/png",
                        "data": base_image
                    }
                })
                logger.debug("Base image added to request payload")
            except Exception as e:
                logger.error(f"Invalid base64 image data: {e}")
                raise InvalidRequestError("Invalid base64 image data")

        return payload

    def _extract_image_data(self, response_data: dict) -> bytes:
        """
        从 API 响应中提取图片数据

        Args:
            response_data: API 响应数据

        Returns:
            图片二进制数据

        Raises:
            GoogleAPIError: 如果响应格式无效或无法提取图片数据
        """
        try:
            # 检查响应结构
            if "candidates" not in response_data or not response_data["candidates"]:
                logger.error("No candidates in response")
                raise GoogleAPIError("No candidates in response")

            candidate = response_data["candidates"][0]

            if "content" not in candidate:
                logger.error("No content in candidate")
                raise GoogleAPIError("No content in candidate")

            content = candidate["content"]

            if "parts" not in content or not content["parts"]:
                logger.error("No parts in content")
                raise GoogleAPIError("No parts in content")

            part = content["parts"][0]

            if "inline_data" not in part:
                logger.error("No inline_data in part")
                raise GoogleAPIError("No inline_data in part")

            inline_data = part["inline_data"]

            if "data" not in inline_data:
                logger.error("No data in inline_data")
                raise GoogleAPIError("No data in inline_data")

            # 提取 Base64 图片数据
            image_base64 = inline_data["data"]

            # 解码为二进制数据
            image_data = base64.b64decode(image_base64)

            logger.debug(f"Image data extracted: {len(image_data)} bytes")
            return image_data

        except Exception as e:
            logger.error(f"Failed to extract image data from response: {e}")
            raise GoogleAPIError(f"Failed to extract image data: {str(e)}")

    async def validate_api_key(self, api_key: str) -> bool:
        """
        验证 API Key 是否有效

        Args:
            api_key: Google API Key

        Returns:
            True 如果 API Key 有效，False 如果无效

        注意：
            - 此方法发送一个最小化的请求来验证 API Key
            - 不会消耗 API 配额（或消耗极少）
        """
        try:
            # 使用一个简单的提示词进行验证
            await self.generate_image(
                api_key=api_key,
                prompt="test"
            )
            return True
        except InvalidAPIKeyError:
            logger.warning("API Key validation failed: Invalid API Key")
            return False
        except Exception as e:
            logger.warning(f"API Key validation failed: {e}")
            return False