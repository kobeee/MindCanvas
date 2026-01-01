"""
邮件服务模块

提供异步发送邮件功能，使用 SMTP 协议。
支持发送验证码邮件、通知邮件等。
"""

import aiosmtplib
from email.message import EmailMessage
from typing import Optional
import logging
import ssl

logger = logging.getLogger(__name__)


class EmailServiceError(Exception):
    """邮件服务异常基类"""
    pass


class EmailService:
    """
    邮件服务类

    使用 aiosmtplib 提供异步发送邮件功能。

    使用方法：
        # 初始化服务（TLS 方式，端口 587）
        email_service = EmailService(
            host="smtp.gmail.com",
            port=587,
            username="your_email@gmail.com",
            password="your_password"
        )

        # 初始化服务（SSL 方式，端口 465）
        email_service = EmailService(
            host="smtp.gmail.com",
            port=465,
            username="your_email@gmail.com",
            password="your_password",
            use_ssl=True
        )

        # 发送验证码邮件
        await email_service.send_verification_code(
            to_email="user@example.com",
            code="123456"
        )
    """

    def __init__(
        self,
        host: str,
        port: int,
        username: str,
        password: str,
        use_tls: bool = True,
        use_ssl: bool = False
    ):
        """
        初始化邮件服务

        Args:
            host: SMTP 服务器地址
            port: SMTP 服务器端口
            username: 邮箱账号
            password: 邮箱密码或应用专用密码
            use_tls: 是否使用 TLS 加密（STARTTLS）
            use_ssl: 是否使用 SSL 加密
        """
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.use_tls = use_tls
        self.use_ssl = use_ssl
        logger.info(f"EmailService initialized: {host}:{port}, TLS={use_tls}, SSL={use_ssl}")

    async def send_verification_code(
        self,
        to_email: str,
        code: str,
        expiry_minutes: int = 5
    ) -> bool:
        """
        发送验证码邮件

        Args:
            to_email: 收件人邮箱
            code: 验证码
            expiry_minutes: 验证码过期时间（分钟）

        Returns:
            是否发送成功

        Raises:
            EmailServiceError: 如果发送失败
        """
        try:
            # 创建邮件消息
            message = EmailMessage()
            message["From"] = self.username
            message["To"] = to_email
            message["Subject"] = "MindCanvas 验证码"

            # 邮件正文
            body = f"""
            您的 MindCanvas 验证码是：{code}

            验证码有效期为 {expiry_minutes} 分钟，请尽快使用。

            如果这不是您的操作，请忽略此邮件。
            """

            message.set_content(body.strip())

            # 发送邮件
            if self.use_ssl:
                # 使用 SSL 连接（端口 465）
                context = ssl.create_default_context()
                await aiosmtplib.send(
                    message,
                    hostname=self.host,
                    port=self.port,
                    username=self.username,
                    password=self.password,
                    use_tls=True,  # SSL 需要 use_tls=True
                    tls_context=context
                )
            else:
                # 使用 TLS（STARTTLS，端口 587）
                await aiosmtplib.send(
                    message,
                    hostname=self.host,
                    port=self.port,
                    username=self.username,
                    password=self.password,
                    use_tls=self.use_tls
                )

            logger.info(f"Verification code sent to {to_email}")
            return True

        except Exception as e:
            logger.error(f"Failed to send email to {to_email}: {str(e)}")
            raise EmailServiceError(f"Failed to send email: {str(e)}")