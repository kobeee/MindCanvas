"""
社区动态模型

定义社区动态相关的数据库模型
"""

from uuid import UUID as PyUUID

from sqlalchemy import Integer, String, Index, ForeignKey
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin, UUIDMixin


class FeedItem(Base, UUIDMixin, TimestampMixin):
    """
    社区动态表

    存储用户发布到社区的作品
    """
    __tablename__ = "feed_items"

    # 关联资源
    asset_id: Mapped[PyUUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("assets.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True
    )

    # 作者
    user_id: Mapped[PyUUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # 发布信息
    title: Mapped[str | None] = mapped_column(String(255))
    likes_count: Mapped[int] = mapped_column(
        Integer,
        default=0,
        nullable=False
    )
    published_at: Mapped[str] = mapped_column(
        String(50),
        nullable=False
    )

    # 关系
    asset: Mapped["Asset"] = relationship(
        "Asset",
        back_populates="feed_item"
    )
    user: Mapped["User"] = relationship(
        "User",
        back_populates="feed_items"
    )
    reports: Mapped[list["Report"]] = relationship(
        "Report",
        back_populates="feed_item",
        cascade="all, delete-orphan"
    )

    # 索引
    __table_args__ = (
        Index("idx_feed_items_asset_id", "asset_id"),
        Index("idx_feed_items_user_id", "user_id"),
        Index("idx_feed_items_published_at", "published_at"),
    )

    def __repr__(self) -> str:
        return f"<FeedItem(id={self.id}, title={self.title}, likes_count={self.likes_count})>"