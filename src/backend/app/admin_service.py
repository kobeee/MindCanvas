"""
管理员服务（独立运行，仅本地访问）

提供邮箱配额注入和管理的 API 接口。
此服务只在本地运行，不对外暴露端口，确保绝对安全。

启动方式：
    python -m app.admin_service

或使用部署脚本：
    ./deploy.sh start-admin
"""

import sys
import os

# 添加项目根目录到 Python 路径
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import uvicorn
from fastapi import FastAPI
from app.config import settings
from app.utils.logger import setup_logger

# 设置日志
logger = setup_logger(settings.LOG_LEVEL)

# 创建 FastAPI 应用实例
app = FastAPI(
    title="MindCanvas Admin Service",
    version="1.0.0",
    description="MindCanvas 管理服务（仅本地访问）",
    docs_url="/admin/docs",
    redoc_url="/admin/redoc",
    openapi_url="/admin/openapi.json"
)

# 直接导入 admin 路由模块，避免通过 __init__.py 导入其他路由
import app.routers.admin as admin_module

# 注册管理员路由
app.include_router(admin_module.router)


@app.get("/")
async def root():
    """根路径，返回服务信息"""
    return {
        "service": "MindCanvas Admin Service",
        "version": "1.0.0",
        "status": "running",
        "note": "This service should only run locally"
    }


@app.get("/health")
async def health_check():
    """健康检查接口"""
    return {
        "status": "healthy",
        "service": "MindCanvas Admin Service"
    }


if __name__ == "__main__":
    logger.info("Starting MindCanvas Admin Service...")
    logger.info(f"Admin Secret Key: {'***' if settings.ADMIN_SECRET_KEY else 'NOT SET'}")

    uvicorn.run(
        "app.admin_service:app",
        host="127.0.0.1",  # 只监听本地回环地址
        port=8009,  # 使用独立端口
        log_level=settings.LOG_LEVEL.lower(),
        reload=False
    )