"""
Laozhang API 客户端模块

提供 Laozhang API 的异步调用功能，支持文本到图片生成和图片到图片生成。
"""

import httpx
import base64
import logging
from typing import Optional

logger = logging.getLogger(__name__)


class LaozhangAPIError(Exception):
    """Laozhang API 异常基类"""
    pass


class LaozhangAPIClient:
    """
    Laozhang API 客户端类

    使用 httpx 异步 HTTP 客户端调用 Laozhang API，
    支持文本到图片生成和图片到图片生成。

    API 文档：https://api.laozhang.ai/v1beta/models/gemini-3-pro-image-preview:generateContent

    特性：
    - 支持 1K, 2K, 4K 分辨率
    - 默认使用 2K 分辨率
    - 支持文生图和图生图
    """

    def __init__(self, timeout: float = 180.0):
        """
        初始化 Laozhang API 客户端

        Args:
            timeout: 请求超时时间（秒），默认 180 秒
        """
        self.base_url = "https://api.laozhang.ai/v1beta"
        self.model_name = "gemini-3-pro-image-preview"
        self.timeout = timeout
        logger.info(f"LaozhangAPIClient initialized with model={self.model_name}, timeout={timeout}s")

    async def generate_image(
        self,
        api_key: str,
        prompt: str,
        base_image: Optional[str] = None,
        image_size: str = "2K"
    ) -> bytes:
        """
        调用 Laozhang API 生成图片

        Args:
            api_key: Laozhang API Key
            prompt: 提示词
            base_image: 参考图的 Base64 编码（可选）
            image_size: 图片尺寸（1K, 2K, 4K），默认 2K

        Returns:
            图片二进制数据（PNG 格式）

        Raises:
            LaozhangAPIError: 如果 API 调用失败
        """
        if not api_key:
            logger.error("API Key is empty")
            raise LaozhangAPIError("API Key is required")

        if not prompt:
            logger.error("Prompt is empty")
            raise LaozhangAPIError("Prompt is required")

        # 构建 API URL
        url = f"{self.base_url}/models/{self.model_name}:generateContent"

        # 构建请求头
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }

        # 构建请求体
        payload = self._build_request_payload(prompt, base_image, image_size)

        logger.info(f"Generating image with prompt length={len(prompt)}, base_image={'yes' if base_image else 'no'}, image_size={image_size}")

        try:
            # 发送异步 HTTP 请求
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.post(url, headers=headers, json=payload)

                # 检查 HTTP 状态码
                if response.status_code == 401:
                    logger.error("Laozhang API returned 401 Unauthorized")
                    raise LaozhangAPIError("Invalid API Key")

                elif response.status_code == 429:
                    logger.error("Laozhang API returned 429 Rate Limit Exceeded")
                    raise LaozhangAPIError("Rate limit exceeded, please try again later")

                elif response.status_code == 400:
                    logger.error(f"Laozhang API returned 400 Bad Request: {response.text}")
                    raise LaozhangAPIError(f"Invalid request: {response.text}")

                elif response.status_code >= 500:
                    logger.error(f"Laozhang API returned {response.status_code}: {response.text}")
                    raise LaozhangAPIError(f"Laozhang API internal error: {response.status_code}")

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
            raise LaozhangAPIError(f"Request timed out after {self.timeout}s")

        except httpx.HTTPStatusError as e:
            logger.error(f"HTTP error occurred: {e}")
            raise LaozhangAPIError(f"HTTP error: {str(e)}")

        except httpx.RequestError as e:
            logger.error(f"Request error occurred: {e}")
            raise LaozhangAPIError(f"Request error: {str(e)}")

        except LaozhangAPIError:
            raise

        except Exception as e:
            logger.error(f"Unexpected error occurred: {e}")
            raise LaozhangAPIError(f"Unexpected error: {str(e)}")

    def _build_request_payload(
        self,
        prompt: str,
        base_image: Optional[str],
        image_size: str
    ) -> dict:
        """
        构建请求体

        Args:
            prompt: 提示词
            base_image: 参考图的 Base64 编码
            image_size: 图片尺寸

        Returns:
            请求体字典
        """
        payload = {
            "contents": [{
                "parts": [{"text": prompt}]
            }],
            "generationConfig": {
                "responseModalities": ["IMAGE"],
                "imageConfig": {
                    "aspectRatio": "1:1",
                    "imageSize": image_size
                }
            }
        }

        # 如果有参考图，添加到请求体
        if base_image:
            try:
                # 验证 base_image 是否为有效的 Base64 字符串
                base64.b64decode(base_image, validate=True)
                payload["contents"][0]["parts"].append({
                    "inlineData": {
                        "mime_type": "image/jpeg",
                        "data": base_image
                    }
                })
                logger.debug("Base image added to request payload")
            except Exception as e:
                logger.error(f"Invalid base64 image data: {e}")
                raise LaozhangAPIError("Invalid base64 image data")

        return payload

    def _extract_image_data(self, response_data: dict) -> bytes:
        """
        从 API 响应中提取图片数据

        Args:
            response_data: API 响应数据

        Returns:
            图片二进制数据

        Raises:
            LaozhangAPIError: 如果响应格式无效或无法提取图片数据
        """
        try:
            # 检查响应结构
            if "candidates" not in response_data or not response_data["candidates"]:
                logger.error("No candidates in response")
                raise LaozhangAPIError("No candidates in response")

            candidate = response_data["candidates"][0]

            if "content" not in candidate:
                logger.error("No content in candidate")
                raise LaozhangAPIError("No content in candidate")

            content = candidate["content"]

            if "parts" not in content or not content["parts"]:
                logger.error("No parts in content")
                raise LaozhangAPIError("No parts in content")

            parts = content["parts"]

            # 遍历所有 parts，找到包含 inlineData 的 part
            image_base64 = None
            for part in parts:
                if "inlineData" in part:
                    inline_data = part["inlineData"]
                    if "data" in inline_data:
                        image_base64 = inline_data["data"]
                        logger.info("Found inlineData in response")
                        break

            if image_base64 is None:
                logger.error("No inlineData found in response")
                raise LaozhangAPIError("No image data in response")

            # 解码为二进制数据
            image_data = base64.b64decode(image_base64)

            logger.debug(f"Image data extracted: {len(image_data)} bytes")
            return image_data

        except LaozhangAPIError:
            raise

        except Exception as e:
            logger.error(f"Failed to extract image data from response: {e}")
            raise LaozhangAPIError(f"Failed to extract image data: {str(e)}")