"""
生图任务模型

定义生图任务相关的数据库模型
"""

from datetime import datetime
from uuid import UUID as PyUUID

from sqlalchemy import String, Text, Index, ForeignKey, TIMESTAMP
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database.base import Base, TimestampMixin, UUIDMixin


class Task(Base, UUIDMixin, TimestampMixin):
    """
    生图任务表

    存储用户提交的图片生成任务
    """
    __tablename__ = "generation_tasks"

    # 用户关联
    user_id: Mapped[PyUUID] = mapped_column(
        PG_UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # 任务状态
    status: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
        index=True
    )  # 'pending', 'processing', 'completed', 'failed'

    # 生成参数
    prompt: Mapped[str] = mapped_column(
        Text,
        nullable=False
    )
    base_image: Mapped[str | None] = mapped_column(Text)

    # API Key（加密存储，任务完成后删除）
    encrypted_api_key: Mapped[str | None] = mapped_column(Text)

    # 生成结果
    image_url: Mapped[str | None] = mapped_column(String(500))
    image_expires_at: Mapped[datetime | None] = mapped_column(
        TIMESTAMP(timezone=True),
        index=True
    )
    error_message: Mapped[str | None] = mapped_column(Text)

    # 关系
    user: Mapped["User"] = relationship(
        "User",
        back_populates="tasks"
    )

    # 索引
    __table_args__ = (
        Index("idx_generation_tasks_user_id", "user_id"),
        Index("idx_generation_tasks_status", "status"),
        Index("idx_generation_tasks_created_at", "created_at"),
        Index("idx_generation_tasks_image_expires_at", "image_expires_at"),
    )

    def __repr__(self) -> str:
        return f"<Task(id={self.id}, status={self.status}, prompt={self.prompt[:50]}...)>"