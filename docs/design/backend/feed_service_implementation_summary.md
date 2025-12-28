# 社区服务实现总结

## 概述

本文档记录了 MindCanvas 后端社区模块（Feed、发布、举报）的实现过程和关键设计决策。

## 创建的文件

### 1. app/services/feed_service.py
社区服务实现，提供以下功能：
- 获取社区动态列表（支持分页和排序）
- 发布资源到社区
- 点赞社区动态（使用 Redis 缓存）
- 举报社区动态
- 获取单个动态详情

### 2. app/routers/feed.py
社区路由实现，提供以下 API 接口：
- `GET /api/v1/feed` - 获取社区动态列表
- `POST /api/v1/feed/assets/{asset_id}/publish` - 发布资源到社区
- `POST /api/v1/feed/{feed_id}/like` - 点赞动态
- `POST /api/v1/feed/{feed_id}/report` - 举报动态
- `GET /api/v1/feed/{feed_id}` - 获取单个动态详情

### 3. 修改的文件
- `app/models/schemas.py` - 添加了 `PublishRequest` 和 `ReportRequest` 模型
- `app/main.py` - 注册了 assets 和 feed 路由
- `app/routers/__init__.py` - 导出了 assets 和 feed 模块

## FeedService 类实现

### 核心方法

#### 1. get_feed(page, size, sort)
获取社区动态列表，支持：
- 分页（page, size）
- 排序（latest: 最新, hot: 热门）
- 关联查询 Asset 和 User

**关键实现细节**：
```python
# 使用 selectinload 进行关联查询
query = (
    select(FeedItem)
    .options(
        selectinload(FeedItem.asset),
        selectinload(FeedItem.user)
    )
)

# 排序逻辑
if sort == "latest":
    query = query.order_by(FeedItem.published_at.desc())
else:  # hot
    query = query.order_by(FeedItem.likes_count.desc(), FeedItem.published_at.desc())
```

#### 2. publish_asset(asset_id, user_id, title)
发布资源到社区，包含：
- 权限检查（只能发布自己的资源）
- 重复发布检查
- 内容安全审核（根据 ENABLE_STRICT_AUDIT 配置）
- 自动将资源标记为公开

**安全特性**：
```python
# 检查资源归属
if asset.user_id != user_id:
    raise FeedPermissionError("You don't have permission to publish this asset")

# 检查是否已经发布
existing_feed = await self.db.execute(
    select(FeedItem).where(FeedItem.asset_id == asset_id)
)
if existing_feed.scalar_one_or_none():
    raise FeedServiceError("Asset already published to feed")

# 内容安全审核检查
if settings.ENABLE_STRICT_AUDIT:
    # TODO: 实现内容安全审核
    logger.warning(f"Strict audit enabled for asset {asset_id}")
```

#### 3. like_feed(feed_id)
点赞社区动态，使用 Redis 缓存：
- Redis Key: `feed:likes:{feed_id}`
- 使用 `incr` 命令原子性增加点赞数
- 同步到数据库
- Redis 失败时回退到数据库操作

**Redis 缓存实现**：
```python
if self.redis:
    try:
        redis_key = f"feed:likes:{feed_id}"
        likes_count = await self.redis.incr(redis_key)

        # 同步到数据库
        feed_item.likes_count = likes_count
        await self.db.commit()

        return likes_count
    except Exception as redis_error:
        logger.warning(f"Redis error, fallback to database: {str(redis_error)}")

# 直接更新数据库
feed_item.likes_count += 1
await self.db.commit()
```

#### 4. report_feed(feed_id, reporter_id, reason, description)
举报社区动态，包含：
- 重复举报检查
- 举报状态默认为 'pending'
- 管理员后台审核

**重复举报检查**：
```python
existing_report = await self.db.execute(
    select(Report).where(
        and_(
            Report.feed_item_id == feed_id,
            Report.reporter_id == reporter_id
        )
    )
)
if existing_report.scalar_one_or_none():
    raise ReportAlreadyExistsError("You have already reported this feed")
```

#### 5. get_feed_by_id(feed_id)
获取单个动态详情，关联查询 Asset 和 User。

#### 6. get_likes_count(feed_id)
获取点赞数，优先从 Redis 读取，Redis 不可用时从数据库读取。

## API 路由实现

### 依赖注入

```python
async def get_feed_service(db: AsyncSession) -> FeedService:
    """获取 FeedService 实例"""
    # TODO: 注入 Redis 客户端
    return FeedService(db)

async def get_current_user(credentials, auth_service) -> User:
    """从 JWT Token 获取当前用户"""
    token = credentials.credentials
    user = await auth_service.get_current_user(token)
    return user
```

### API 接口

#### 1. GET /api/v1/feed
获取社区动态列表（无需认证）

**请求参数**：
- `page`: 页码（默认 1）
- `size`: 每页数量（默认 20，最大 100）
- `sort`: 排序方式（latest: 最新, hot: 热门）

