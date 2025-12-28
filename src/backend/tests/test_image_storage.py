"""
图片存储服务测试

测试 ImageStorage 类的所有功能。
"""

import pytest
import asyncio
from pathlib import Path
import tempfile
import shutil

from app.storage.image_storage import ImageStorage, ImageType


class TestImageStorage:
    """图片存储服务测试类"""

    @pytest.fixture
    def temp_storage_path(self):
        """创建临时存储路径"""
        temp_dir = tempfile.mkdtemp()
        yield temp_dir
        # 清理临时目录
        shutil.rmtree(temp_dir, ignore_errors=True)

    @pytest.fixture
    def storage(self, temp_storage_path):
        """创建图片存储实例"""
        return ImageStorage(
            base_path=temp_storage_path,
            base_url="http://localhost:8000/images"
        )

    @pytest.mark.asyncio
    async def test_save_and_get_image(self, storage):
        """测试保存和获取图片"""
        # 准备测试数据
        image_id = "test_image_001"
        image_data = b"fake_image_data_for_testing"
        extension = "png"

        # 保存图片
        url = await storage.save_image(image_id, image_data, extension)
        assert url is not None
        assert "test_image_001.png" in url

        # 获取图片
        retrieved_data = await storage.get_image(url)
        assert retrieved_data == image_data

    @pytest.mark.asyncio
    async def test_delete_image(self, storage):
        """测试删除图片"""
        # 保存图片
        image_id = "test_image_002"
        image_data = b"fake_image_data_for_testing"
        url = await storage.save_image(image_id, image_data, "png")

        # 验证图片存在
        assert await storage.image_exists(url)

        # 删除图片
        result = await storage.delete_image(url)
        assert result is True

        # 验证图片不存在
        assert not await storage.image_exists(url)

    @pytest.mark.asyncio
    async def test_generate_url(self, storage):
        """测试生成URL"""
        image_id = "test_image_003"
        url = storage.generate_url(image_id, "png", ImageType.GENERATED)
        assert url == "http://localhost:8000/images/generated/test_image_003.png"

    @pytest.mark.asyncio
    async def test_image_type_separation(self, storage):
        """测试不同类型图片的存储分离"""
        # 保存生成的图片
        generated_url = await storage.save_image(
            "gen_001",
            b"generated_data",
            "png",
            ImageType.GENERATED
        )
        assert "/images/generated/" in generated_url

        # 保存上传的图片
        uploaded_url = await storage.save_image(
            "upl_001",
            b"uploaded_data",
            "jpg",
            ImageType.UPLOADED
        )
        assert "/images/uploaded/" in uploaded_url

    @pytest.mark.asyncio
    async def test_unsupported_format(self, storage):
        """测试不支持的图片格式"""
        with pytest.raises(ValueError):
            await storage.save_image("test", b"data", "bmp")

    @pytest.mark.asyncio
    async def test_empty_image_id(self, storage):
        """测试空的图片ID"""
        with pytest.raises(ValueError):
            await storage.save_image("", b"data", "png")

    @pytest.mark.asyncio
    async def test_empty_image_data(self, storage):
        """测试空的图片数据"""
        with pytest.raises(ValueError):
            await storage.save_image("test", b"", "png")

    @pytest.mark.asyncio
    async def test_get_nonexistent_image(self, storage):
        """测试获取不存在的图片"""
        with pytest.raises(FileNotFoundError):
            await storage.get_image("http://localhost:8000/images/generated/nonexistent.png")

    @pytest.mark.asyncio
    async def test_cleanup_old_images(self, storage):
        """测试清理旧图片"""
        # 保存一些图片
        await storage.save_image("old_001", b"old_data", "png", ImageType.GENERATED)
        await storage.save_image("old_002", b"old_data", "png", ImageType.UPLOADED)
        await storage.save_image("new_001", b"new_data", "png", ImageType.GENERATED)

        # 清理0天前的图片（应该删除所有图片）
        deleted_count = await storage.cleanup_old_images(days=0)
        assert deleted_count >= 3


if __name__ == "__main__":
    pytest.main([__file__, "-v"])