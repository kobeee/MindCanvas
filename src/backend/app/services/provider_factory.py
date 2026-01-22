"""
API 提供商工厂模块

提供统一的 API 提供商创建接口，支持多种生图 API 提供商。
"""

import logging
from abc import ABC, abstractmethod
from typing import Optional

from app.services.google_api import GoogleAPIClient
from app.services.laozhang_api import LaozhangAPIClient

logger = logging.getLogger(__name__)


class ImageGenerationProvider(ABC):
    """图像生成提供商抽象基类"""

    @abstractmethod
    async def generate_image(
        self,
        api_key: str,
        prompt: str,
        base_image: Optional[str] = None,
        image_size: str = "2K"
    ) -> bytes:
        """
        生成图片

        Args:
            api_key: API Key
            prompt: 提示词
            base_image: 参考图的 Base64 编码（可选）
            image_size: 图片尺寸（1K, 2K, 4K）

        Returns:
            图片二进制数据
        """
        pass


class ProviderFactory:
    """API 提供商工厂"""

    @staticmethod
    def create_provider(provider_name: str) -> ImageGenerationProvider:
        """
        创建 API 提供商实例

        Args:
            provider_name: 提供商名称（'google' or 'laozhang'）

        Returns:
            API 提供商实例

        Raises:
            ValueError: 如果提供商名称无效
        """
        providers = {
            "google": GoogleAPIClient,
            "laozhang": LaozhangAPIClient
        }

        provider_class = providers.get(provider_name)
        if not provider_class:
            raise ValueError(f"Unknown provider: {provider_name}")

        return provider_class()