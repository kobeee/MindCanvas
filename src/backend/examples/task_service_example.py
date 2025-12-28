"""
TaskService 使用示例

演示如何使用 TaskService 创建和管理生图任务
"""

import asyncio
import sys
import os

# 添加项目根目录到 Python 路径
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# 只导入不依赖数据库的模块
from app.services.encryption import EncryptionService
from app.services.google_api import GoogleAPIClient
from app.storage.image_storage import ImageStorage


async def example_usage():
    """
    TaskService 使用示例
    """
    print("=" * 60)
    print("TaskService 使用示例")
    print("=" * 60)

    # 初始化服务
    print("\n1. 初始化服务...")
    try:
        encryption_service = EncryptionService(
            secret_key="ST7kPnldm-hsckHSrVuVLP5MaH4C7D56BgqD41tA_p4="
        )
        print("  [OK] EncryptionService 初始化成功")

        google_client = GoogleAPIClient()
        print("  [OK] GoogleAPIClient 初始化成功")

        storage = ImageStorage(base_path="./storage/images", base_url="http://localhost:8000/images")
        print("  [OK] ImageStorage 初始化成功")

        print("\n  注意: TaskService 需要真实的数据库连接")
        print("  实际使用时，TaskService 会:")
        print("    1. 创建任务记录到数据库")
        print("    2. 异步处理任务（调用 Google API）")
        print("    3. 保存生成的图片")
        print("    4. 更新任务状态")
        print("    5. 清除 API Key")

    except Exception as e:
        print(f"  [ERROR] 服务初始化失败: {e}")
        return

    # 示例 1: 加密 API Key
    print("\n2. 加密 API Key...")
    try:
        api_key = "your_google_api_key_here"
        encrypted_key = encryption_service.encrypt(api_key)
        print(f"  [OK] API Key 加密成功")
        print(f"  原始密钥: {api_key[:10]}...")
        print(f"  加密密钥: {encrypted_key[:20]}...")
    except Exception as e:
        print(f"  [ERROR] API Key 加密失败: {e}")
        return

    # 示例 2: 创建任务（模拟）
    print("\n3. 创建任务（模拟）...")
    print("  注意: 由于没有真实的数据库连接，这里只演示流程")
    print("  实际使用时，TaskService 会:")
    print("    1. 创建任务记录到数据库")
    print("    2. 异步处理任务（调用 Google API）")
    print("    3. 保存生成的图片")
    print("    4. 更新任务状态")
    print("    5. 清除 API Key")

    # 示例 3: 任务状态
    print("\n4. 任务状态说明...")
    print("  pending:      任务已创建，等待处理")
    print("  processing:   任务正在处理中")
    print("  completed:    任务已完成，图片已生成")
    print("  failed:       任务失败，查看 error_message")

    # 示例 4: API Key 安全流程
    print("\n5. API Key 安全流程...")
    print("  1. iOS APP 加密 API Key (AES-256-GCM)")
    print("  2. HTTPS 传输到后端")
    print("  3. 后端解密 API Key (Fernet)")
    print("  4. 加密存储 API Key (Fernet)")
    print("  5. 任务处理时解密到内存")
    print("  6. 调用 Google API")
    print("  7. 立即清除内存中的 API Key")
    print("  8. 任务完成后删除数据库中的 API Key")

    # 示例 5: 错误处理
    print("\n6. 错误处理...")
    print("  TaskServiceError: 任务服务异常")
    print("  TaskNotFoundError: 任务不存在")
    print("  EncryptionError: 加密服务异常")
    print("  GoogleAPIError: Google API 异常")

    print("\n" + "=" * 60)
    print("示例完成")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(example_usage())
