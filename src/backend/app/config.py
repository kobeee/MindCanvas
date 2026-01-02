from pydantic_settings import BaseSettings
from typing import Optional


class Settings(BaseSettings):
    """应用配置管理类，使用 Pydantic Settings 管理环境变量"""

    # 应用基础配置
    APP_NAME: str = "MindCanvas Backend"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False

    # 服务器配置
    HOST: str = "0.0.0.0"
    PORT: int = 8000

    # 数据库配置
    DATABASE_URL: str = "postgresql://mindcanvas:mindcanvas@localhost:5432/mindcanvas"

    # 邮件服务配置
    SMTP_HOST: str = "smtp.gmail.com"
    SMTP_PORT: int = 587
    SMTP_USERNAME: str = ""
    SMTP_PASSWORD: str = ""
    SMTP_USE_TLS: bool = True

    # Redis 配置
    REDIS_URL: str = "redis://localhost:6379/0"

    # 加密密钥（用于 API Key 加密存储）
    ENCRYPTION_SECRET_KEY: str

    # JWT 配置
    JWT_SECRET_KEY: str = "your-jwt-secret-key-change-in-production"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 天

    # 日志配置
    LOG_LEVEL: str = "INFO"

    # 图片存储配置
    IMAGE_STORAGE_PATH: str = "/app/storage/images"
    IMAGE_BASE_URL: str = "http://localhost:8000/images"

    # 任务清理配置
    TASK_CLEANUP_INTERVAL: int = 3600  # 秒
    TASK_RETENTION_HOURS: int = 24  # 任务保留时间
    IMAGE_RETENTION_DAYS: int = 7  # 图片保留时间

    # API 速率限制
    RATE_LIMIT_PER_MINUTE: int = 60

    # 内容安全审核
    ENABLE_STRICT_AUDIT: bool = False

    # Google OAuth 配置
    GOOGLE_CLIENT_ID: str = "356898960552-aq7iv1iooas0ihn2j391becn9jvsuoou.apps.googleusercontent.com"

    # GitHub OAuth 配置
    GITHUB_CLIENT_ID: str = "Ov23li3PdYwr0zVzdJjw"
    GITHUB_CLIENT_SECRET: str = "8d5fcdddc76d312d937108c01450c13018301a07"

    # RSA 加密配置（用于 iOS 端 API Key 安全传输）
    # iOS 端使用此公钥加密 API Key，后端用私钥解密
    RSA_PUBLIC_KEY_BASE64: str = "LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQklqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FROEFNSUlCQ2dLQ0FRRUFxdmVhc2pTbXYzMFluMkJONkVzcApybWFTYks1WHorbFJQZjZSeW5EdnZWRDAxUVlYMTVmaThzK1RJZGhvMStTNGtibVQ0T1VpZTZJUEJpc1ZkeVFiCldXUGZNbXdmV0tVMCtDWEhzZzdFOXFHbzFETDEyOFlnWnA0SmdNUEVmUEEvMDVrR0h6YkpuQzRGcUQ4WUtIVXMKaVRXU3JnQ296K3RxYy9UUndXbEM0WDF1dUtzZWN2cXNNZmZsQmVUZVdiUmE5TjNDY2RYQTdOWSt1WWcwakFtSQp2Z284WHB4MVlTQXN6eXQwL2lpUVdkcW82UGcvNEtsK2QvYnhzeUxvY1dUMDhxdURlOHVnYklPaTB5eEVnUTNzCld0bUtqdVJhMXh5bVQxWnpTL1k2SjlIUkR1MThvMldGYWhLY3diOXdZWitTV1pSa0E0eEh5UlU4ZUJEcS92dHAKT1FJREFRQUIKLS0tLS1FTkQgUFVCTElDIEtFWS0tLS0tCg=="

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


# 全局配置实例
settings = Settings()