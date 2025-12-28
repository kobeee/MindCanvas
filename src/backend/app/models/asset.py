"""
资源模型

定义资源/图片相关的数据库模型
"""

from uuid import UUID as PyUUID

from sqlalchemy import Boolean, String, Text, Index, ForeignKey
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin, UUIDMixin


class Asset(Base, UUIDMixin, TimestampMixin):
    """
    资源表

    存储用户上传的图片和 AI 生成的图片
    """
    __tablename__ = "assets"

    # 用户关联
    user_id: Mapped[PyUUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # 资源信息
    url: Mapped[str] = mapped_column(
        String(500),
        nullable=False
    )
    type: Mapped[str] = mapped_column(
        String(50),
        nullable=False
    )  # 'upload', 'generated'
    prompt: Mapped[str | None] = mapped_column(Text)
    model_version: Mapped[str | None] = mapped_column(String(100))

    # 公开状态
    is_public: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False
    )

    # 关系
    user: Mapped["User"] = relationship(
        "User",
        back_populates="assets"
    )
    feed_item: Mapped["FeedItem | None"] = relationship(
        "FeedItem",
        back_populates="asset",
        uselist=False,
        cascade="all, delete-orphan"
    )

    # 索引
    __table_args__ = (
        Index("idx_assets_user_id", "user_id"),
        Index("idx_assets_type", "type"),
        Index("idx_assets_is_public", "is_public"),
        Index("idx_assets_created_at", "created_at"),
    )

    def __repr__(self) -> str:
        return f"<Asset(id={self.id}, type={self.type}, is_public={self.is_public})>"