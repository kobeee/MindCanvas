import logging
import sys
from typing import Optional


def setup_logger(log_level: str = "INFO") -> logging.Logger:
    """
    设置应用日志记录器

    Args:
        log_level: 日志级别 (DEBUG, INFO, WARNING, ERROR, CRITICAL)

    Returns:
        配置好的日志记录器
    """
    # 创建日志记录器
    logger = logging.getLogger("mindcanvas")
    logger.setLevel(getattr(logging, log_level.upper()))

    # 避免重复添加处理器
    if logger.handlers:
        return logger

    # 创建控制台处理器
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(getattr(logging, log_level.upper()))

    # 创建日志格式
    formatter = logging.Formatter(
        "%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )
    console_handler.setFormatter(formatter)

    # 添加处理器到日志记录器
    logger.addHandler(console_handler)

    return logger


def get_logger(name: Optional[str] = None) -> logging.Logger:
    """
    获取日志记录器实例

    Args:
        name: 日志记录器名称，如果为 None 则返回根日志记录器

    Returns:
        日志记录器实例
    """
    if name:
        return logging.getLogger(f"mindcanvas.{name}")
    return logging.getLogger("mindcanvas")