"""
路由模块

导出所有 API 路由
"""

from app.routers import auth, assets, feed, tasks

__all__ = ["auth", "assets", "feed", "tasks"]