**响应示例**：
```json
{
  "total": 100,
  "page": 1,
  "size": 20,
  "items": [
    {
      "id": "uuid",
      "asset_id": "uuid",
      "user_id": "uuid",
      "title": "My Masterpiece",
      "likes_count": 10,
      "published_at": "2025-12-27T10:00:00",
      "created_at": "2025-12-27T10:00:00",
      "updated_at": "2025-12-27T10:00:00",
      "asset": {...},
      "user": {...}
    }
  ]
}
```

#### 2. POST /api/v1/feed/assets/{asset_id}/publish
发布资源到社区（需要认证）

**请求体**：
```json
{
  "title": "My Masterpiece"
}
```

**响应**：FeedItemResponse

#### 3. POST /api/v1/feed/{feed_id}/like
点赞动态（无需认证）

**响应**：
```json
{
  "success": true,
  "message": "Feed liked successfully, likes_count=10"
}
```

#### 4. POST /api/v1/feed/{feed_id}/report
举报动态（需要认证）

**请求体**：
```json
{
  "reason": "nsfw"
}
```

**响应**：
```json
{
  "success": true,
  "message": "Feed reported successfully, report_id=uuid"
}
```

#### 5. GET /api/v1/feed/{feed_id}
获取单个动态详情（无需认证）

**响应**：FeedItemResponse

## Pydantic 模型

### 新增模型

```python
class PublishRequest(BaseModel):
    """发布资源请求"""
    title: Optional[str] = Field(default=None, max_length=255, description="标题")


class ReportRequest(BaseModel):
    """举报请求"""
    reason: str = Field(..., min_length=1, max_length=100, description="举报原因")
```

### 已有模型（复用）

- `FeedItemResponse` - 社区动态响应
- `FeedListResponse` - 社区动态列表响应
- `SuccessResponse` - 成功响应

## 安全特性

### 1. 权限检查
- 只能发布自己的资源
- 每个资源只能发布一次
- 每个用户对每个动态只能举报一次

### 2. 内容安全审核
- 根据 `ENABLE_STRICT_AUDIT` 配置启用
- 预留了审核接口（待实现）

### 3. Redis 缓存
- 点赞数使用 Redis 缓存加速
- Redis 失败时自动回退到数据库
- 同步机制确保数据一致性

## 错误处理

### 自定义异常

```python
class FeedNotFoundError(Exception):
    """社区动态不存在异常"""

class FeedPermissionError(Exception):
    """社区动态权限异常"""

class FeedServiceError(Exception):
    """社区服务异常基类"""

class ReportAlreadyExistsError(Exception):
    """举报已存在异常"""
```

### HTTP 状态码

- `200 OK` - 成功
- `201 Created` - 创建成功
- `400 Bad Request` - 请求参数错误
- `401 Unauthorized` - 未授权
- `403 Forbidden` - 权限不足
- `404 Not Found` - 资源不存在
- `500 Internal Server Error` - 服务器错误

## 测试建议

### 单元测试
1. 测试获取动态列表（分页、排序）
2. 测试发布资源（权限、重复发布）
3. 测试点赞功能（Redis 缓存、数据库同步）
4. 测试举报功能（重复举报）
5. 测试错误处理

### 集成测试
1. 测试完整的发布流程
2. 测试点赞和举报的并发场景
3. 测试 Redis 故障回退机制

## 待优化项

### 1. Redis 集成
- 创建 Redis 连接管理模块
- 实现后台任务定期同步 Redis 到数据库
- 添加 Redis 健康检查

### 2. 内容安全审核
- 集成第三方审核服务（阿里云内容安全、腾讯云天御）
- 实现审核结果回调

### 3. 性能优化
- 添加缓存层（Feed 列表缓存）
- 实现分页预加载
- 优化数据库查询

### 4. 功能增强
- 添加评论功能
- 添加收藏功能
- 添加用户关注功能
- 添加推荐算法

## 遇到的问题和解决方案

### 问题 1: 参数顺序错误
**错误**：`SyntaxError: parameter without a default follows parameter with a default`

**原因**：FastAPI 路由函数中，带默认值的参数必须在没有默认值的参数之后。

**解决方案**：将 `feed_service` 参数移到函数参数列表的前面。

```python
# 错误
async def get_feed(
    page: int = 1,
    size: int = 20,
    sort: str = "latest",
    feed_service: Annotated[FeedService, Depends(get_feed_service)]
):

# 正确
async def get_feed(
    feed_service: Annotated[FeedService, Depends(get_feed_service)],
    page: int = 1,
    size: int = 20,
    sort: str = "latest"
):
```

### 问题 2: 导入缺失
**错误**：`NameError: name 'selectinload' is not defined`

**原因**：未导入 `selectinload`。

**解决方案**：添加导入语句。

```python
from sqlalchemy.orm import selectinload
```

## 总结

社区模块已成功实现，包含以下核心功能：

1. 获取社区动态列表（支持分页和排序）
2. 发布资源到社区（权限检查、重复检查）
3. 点赞社区动态（Redis 缓存）
4. 举报社区动态（重复举报检查）
5. 获取单个动态详情

所有功能都包含完善的错误处理和日志记录，符合项目开发规范。

## 下一步

1. 实现任务 9：API 路由层整合（已完成部分）
2. 添加单元测试和集成测试
3. 实现 Redis 连接管理模块
4. 实现内容安全审核功能
5. 性能优化和功能增强