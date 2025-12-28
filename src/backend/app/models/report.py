"""
举报模型

定义举报相关的数据库模型
"""

from uuid import UUID as PyUUID

from sqlalchemy import String, Text, Index, ForeignKey
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin, UUIDMixin


class Report(Base, UUIDMixin, TimestampMixin):
    """
    举报表

    存储用户对社区内容的举报
    """
    __tablename__ = "reports"

    # 关联内容
    feed_item_id: Mapped[PyUUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("feed_items.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # 举报人
    reporter_id: Mapped[PyUUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # 举报信息
    reason: Mapped[str] = mapped_column(
        String(100),
        nullable=False
    )
    description: Mapped[str | None] = mapped_column(Text)

    # 举报状态
    status: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        default="pending",
        index=True
    )  # 'pending', 'reviewed', 'resolved', 'dismissed'

    # 关系
    feed_item: Mapped["FeedItem"] = relationship(
        "FeedItem",
        back_populates="reports"
    )
    reporter: Mapped["User"] = relationship(
        "User",
        back_populates="reports",
        foreign_keys="Report.reporter_id"
    )

    # 索引
    __table_args__ = (
        Index("idx_reports_feed_item_id", "feed_item_id"),
        Index("idx_reports_user_id", "reporter_id"),
        Index("idx_reports_status", "status"),
    )

    def __repr__(self) -> str:
        return f"<Report(id={self.id}, reason={self.reason}, status={self.status})>"