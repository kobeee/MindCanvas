"""
邮件服务模块

提供异步发送邮件功能，使用 Resend API。
支持发送验证码邮件、通知邮件等。
"""

import asyncio
import resend
from typing import Optional
import logging
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential,
    retry_if_exception_type,
    before_sleep_log
)
import urllib3.exceptions

logger = logging.getLogger(__name__)


class EmailServiceError(Exception):
    """邮件服务异常基类"""
    pass


class EmailService:
    """
    邮件服务类

    使用 Resend API 提供异步发送邮件功能。

    使用方法：
        # 初始化服务
        email_service = EmailService(
            api_key="your_resend_api_key",
            from_email="noreply@yourdomain.com",
            from_name="MindCanvas"
        )

        # 发送验证码邮件
        await email_service.send_verification_code(
            to_email="user@example.com",
            code="123456"
        )
    """

    def __init__(
        self,
        api_key: str,
        from_email: str,
        from_name: str = "MindCanvas",
        reply_to: Optional[str] = None
    ):
        """
        初始化邮件服务

        Args:
            api_key: Resend API Key
            from_email: 发件人邮箱地址（需要在 Resend 中验证）
            from_name: 发件人显示名称
            reply_to: 回复邮箱地址（可选）
        """
        self.api_key = api_key
        self.from_email = from_email
        self.from_name = from_name
        self.reply_to = reply_to or from_email
        # 设置 Resend API Key
        resend.api_key = api_key
        logger.info(f"EmailService initialized: from={from_name} <{from_email}>, reply_to={self.reply_to}")

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
            # 在线程池中执行同步的 Resend API 调用
            response = await asyncio.to_thread(
                self._send_via_resend,
                to_email=to_email,
                code=code,
                expiry_minutes=expiry_minutes
            )

            # 检查响应（Resend 返回字典格式 {'id': 'xxx'}）
            if response and isinstance(response, dict) and 'id' in response:
                logger.info(f"Verification code sent to {to_email}, message_id: {response['id']}")
                return True
            else:
                error_msg = f"Resend API returned unexpected response: {response}"
                logger.error(error_msg)
                raise EmailServiceError(error_msg)

        except Exception as e:
            logger.error(f"Failed to send email to {to_email}: {str(e)}")
            raise EmailServiceError(f"Failed to send email: {str(e)}")

    @retry(
        stop=stop_after_attempt(3),
        wait=wait_exponential(multiplier=1, min=2, max=10),
        retry=retry_if_exception_type((
            urllib3.exceptions.SSLError,
            urllib3.exceptions.HTTPError,
            RuntimeError
        )),
        before_sleep=before_sleep_log(logger, logging.WARNING),
        reraise=True
    )
    def _send_via_resend(self, to_email: str, code: str, expiry_minutes: int):
        """
        通过 Resend API 发送邮件（同步方法）

        使用 tenacity 实现重试逻辑，处理 SSL 错误和网络错误。

        Args:
            to_email: 收件人邮箱
            code: 验证码
            expiry_minutes: 验证码过期时间（分钟）

        Returns:
            Resend 响应对象

        Raises:
            RuntimeError: 如果重试 3 次后仍然失败
        """
        params = {
            "from": f"{self.from_name} <{self.from_email}>",
            "to": [to_email],
            "subject": "MindCanvas 验证码",
            "html": self._build_verification_html(code, expiry_minutes),
            "reply_to": self.reply_to
        }

        return resend.Emails.send(params)

    def _build_verification_html(self, code: str, expiry_minutes: int) -> str:
        """
        构建验证码邮件的 HTML 内容

        Args:
            code: 验证码
            expiry_minutes: 验证码过期时间（分钟）

        Returns:
            HTML 格式的邮件内容
        """
        return f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {{
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
                    background-color: #f5f5f5;
                    margin: 0;
                    padding: 20px;
                }}
                .container {{
                    max-width: 600px;
                    margin: 0 auto;
                    background-color: #ffffff;
                    border-radius: 8px;
                    overflow: hidden;
                    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                }}
                .header {{
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    padding: 30px;
                    text-align: center;
                }}
                .header h1 {{
                    color: #ffffff;
                    margin: 0;
                    font-size: 24px;
                    font-weight: 600;
                }}
                .content {{
                    padding: 40px 30px;
                }}
                .code-box {{
                    background-color: #f8f9fa;
                    border: 2px solid #667eea;
                    border-radius: 8px;
                    padding: 20px;
                    text-align: center;
                    margin: 20px 0;
                }}
                .code {{
                    font-size: 32px;
                    font-weight: bold;
                    color: #333333;
                    letter-spacing: 3px;
                    font-family: 'Courier New', monospace;
                }}
                .info {{
                    color: #666666;
                    font-size: 14px;
                    line-height: 1.6;
                    margin-top: 20px;
                }}
                .footer {{
                    background-color: #f8f9fa;
                    padding: 20px;
                    text-align: center;
                    color: #999999;
                    font-size: 12px;
                }}
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <h1>MindCanvas 验证码</h1>
                </div>
                <div class="content">
                    <p style="margin: 0 0 20px 0; color: #333333; font-size: 16px;">
                        您的验证码是：
                    </p>
                    <div class="code-box">
                        <div class="code">{code}</div>
                    </div>
                    <div class="info">
                        <p>验证码有效期为 <strong>{expiry_minutes} 分钟</strong>，请尽快使用。</p>
                        <p style="margin-top: 15px;">如果这不是您的操作，请忽略此邮件。</p>
                    </div>
                </div>
                <div class="footer">
                    <p>此邮件由 MindCanvas 系统自动发送，请勿直接回复。</p>
                </div>
            </div>
        </body>
        </html>
        """