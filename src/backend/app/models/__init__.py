"""
数据模型模块

导出所有数据库模型和 Pydantic 模型
"""

# 数据库模型
from app.models.user import User
from app.models.asset import Asset
from app.models.feed import FeedItem
from app.models.task import Task
from app.models.report import Report

# Pydantic 模型
from app.models.schemas import (
    # 通用响应
    SuccessResponse,
    ErrorResponse,
    # 用户相关
    UserBase,
    UserCreate,
    UserUpdate,
    UserResponse,
    # 认证相关
    LoginRequest,
    LoginResponse,
    # 资源相关
    AssetBase,
    AssetCreate,
    AssetUpdate,
    AssetResponse,
    AssetListResponse,
    # 社区动态相关
    FeedItemBase,
    FeedItemCreate,
    FeedItemUpdate,
    FeedItemResponse,
    FeedListResponse,
    # 任务相关
    TaskBase,
    TaskCreate,
    TaskUpdate,
    TaskResponse,
    TaskStatusResponse,
    TaskListResponse,
    # 举报相关
    ReportBase,
    ReportCreate,
    ReportUpdate,
    ReportResponse,
    ReportListResponse,
    # 分页和过滤参数
    PaginationParams,
    FeedFilterParams,
    AssetFilterParams,
    TaskFilterParams,
)

__all__ = [
    # 数据库模型
    "User",
    "Asset",
    "FeedItem",
    "Task",
    "Report",
    # 通用响应
    "SuccessResponse",
    "ErrorResponse",
    # 用户相关
    "UserBase",
    "UserCreate",
    "UserUpdate",
    "UserResponse",
    # 认证相关
    "LoginRequest",
    "LoginResponse",
    # 资源相关
    "AssetBase",
    "AssetCreate",
    "AssetUpdate",
    "AssetResponse",
    "AssetListResponse",
    # 社区动态相关
    "FeedItemBase",
    "FeedItemCreate",
    "FeedItemUpdate",
    "FeedItemResponse",
    "FeedListResponse",
    # 任务相关
    "TaskBase",
    "TaskCreate",
    "TaskUpdate",
    "TaskResponse",
    "TaskStatusResponse",
    "TaskListResponse",
    # 举报相关
    "ReportBase",
    "ReportCreate",
    "ReportUpdate",
    "ReportResponse",
    "ReportListResponse",
    # 分页和过滤参数
    "PaginationParams",
    "FeedFilterParams",
    "AssetFilterParams",
    "TaskFilterParams",
]