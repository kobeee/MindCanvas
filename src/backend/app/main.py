from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
import os

from app.config import settings
from app.utils.logger import setup_logger

# 设置日志
logger = setup_logger(settings.LOG_LEVEL)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理"""
    logger.info("Starting MindCanvas Backend...")

    # 启动清理调度器
    try:
        from app.services.cleanup_service import CleanupService, start_cleanup_scheduler
        from app.storage.image_storage import ImageStorage
        from app.database.connection import get_db

        # 获取数据库会话（不使用 async for，避免会话被关闭）
        db_gen = get_db()
        db = await db_gen.__anext__()

        # 创建清理服务
        cleanup_service = CleanupService(
            db=db,
            storage=ImageStorage(),
            retention_days=settings.IMAGE_RETENTION_DAYS
        )

        # 启动调度器
        start_cleanup_scheduler(cleanup_service)
        logger.info("Cleanup scheduler started successfully")
    except Exception as e:
        logger.error(f"Failed to start cleanup scheduler: {str(e)}")

    yield
    logger.info("Shutting down MindCanvas Backend...")


# 创建 FastAPI 应用实例
app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="MindCanvas 后端服务，提供用户认证、资源管理、社区功能和 AI 生图服务",
    lifespan=lifespan,
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json"
)

# CORS 配置
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:8000",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:8000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/")
async def root():
    """根路径，返回 API 信息"""
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "status": "running"
    }


@app.get("/health")
async def health_check():
    """健康检查接口"""
    return {
        "status": "healthy",
        "service": settings.APP_NAME
    }


@app.get("/api/v1")
async def api_info():
    """API v1 信息"""
    return {
        "version": "v1",
        "endpoints": {
            "auth": "/api/v1/auth",
            "assets": "/api/v1/assets",
            "generate": "/api/v1/generate",
            "feed": "/api/v1/feed"
        }
    }


# 全局异常处理
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={
            "error": {
                "code": "INTERNAL_ERROR",
                "message": "Internal server error",
                "details": str(exc) if settings.DEBUG else None
            }
        }
    )


# 导入路由
from app.routers import auth, assets, feed, tasks, users

# 注册路由
app.include_router(auth.router)
app.include_router(assets.router)
app.include_router(feed.router)
app.include_router(tasks.router)
app.include_router(users.router)

# 配置静态文件服务
# 使用配置中的存储路径（支持 Docker 环境变量覆盖）
STORAGE_DIR = settings.IMAGE_STORAGE_PATH

# 确保存储目录存在
os.makedirs(STORAGE_DIR, exist_ok=True)

# 挂载静态文件服务
app.mount("/images", StaticFiles(directory=STORAGE_DIR), name="images")

logger.info(f"Static files mounted at /images -> {STORAGE_DIR}")