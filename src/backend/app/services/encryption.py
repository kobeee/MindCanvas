"""
加密服务模块

提供 API Key 加密和解密功能，使用 Fernet 对称加密算法（AES-128-CBC + HMAC-SHA256）。

安全特性：
- 使用 Fernet 对称加密（AES-128-CBC + HMAC-SHA256）
- 密钥从环境变量获取，不在代码中硬编码
- 加密数据使用 Base64 编码
- 提供异常处理，确保密钥不在日志中泄露
"""

from cryptography.fernet import Fernet, InvalidToken
from typing import Optional
import logging

logger = logging.getLogger(__name__)


class EncryptionError(Exception):
    """加密服务异常基类"""
    pass


class InvalidKeyError(EncryptionError):
    """无效密钥异常"""
    pass


class DecryptionError(EncryptionError):
    """解密失败异常"""
    pass


class EncryptionService:
    """
    加密服务类

    使用 Fernet 对称加密算法（AES-128-CBC + HMAC-SHA256）提供加密和解密功能。
    适用于 API Key 等敏感数据的加密存储。

    使用方法：
        # 初始化服务
        encryption_service = EncryptionService(secret_key=os.getenv("ENCRYPTION_SECRET_KEY"))

        # 加密
        encrypted = encryption_service.encrypt("my_api_key")

        # 解密
        decrypted = encryption_service.decrypt(encrypted)
    """

    def __init__(self, secret_key: str):
        """
        初始化加密服务

        Args:
            secret_key: 加密密钥（32 字节的 Base64 编码字符串）
                       可以使用 Fernet.generate_key() 生成

        Raises:
            InvalidKeyError: 如果密钥无效或为空

        注意：
            - 密钥必须从环境变量获取，不要在代码中硬编码
            - 密钥长度必须为 32 字节（Base64 编码后为 44 字符）
            - 密钥一旦设置，不应更改，否则无法解密之前加密的数据
        """
        if not secret_key:
            logger.error("Encryption secret key is empty")
            raise InvalidKeyError("ENCRYPTION_SECRET_KEY is required")

        try:
            # 验证密钥格式（Fernet 期望 32 字节的 Base64 编码字符串）
            self.fernet = Fernet(secret_key.encode())
            logger.info("Encryption service initialized successfully")
        except Exception as e:
            logger.error("Failed to initialize encryption service: invalid key format")
            raise InvalidKeyError(f"Invalid encryption key format: {str(e)}")

    def encrypt(self, plaintext: str) -> str:
        """
        加密明文字符串

        Args:
            plaintext: 要加密的明文字符串（如 API Key）

        Returns:
            Base64 编码的密文字符串

        Raises:
            EncryptionError: 如果加密失败

        注意：
            - 加密后的数据包含时间戳，每次加密结果不同
            - 返回的密文可以直接存储在数据库中
            - 加密过程中不会在日志中记录明文或密文
        """
        if not plaintext:
            logger.warning("Attempted to encrypt empty string")
            raise EncryptionError("Cannot encrypt empty string")

        try:
            # 将明文转换为字节并加密
            encrypted_bytes = self.fernet.encrypt(plaintext.encode('utf-8'))
            # 将加密后的字节转换为 Base64 字符串
            encrypted_text = encrypted_bytes.decode('utf-8')

            logger.debug("Data encrypted successfully")
            return encrypted_text

        except Exception as e:
            logger.error(f"Encryption failed: {str(e)}")
            raise EncryptionError(f"Failed to encrypt data: {str(e)}")

    def decrypt(self, ciphertext: str) -> str:
        """
        解密 Base64 编码的密文字符串

        Args:
            ciphertext: Base64 编码的密文字符串（由 encrypt 方法生成）

        Returns:
            解密后的明文字符串

        Raises:
            DecryptionError: 如果解密失败（密文无效、密钥不匹配或数据被篡改）
            EncryptionError: 如果密文为空

        注意：
            - 如果密钥不匹配或数据被篡改，会抛出 DecryptionError
            - 解密过程中不会在日志中记录明文或密文
            - 解密失败可能是因为：密钥错误、密文损坏、数据被篡改
        """
        if not ciphertext:
            logger.warning("Attempted to decrypt empty string")
            raise EncryptionError("Cannot decrypt empty string")

        try:
            # 将 Base64 字符串转换为字节并解密
            decrypted_bytes = self.fernet.decrypt(ciphertext.encode('utf-8'))
            # 将解密后的字节转换为字符串
            decrypted_text = decrypted_bytes.decode('utf-8')

            logger.debug("Data decrypted successfully")
            return decrypted_text

        except InvalidToken as e:
            # Fernet 会抛出 InvalidToken 异常，表示密文无效或密钥不匹配
            logger.error(f"Decryption failed: invalid token (possibly wrong key or corrupted data)")
            raise DecryptionError("Failed to decrypt: invalid token (wrong key or corrupted data)")

        except Exception as e:
            logger.error(f"Decryption failed: {str(e)}")
            raise DecryptionError(f"Failed to decrypt data: {str(e)}")

    def is_valid_token(self, ciphertext: str) -> bool:
        """
        验证密文是否有效（不解密）

        Args:
            ciphertext: Base64 编码的密文字符串

        Returns:
            True 如果密文有效，False 如果密文无效

        注意：
            - 此方法只验证密文格式和完整性，不解密内容
            - 可以用于快速验证密文是否有效，而不需要解密
        """
        if not ciphertext:
            return False

        try:
            # 尝试解密，如果成功则密文有效
            self.fernet.decrypt(ciphertext.encode('utf-8'))
            return True
        except (InvalidToken, Exception):
            return False

    @staticmethod
    def generate_key() -> str:
        """
        生成新的加密密钥

        Returns:
            32 字节的 Base64 编码密钥字符串

        注意：
            - 每次调用都会生成不同的密钥
            - 生成的密钥应该存储在环境变量中
            - 密钥一旦设置，不应更改，否则无法解密之前加密的数据

        使用方法：
            import os
            from app.services.encryption import EncryptionService

            # 生成密钥
            key = EncryptionService.generate_key()
            print(f"Generated key: {key}")

            # 将密钥添加到 .env 文件
            # ENCRYPTION_SECRET_KEY=your_generated_key_here
        """
        return Fernet.generate_key().decode('utf-8')