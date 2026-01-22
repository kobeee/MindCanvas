"""
用户模型

定义用户相关的数据库模型
"""

from datetime import datetime
from sqlalchemy import String, Index, TIMESTAMP
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin, UUIDMixin


class User(Base, UUIDMixin, TimestampMixin):
    """
    用户表

    存储用户基本信息和认证信息
    """
    __tablename__ = "users"

    # 基本信息
    email: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        index=True,
        nullable=False
    )
    username: Mapped[str | None] = mapped_column(String(100))

    # 认证信息
    auth_provider: Mapped[str] = mapped_column(
        String(50),
        nullable=False
    )  # 'apple', 'google', 'github', 'email'
    provider_id: Mapped[str | None] = mapped_column(String(255))

    # Refresh Token
    refresh_token: Mapped[str | None] = mapped_column(String(500))
    refresh_token_expires_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))

    # API 提供商配置
    api_provider: Mapped[str] = mapped_column(
        String(50),
        default="google",
        nullable=False,
        index=True
    )  # 'google' or 'laozhang'
    free_quota: Mapped[int] = mapped_column(default=0)  # 免费额度
    total_quota_used: Mapped[int] = mapped_column(default=0)  # 总使用次数

    # 订阅信息（为未来订阅功能预留）
    subscription_tier: Mapped[str] = mapped_column(
        String(50),
        default="free",
        index=True
    )  # 'free', 'pro', 'enterprise'
    subscription_expires_at: Mapped[datetime | None] = mapped_column(TIMESTAMP(timezone=True))

    # 头像
    avatar_url: Mapped[str | None] = mapped_column(String(500))

    # 关系
    assets: Mapped[list["Asset"]] = relationship(
        "Asset",
        back_populates="user",
        cascade="all, delete-orphan"
    )
    tasks: Mapped[list["Task"]] = relationship(
        "Task",
        back_populates="user",
        cascade="all, delete-orphan"
    )
    feed_items: Mapped[list["FeedItem"]] = relationship(
        "FeedItem",
        back_populates="user",
        cascade="all, delete-orphan"
    )
    reports: Mapped[list["Report"]] = relationship(
        "Report",
        back_populates="reporter",
        foreign_keys="Report.reporter_id",
        cascade="all, delete-orphan"
    )

    # 索引
    __table_args__ = (
        Index("idx_users_email", "email"),
        Index("idx_users_provider_id", "provider_id"),
        Index("idx_users_refresh_token", "refresh_token"),
        Index("idx_users_api_provider", "api_provider"),
        Index("idx_users_subscription_tier", "subscription_tier"),
    )

    def __repr__(self) -> str:
        return f"<User(id={self.id}, email={self.email}, username={self.username})>"