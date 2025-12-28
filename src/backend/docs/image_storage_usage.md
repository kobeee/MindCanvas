# 图片存储服务使用指南

本文档介绍如何使用 MindCanvas 后端的图片存储服务。

## 目录

1. [快速开始](#快速开始)
2. [基本用法](#基本用法)
3. [高级用法](#高级用法)
4. [API 参考](#api-参考)
5. [错误处理](#错误处理)
6. [云存储集成](#云存储集成)

---

## 快速开始

### 安装依赖

```bash
pip install aiofiles
```

### 初始化存储服务

```python
from app.storage.image_storage import ImageStorage, ImageType

# 使用默认配置（从 settings 读取）
storage = ImageStorage()

# 或指定自定义配置
storage = ImageStorage(
    base_path="/app/storage/images",
    base_url="http://localhost:8000/images"
)
```

---

## 基本用法

### 保存图片

```python
import asyncio

async def save_example():
    # 准备图片数据
    image_id = "my_image_001"
    image_data = b"..."  # 图片二进制数据
    extension = "png"

    # 保存生成的图片
    url = await storage.save_image(
        image_id=image_id,
        image_data=image_data,
        extension=extension,
        image_type=ImageType.GENERATED
    )

    print(f"Image saved: {url}")
    # 输出: http://localhost:8000/images/generated/my_image_001.png

# 运行
asyncio.run(save_example())
```

### 保存用户上传的图片

```python
async def upload_example():
    # 保存上传的图片
    url = await storage.save_image(
        image_id="upload_001",
        image_data=image_data,
        extension="jpg",
        image_type=ImageType.UPLOADED
    )

    print(f"Uploaded: {url}")
    # 输出: http://localhost:8000/images/uploaded/upload_001.jpg
```

### 获取图片

```python
async def get_example():
    image_url = "http://localhost:8000/images/generated/my_image_001.png"

    # 获取图片数据
    image_data = await storage.get_image(image_url)

    print(f"Image size: {len(image_data)} bytes")
```

### 删除图片

```python
async def delete_example():
    image_url = "http://localhost:8000/images/generated/my_image_001.png"

    # 删除图片
    success = await storage.delete_image(image_url)

    if success:
        print("Image deleted successfully")
    else:
        print("Failed to delete image")
```

### 检查图片是否存在

```python
async def check_example():
    image_url = "http://localhost:8000/images/generated/my_image_001.png"

    # 检查图片是否存在
    exists = await storage.image_exists(image_url)

    if exists:
        print("Image exists")
    else:
        print("Image not found")
```

### 生成访问URL

```python
def generate_url_example():
    # 生成图片URL
    url = storage.generate_url(
        image_id="my_image_001",
        extension="png",
        image_type=ImageType.GENERATED
    )

    print(f"Generated URL: {url}")
    # 输出: http://localhost:8000/images/generated/my_image_001.png
```

---

## 高级用法

### 支持的图片格式

```python
# 支持的格式
SUPPORTED_FORMATS = {"png", "jpg", "jpeg", "webp"}

# 使用不同格式
await storage.save_image("img1", data, "png")
await storage.save_image("img2", data, "jpg")
await storage.save_image("img3", data, "jpeg")
await storage.save_image("img4", data, "webp")
```

### 清理旧图片

```python
async def cleanup_example():
    # 清理7天前的旧图片
    deleted_count = await storage.cleanup_old_images(days=7)
    print(f"Deleted {deleted_count} old images")

    # 只清理生成的图片
    deleted_count = await storage.cleanup_old_images(
        days=7,
        image_type=ImageType.GENERATED
    )
    print(f"Deleted {deleted_count} generated images")
```

### 在 FastAPI 路由中使用

```python
from fastapi import APIRouter, UploadFile, File
from app.storage.image_storage import ImageStorage, ImageType
import uuid

router = APIRouter()
storage = ImageStorage()

@router.post("/upload")
async def upload_image(file: UploadFile = File(...)):
    """上传图片"""
    # 读取文件数据
    image_data = await file.read()

    # 生成唯一ID
    image_id = str(uuid.uuid4())

    # 获取文件扩展名
    extension = file.filename.split(".")[-1]

    # 保存图片
    image_url = await storage.save_image(
        image_id=image_id,
        image_data=image_data,
        extension=extension,
        image_type=ImageType.UPLOADED
    )

    return {"url": image_url}

@router.get("/images/{image_url:path}")
async def get_image(image_url: str):
    """获取图片"""
    try:
        image_data = await storage.get_image(image_url)
        from fastapi.responses import Response
        return Response(content=image_data, media_type="image/png")
    except FileNotFoundError:
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Image not found")
```

### 在任务服务中使用

```python
from app.storage.image_storage import ImageStorage, ImageType

class TaskService:
    def __init__(self):
        self.storage = ImageStorage()

    async def process_task(self, task_id: str, image_data: bytes):
        """处理任务并保存生成的图片"""
        try:
            # 保存生成的图片
            image_url = await self.storage.save_image(
                image_id=task_id,
                image_data=image_data,
                extension="png",
                image_type=ImageType.GENERATED
            )

            # 更新任务状态
            await self.update_task_status(task_id, "completed", image_url)

            return image_url

        except Exception as e:
            # 处理错误
            await self.update_task_status(task_id, "failed", error=str(e))
            raise
```

---

## API 参考

### ImageStorage 类

#### 构造函数

```python
ImageStorage(
    base_path: Optional[str] = None,
    base_url: Optional[str] = None
)
```

**参数**:
- `base_path`: 存储根路径，默认从配置读取
- `base_url`: 访问基础URL，默认从配置读取

#### 方法

##### save_image

```python
async def save_image(
    self,
    image_id: str,
    image_data: bytes,
    extension: str = "png",
    image_type: ImageType = ImageType.GENERATED
) -> str
```

保存图片到存储。

**参数**:
- `image_id`: 图片ID
- `image_data`: 图片二进制数据
- `extension`: 文件扩展名（默认: png）
- `image_type`: 图片类型（默认: GENERATED）

**返回**: 图片访问URL

**异常**:
- `ValueError`: 参数无效
- `IOError`: 文件保存失败

##### delete_image

```python
async def delete_image(self, image_url: str) -> bool
```

删除图片。

**参数**:
- `image_url`: 图片URL

**返回**: 是否删除成功

##### get_image

```python
async def get_image(self, image_url: str) -> bytes
```

获取图片数据。

**参数**:
- `image_url`: 图片URL

**返回**: 图片二进制数据

**异常**:
- `ValueError`: URL格式无效
- `FileNotFoundError`: 图片不存在
- `IOError`: 读取失败

##### generate_url

```python
def generate_url(
    self,
    image_id: str,
    extension: str = "png",
    image_type: ImageType = ImageType.GENERATED
) -> str
```

生成图片访问URL。

**参数**:
- `image_id`: 图片ID
- `extension`: 文件扩展名（默认: png）
- `image_type`: 图片类型（默认: GENERATED）

**返回**: 图片访问URL

##### image_exists

```python
async def image_exists(self, image_url: str) -> bool
```

检查图片是否存在。

**参数**:
- `image_url`: 图片URL

**返回**: 图片是否存在

##### cleanup_old_images

```python
async def cleanup_old_images(
    self,
    days: int = 7,
    image_type: Optional[ImageType] = None
) -> int
```

清理指定天数前的旧图片。

**参数**:
- `days`: 保留天数（默认: 7天）
- `image_type`: 图片类型（默认: None，清理所有类型）

**返回**: 删除的图片数量

### ImageType 枚举

```python
class ImageType(Enum):
    GENERATED = "generated"  # AI 生成的图片
    UPLOADED = "uploaded"    # 用户上传的图片
```

---

## 错误处理

### 常见错误

```python
from app.storage.image_storage import ImageStorage, ImageType

storage = ImageStorage()

# 1. 不支持的图片格式
try:
    await storage.save_image("test", b"data", "bmp")
except ValueError as e:
    print(f"Error: {e}")
    # 输出: Unsupported image format: bmp. Supported formats: {'png', 'jpg', 'jpeg', 'webp'}

# 2. 空的图片ID
try:
    await storage.save_image("", b"data", "png")
except ValueError as e:
    print(f"Error: {e}")
    # 输出: image_id cannot be empty

# 3. 空的图片数据
try:
    await storage.save_image("test", b"", "png")
except ValueError as e:
    print(f"Error: {e}")
    # 输出: image_data cannot be empty

# 4. 图片不存在
try:
    await storage.get_image("http://localhost:8000/images/generated/nonexistent.png")
except FileNotFoundError as e:
    print(f"Error: {e}")
    # 输出: Image not found: /app/storage/images/generated/nonexistent.png

# 5. 无效的URL格式
try:
    await storage.delete_image("invalid_url")
except ValueError as e:
    print(f"Error: {e}")
    # 输出: Failed to parse image URL: invalid_url
```

---

## 云存储集成

### CloudImageStorage（预留）

`CloudImageStorage` 类预留了云存储接口，支持 AWS S3 和 Aliyun OSS。

```python
from app.storage.image_storage import CloudImageStorage

# AWS S3 示例（预留）
storage = CloudImageStorage(
    provider="s3",
    bucket_name="mindcanvas-images",
    access_key="your_access_key",
    secret_key="your_secret_key",
    region="us-east-1"
)

# Aliyun OSS 示例（预留）
storage = CloudImageStorage(
    provider="oss",
    bucket_name="mindcanvas-images",
    access_key_id="your_access_key_id",
    access_key_secret="your_access_key_secret",
    endpoint="oss-cn-hangzhou.aliyuncs.com"
)
```

**注意**: 云存储功能当前为预留接口，需要根据实际需求实现。

### 从本地存储迁移到云存储

```python
# 当前使用本地存储
from app.storage.image_storage import ImageStorage

storage = ImageStorage()

# 未来迁移到云存储
# from app.storage.image_storage import CloudImageStorage
# storage = CloudImageStorage(provider="s3", bucket_name="mindcanvas-images", ...)

# API 保持一致，无需修改业务代码
url = await storage.save_image(image_id, image_data, "png")
```

---

## 最佳实践

### 1. 使用唯一ID

```python
import uuid

# 生成唯一ID
image_id = str(uuid.uuid4())
```

### 2. 验证图片格式

```python
ALLOWED_FORMATS = {"png", "jpg", "jpeg", "webp"}

extension = filename.split(".")[-1].lower()
if extension not in ALLOWED_FORMATS:
    raise ValueError(f"Invalid image format: {extension}")
```

### 3. 限制图片大小

```python
MAX_IMAGE_SIZE = 10 * 1024 * 1024  # 10MB

if len(image_data) > MAX_IMAGE_SIZE:
    raise ValueError(f"Image too large: {len(image_data)} bytes")
```

### 4. 定期清理旧图片

```python
import asyncio

async def cleanup_job():
    storage = ImageStorage()
    while True:
        await storage.cleanup_old_images(days=7)
        await asyncio.sleep(3600)  # 每小时执行一次
```

---

## 配置说明

在 `.env` 文件中配置：

```env
# 图片存储路径
IMAGE_STORAGE_PATH=/app/storage/images

# 图片访问基础URL
IMAGE_BASE_URL=http://localhost:8000/images

# 生产环境使用实际域名
# IMAGE_BASE_URL=https://api.mindcanvas.com/images
```

在 `config.py` 中：

```python
class Settings(BaseSettings):
    # 图片存储配置
    IMAGE_STORAGE_PATH: str = "/app/storage/images"
    IMAGE_BASE_URL: str = "http://localhost:8000/images"
```

---

## 测试

运行测试：

```bash
cd /Users/elvis/Documents/codes/一个月一个AI项目挑战/2025/12月/MindCanvas/src/backend
pytest tests/test_image_storage.py -v
```

---

## 常见问题

### Q1: 如何更改存储路径？

A: 在 `.env` 文件中设置 `IMAGE_STORAGE_PATH`，或在初始化时指定：

```python
storage = ImageStorage(base_path="/custom/path/images")
```

### Q2: 如何支持更多图片格式？

A: 修改 `ImageStorage.SUPPORTED_FORMATS`：

```python
ImageStorage.SUPPORTED_FORMATS.add("gif")
```

### Q3: 如何在 Docker 中使用？

A: 确保挂载存储卷：

```yaml
volumes:
  - ./storage:/app/storage
```

### Q4: 如何实现 CDN 加速？

A: 修改 `IMAGE_BASE_URL` 指向 CDN 域名：

```env
IMAGE_BASE_URL=https://cdn.mindcanvas.com/images
```

---

## 更新日志

### v1.0.0 (2025-12-27)

- 初始版本
- 实现本地存储功能
- 支持多种图片格式
- 预留云存储接口
- 完整的单元测试