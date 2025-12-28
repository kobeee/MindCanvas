"""
数据库模型测试

验证所有模型的基本结构和关系
"""

import sys
sys.path.insert(0, "/Users/elvis/Documents/codes/一个月一个AI项目挑战/2025/12月/MindCanvas/src/backend")

from sqlalchemy import inspect
from app.database import Base
from app.models import User, Asset, FeedItem, Task, Report


def test_model_structure():
    """测试模型结构"""

    # 测试 User 模型
    user_inspector = inspect(User)
    assert user_inspector is not None
    assert User.__tablename__ == "users"
    print(f"✓ User 模型: {User.__tablename__}")

    # 测试 Asset 模型
    asset_inspector = inspect(Asset)
    assert asset_inspector is not None
    assert Asset.__tablename__ == "assets"
    print(f"✓ Asset 模型: {Asset.__tablename__}")

    # 测试 FeedItem 模型
    feed_inspector = inspect(FeedItem)
    assert feed_inspector is not None
    assert FeedItem.__tablename__ == "feed_items"
    print(f"✓ FeedItem 模型: {FeedItem.__tablename__}")

    # 测试 Task 模型
    task_inspector = inspect(Task)
    assert task_inspector is not None
    assert Task.__tablename__ == "generation_tasks"
    print(f"✓ Task 模型: {Task.__tablename__}")

    # 测试 Report 模型
    report_inspector = inspect(Report)
    assert report_inspector is not None
    assert Report.__tablename__ == "reports"
    print(f"✓ Report 模型: {Report.__tablename__}")

    # 测试关系
    assert hasattr(User, "assets")
    assert hasattr(User, "tasks")
    assert hasattr(User, "feed_items")
    assert hasattr(User, "reports")
    print("✓ User 关系: assets, tasks, feed_items, reports")

    assert hasattr(Asset, "user")
    assert hasattr(Asset, "feed_item")
    print("✓ Asset 关系: user, feed_item")

    assert hasattr(FeedItem, "asset")
    assert hasattr(FeedItem, "user")
    assert hasattr(FeedItem, "reports")
    print("✓ FeedItem 关系: asset, user, reports")

    assert hasattr(Task, "user")
    print("✓ Task 关系: user")

    assert hasattr(Report, "feed_item")
    assert hasattr(Report, "reporter")
    print("✓ Report 关系: feed_item, reporter")

    print("\n所有模型结构验证通过！")


if __name__ == "__main__":
    test_model_structure()