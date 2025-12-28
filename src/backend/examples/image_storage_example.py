"""
图片存储服务使用示例

演示如何在实际应用中使用 ImageStorage 类。
"""

import asyncio
import sys
from pathlib import Path

# 添加项目根目录到 Python 路径
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.storage.image_storage import ImageStorage, ImageType


async def example_1_basic_usage():
    """示例1：基本用法"""
    print("\n=== 示例1：基本用法 ===")

    # 初始化存储服务
    storage = ImageStorage(
        base_path="/tmp/mindcanvas_images",
        base_url="http://localhost:8000/images"
    )

    # 保存图片
    image_id = "example_001"
    image_data = b"fake_image_data_for_testing_example"
    url = await storage.save_image(image_id, image_data, "png", ImageType.GENERATED)

    print(f"保存图片成功: {url}")

    # 获取图片
    retrieved_data = await storage.get_image(url)
    print(f"获取图片成功: {len(retrieved_data)} bytes")

    # 检查图片是否存在
    exists = await storage.image_exists(url)
    print(f"图片存在: {exists}")

    # 删除图片
    success = await storage.delete_image(url)
    print(f"删除图片: {success}")


async def example_2_different_types():
    """示例2：不同类型的图片"""
    print("\n=== 示例2：不同类型的图片 ===")

    storage = ImageStorage(
        base_path="/tmp/mindcanvas_images",
        base_url="http://localhost:8000/images"
    )

    # 保存生成的图片
    gen_url = await storage.save_image(
        "gen_example_001",
        b"generated_image_data",
        "png",
        ImageType.GENERATED
    )
    print(f"生成图片: {gen_url}")

    # 保存上传的图片
    upl_url = await storage.save_image(
        "upl_example_001",
        b"uploaded_image_data",
        "jpg",
        ImageType.UPLOADED
    )
    print(f"上传图片: {upl_url}")

    # 清理
    await storage.delete_image(gen_url)
    await storage.delete_image(upl_url)
    print("清理完成")


async def example_3_multiple_formats():
    """示例3：多种图片格式"""
    print("\n=== 示例3：多种图片格式 ===")

    storage = ImageStorage(
        base_path="/tmp/mindcanvas_images",
        base_url="http://localhost:8000/images"
    )

    formats = ["png", "jpg", "jpeg", "webp"]
    urls = []

    for fmt in formats:
        image_id = f"example_{fmt}"
        url = await storage.save_image(image_id, b"test_data", fmt, ImageType.GENERATED)
        urls.append(url)
        print(f"保存 {fmt} 格式: {url}")

    # 清理
    for url in urls:
        await storage.delete_image(url)
    print("清理完成")


async def example_4_url_generation():
    """示例4：URL生成"""
    print("\n=== 示例4：URL生成 ===")

    storage = ImageStorage(
        base_path="/tmp/mindcanvas_images",
        base_url="http://localhost:8000/images"
    )

    # 生成不同类型的URL
    gen_url = storage.generate_url("test_gen", "png", ImageType.GENERATED)
    print(f"生成图片URL: {gen_url}")

    upl_url = storage.generate_url("test_upl", "jpg", ImageType.UPLOADED)
    print(f"上传图片URL: {upl_url}")


async def example_5_error_handling():
    """示例5：错误处理"""
    print("\n=== 示例5：错误处理 ===")

    storage = ImageStorage(
        base_path="/tmp/mindcanvas_images",
        base_url="http://localhost:8000/images"
    )

    # 不支持的格式
    try:
        await storage.save_image("test", b"data", "bmp")
    except ValueError as e:
        print(f"捕获错误（不支持的格式）: {e}")

    # 空的图片ID
    try:
        await storage.save_image("", b"data", "png")
    except ValueError as e:
        print(f"捕获错误（空的图片ID）: {e}")

    # 空的图片数据
    try:
        await storage.save_image("test", b"", "png")
    except ValueError as e:
        print(f"捕获错误（空的图片数据）: {e}")

    # 图片不存在
    try:
        await storage.get_image("http://localhost:8000/images/generated/nonexistent.png")
    except FileNotFoundError as e:
        print(f"捕获错误（图片不存在）: {e}")


async def example_6_cleanup():
    """示例6：清理旧图片"""
    print("\n=== 示例6：清理旧图片 ===")

    storage = ImageStorage(
        base_path="/tmp/mindcanvas_images",
        base_url="http://localhost:8000/images"
    )

    # 保存一些图片
    urls = []
    for i in range(3):
        url = await storage.save_image(
            f"cleanup_test_{i}",
            b"test_data",
            "png",
            ImageType.GENERATED
        )
        urls.append(url)
        print(f"保存图片: {url}")

    # 清理0天前的图片（删除所有）
    deleted_count = await storage.cleanup_old_images(days=0)
    print(f"清理了 {deleted_count} 张旧图片")

    # 验证图片已被删除
    for url in urls:
        exists = await storage.image_exists(url)
        print(f"图片 {url} 存在: {exists}")


async def example_7_task_service_integration():
    """示例7：在任务服务中使用"""
    print("\n=== 示例7：在任务服务中使用 ===")

    class MockTaskService:
        """模拟任务服务"""

        def __init__(self):
            self.storage = ImageStorage(
                base_path="/tmp/mindcanvas_images",
                base_url="http://localhost:8000/images"
            )

        async def process_task(self, task_id: str, prompt: str):
            """处理任务并保存生成的图片"""
            print(f"处理任务: {task_id}")
            print(f"提示词: {prompt}")

            # 模拟生成图片
            image_data = f"generated_image_for_{prompt}".encode()

            try:
                # 保存生成的图片
                image_url = await self.storage.save_image(
                    image_id=task_id,
                    image_data=image_data,
                    extension="png",
                    image_type=ImageType.GENERATED
                )

                print(f"任务完成，图片已保存: {image_url}")
                return image_url

            except Exception as e:
                print(f"任务失败: {e}")
                raise

    # 使用模拟任务服务
    task_service = MockTaskService()
    image_url = await task_service.process_task("task_001", "A beautiful sunset")

    # 清理
    await task_service.storage.delete_image(image_url)
    print("清理完成")


async def main():
    """运行所有示例"""
    print("MindCanvas 图片存储服务示例")
    print("=" * 50)

    try:
        await example_1_basic_usage()
        await example_2_different_types()
        await example_3_multiple_formats()
        await example_4_url_generation()
        await example_5_error_handling()
        await example_6_cleanup()
        await example_7_task_service_integration()

        print("\n" + "=" * 50)
        print("所有示例执行完成！")

    except Exception as e:
        print(f"\n执行示例时出错: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(main())