"""
Pydantic 模型

定义所有 API 请求和响应的数据模型
"""

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, Field, EmailStr, ConfigDict


# ==================== 通用响应模型 ====================
class SuccessResponse(BaseModel):
    """成功响应"""
    success: bool = True
    message: str = "Operation successful"


class ErrorResponse(BaseModel):
    """错误响应"""
    success: bool = False
    error: str
    message: str
    details: Optional[dict] = None


# ==================== 用户相关模型 ====================
class UserBase(BaseModel):
    """用户基础模型"""
    email: EmailStr
    username: Optional[str] = None
    avatar_url: Optional[str] = None


class UserCreate(UserBase):
    """创建用户"""
    auth_provider: str = Field(..., description="认证提供者: apple, google, github, email")
    provider_id: Optional[str] = None


class UserUpdate(BaseModel):
    """更新用户"""
    username: Optional[str] = None
    avatar_url: Optional[str] = None


class UserResponse(UserBase):
    """用户响应"""
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    auth_provider: str
    created_at: datetime
    updated_at: datetime


# ==================== 认证相关模型 ====================
class LoginRequest(BaseModel):
    """登录请求"""
    provider: str = Field(..., description="认证提供者: apple, google, github, email")
    token: str = Field(..., description="第三方 Token 或验证码")


class LoginResponse(BaseModel):
    """登录响应"""
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


# ==================== 资源相关模型 ====================
class AssetBase(BaseModel):
    """资源基础模型"""
    url: str
    type: str = Field(..., description="资源类型: upload, generated")
    prompt: Optional[str] = None
    model_version: Optional[str] = None
    is_public: bool = False


class AssetCreate(AssetBase):
    """创建资源"""
    pass


class AssetUpdate(BaseModel):
    """更新资源"""
    is_public: Optional[bool] = None


class AssetResponse(AssetBase):
    """资源响应"""
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    created_at: datetime
    updated_at: datetime


class AssetListResponse(BaseModel):
    """资源列表响应"""
    total: int
    page: int
    size: int
    items: list[AssetResponse]


# ==================== 社区动态相关模型 ====================
class FeedItemBase(BaseModel):
    """社区动态基础模型"""
    asset_id: UUID
    title: Optional[str] = None


class FeedItemCreate(FeedItemBase):
    """创建社区动态"""
    pass


class FeedItemUpdate(BaseModel):
    """更新社区动态"""
    title: Optional[str] = None
    likes_count: Optional[int] = None


class PublishRequest(BaseModel):
    """发布资源请求"""
    title: Optional[str] = Field(default=None, max_length=255, description="标题")


class ReportRequest(BaseModel):
    """举报请求"""
    reason: str = Field(..., min_length=1, max_length=100, description="举报原因")


class FeedItemResponse(FeedItemBase):
    """社区动态响应"""
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    likes_count: int
    published_at: datetime
    created_at: datetime
    updated_at: datetime

    # 关联数据
    asset: Optional[AssetResponse] = None
    user: Optional[UserResponse] = None


class FeedListResponse(BaseModel):
    """社区动态列表响应"""
    total: int
    page: int
    size: int
    items: list[FeedItemResponse]


# ==================== 生图任务相关模型 ====================
class TaskBase(BaseModel):
    """任务基础模型"""
    prompt: str = Field(..., min_length=1, max_length=2000)
    base_image: Optional[str] = None


class TaskCreate(TaskBase):
    """创建任务"""
    encrypted_api_key: str = Field(..., description="加密的 API Key")


class TaskUpdate(BaseModel):
    """更新任务"""
    status: Optional[str] = None
    image_url: Optional[str] = None
    error_message: Optional[str] = None


class TaskResponse(TaskBase):
    """任务响应"""
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    status: str
    image_url: Optional[str] = None
    error_message: Optional[str] = None
    created_at: datetime
    updated_at: datetime


class TaskStatusResponse(BaseModel):
    """任务状态响应"""
    task_id: UUID
    status: str
    progress: Optional[int] = None
    image_url: Optional[str] = None
    error_message: Optional[str] = None


class TaskListResponse(BaseModel):
    """任务列表响应"""
    total: int
    page: int
    size: int
    items: list[TaskResponse]


# ==================== 举报相关模型 ====================
class ReportBase(BaseModel):
    """举报基础模型"""
    feed_item_id: UUID
    reason: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None


class ReportCreate(ReportBase):
    """创建举报"""
    pass


class ReportUpdate(BaseModel):
    """更新举报"""
    status: Optional[str] = None


class ReportResponse(ReportBase):
    """举报响应"""
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    reporter_id: UUID
    status: str
    created_at: datetime
    updated_at: datetime

    # 关联数据
    feed_item: Optional[FeedItemResponse] = None
    reporter: Optional[UserResponse] = None


class ReportListResponse(BaseModel):
    """举报列表响应"""
    total: int
    page: int
    size: int
    items: list[ReportResponse]


# ==================== 分页参数 ====================
class PaginationParams(BaseModel):
    """分页参数"""
    page: int = Field(default=1, ge=1, description="页码")
    size: int = Field(default=20, ge=1, le=100, description="每页数量")

    @property
    def offset(self) -> int:
        """计算偏移量"""
        return (self.page - 1) * self.size


# ==================== 过滤参数 ====================
class FeedFilterParams(PaginationParams):
    """社区动态过滤参数"""
    sort: str = Field(default="latest", description="排序方式: latest, hot")


class AssetFilterParams(PaginationParams):
    """资源过滤参数"""
    type: Optional[str] = Field(default=None, description="资源类型: upload, generated")
    is_public: Optional[bool] = Field(default=None, description="是否公开")


class TaskFilterParams(PaginationParams):
    """任务过滤参数"""
    status: Optional[str] = Field(default=None, description="任务状态: pending, processing, completed, failed")