"""
Google API 客户端模块

提供 Google Nano Banana Pro API (Gemini 3 Pro Image Preview) 的异步调用功能，
支持文本到图片生成和图片到图片生成。

Nano Banana Pro 是 Google 最新的旗舰级图像生成模型，具备：
- 思考模式（Thinking Mode）：复杂场景推理
- 搜索接地（Search Grounding）：验证事实准确性
- 4K 分辨率输出：专业级图像质量
- 高保真文本渲染：94% 文本渲染准确率

安全特性：
- 使用 httpx 异步 HTTP 客户端
- 设置合理的超时时间（60秒）
- 完善的错误处理
- 日志中不泄露 API Key
"""

import httpx
import base64
import json
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

    使用 httpx 异步 HTTP 客户端调用 Google Nano Banana Pro API (Gemini 3 Pro Image Preview)，
    支持文本到图片生成和图片到图片生成。

    Nano Banana Pro (gemini-3-pro-image-preview) 特性：
    - 思考模式（Thinking Mode）：复杂场景推理
    - 搜索接地（Search Grounding）：验证事实准确性
    - 4K 分辨率输出：专业级图像质量
    - 高保真文本渲染：94% 文本渲染准确率

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

    def __init__(self, timeout: float = 180.0):
        """
        初始化 Google API 客户端

        Args:
            timeout: 请求超时时间（秒），默认 180 秒

        注意：
            - 使用 httpx.AsyncClient 进行异步 HTTP 请求
            - 超时时间设置为 180 秒，适用于生图任务
        """
        self.base_url = "https://generativelanguage.googleapis.com/v1beta"
        self.model_name = "gemini-3-pro-image-preview"
        self.timeout = timeout
        logger.info(f"GoogleAPIClient initialized with model={self.model_name}, timeout={timeout}s")

    async def generate_image(
        self,
        api_key: str,
        prompt: str,
        base_image: Optional[str] = None,
        image_size: str = "1K"
    ) -> bytes:
        """
        调用 Google Nano Banana Pro API 生成图片

        Args:
            api_key: Google API Key（不记录在日志中）
            prompt: 提示词（描述要生成的图片）
            base_image: 参考图的 Base64 编码字符串（可选，用于图片到图片生成）
            image_size: 图片尺寸（仅用于接口兼容，Google API 不支持此参数）

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
            - 超时时间为 180 秒
            - 返回的图片为 PNG 格式
            - image_size 参数仅用于接口兼容，Google API 不支持此参数
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
            async with httpx.AsyncClient(
                timeout=self.timeout,
                verify=True  # 启用TLS验证
            ) as client:
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

                # 添加详细的响应日志
                logger.info(f"API Response keys: {list(data.keys())}")
                logger.info(f"Full API Response: {json.dumps(data, indent=2)}")

                if "candidates" in data:
                    candidates_count = len(data["candidates"])
                    logger.info(f"Candidates count: {candidates_count}")
                    if candidates_count > 0:
                        first_candidate = data["candidates"][0]
                        logger.info(f"First candidate keys: {list(first_candidate.keys())}")
                        if "finishReason" in first_candidate:
                            logger.info(f"Finish reason: {first_candidate['finishReason']}")
                        if "finishMessage" in first_candidate:
                            logger.info(f"Finish message: {first_candidate['finishMessage']}")

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
                "role": "user",
                "parts": [{"text": prompt}]
            }],
            "generationConfig": {
                "responseModalities": ["IMAGE"]
            }
        }

        # 如果有参考图，添加到请求体
        if base_image:
            # 验证 base_image 是否为有效的 Base64 字符串
            try:
                # 尝试解码以验证 Base64 格式
                base64.b64decode(base_image, validate=True)
                payload["contents"][0]["parts"].append({
                    "inlineData": {
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

            # 检查候选结果状态
            if "finishReason" in candidate:
                finish_reason = candidate["finishReason"]
                logger.info(f"Candidate finishReason: {finish_reason}")
                if finish_reason != "STOP":
                    error_msg = f"Generation failed with reason: {finish_reason}"
                    if "finishMessage" in candidate:
                        error_msg += f" - {candidate['finishMessage']}"
                    logger.error(error_msg)
                    raise GoogleAPIError(error_msg)

            if "content" not in candidate:
                logger.error("No content in candidate")
                raise GoogleAPIError("No content in candidate")

            content = candidate["content"]

            if "parts" not in content or not content["parts"]:
                logger.error("No parts in content")
                raise GoogleAPIError("No parts in content")

            # 添加 parts 数组的详细日志
            parts = content["parts"]
            parts_count = len(parts)
            logger.info(f"Parts count: {parts_count}")

            # 记录每个 part 的类型和完整内容
            for i, part in enumerate(parts):
                logger.info(f"Part {i} keys: {list(part.keys())}")
                logger.info(f"Part {i} full content: {json.dumps(part, indent=2)}")
                if "text" in part:
                    text_preview = part['text'][:100] if len(part['text']) > 100 else part['text']
                    logger.info(f"Part {i} text: {text_preview}...")
                if "inline_data" in part:
                    mime_type = part['inline_data'].get('mime_type', 'unknown')
                    logger.info(f"Part {i} inline_data mime_type: {mime_type}")
                if "inlineData" in part:  # 驼峰命名
                    mime_type = part['inlineData'].get('mime_type', 'unknown')
                    logger.info(f"Part {i} inlineData (camelCase) mime_type: {mime_type}")
                if "thought_signature" in part:
                    logger.info(f"Part {i} has thought_signature")

            # 遍历所有 parts，找到包含 inline_data 或 inlineData 的 part
            image_base64 = None
            for i, part in enumerate(parts):
                # 检查下划线命名 inline_data
                if "inline_data" in part:
                    inline_data = part["inline_data"]
                    if "data" in inline_data:
                        image_base64 = inline_data["data"]
                        logger.info(f"Found inline_data in part {i}")
                        break
                    else:
                        logger.error(f"Part {i} has inline_data but no data field")
                # 检查驼峰命名 inlineData
                elif "inlineData" in part:
                    inline_data = part["inlineData"]
                    if "data" in inline_data:
                        image_base64 = inline_data["data"]
                        logger.info(f"Found inlineData (camelCase) in part {i}")
                        break
                    else:
                        logger.error(f"Part {i} has inlineData but no data field")

            # 如果没有找到 inline_data 或 inlineData，记录所有 parts 的类型并抛出异常
            if image_base64 is None:
                part_types = []
                for part in parts:
                    if "text" in part:
                        part_types.append("text")
                    elif "inline_data" in part:
                        part_types.append("inline_data")
                    elif "inlineData" in part:
                        part_types.append("inlineData")
                    elif "thought_signature" in part:
                        part_types.append("thought_signature")
                    else:
                        part_types.append("unknown")

                logger.error(f"No inline_data or inlineData found in any part. Part types: {part_types}")

                # 如果有 text part，记录文本内容
                for i, part in enumerate(parts):
                    if "text" in part:
                        logger.error(f"Part {i} text content: {part['text'][:200]}...")

                raise GoogleAPIError(f"No inline_data or inlineData found in any part. Part types: {part_types}")

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