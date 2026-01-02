"""
RSA 加密服务模块

提供 RSA 公钥加密和私钥解密功能。
用于 iOS 端 API Key 的安全传输。
"""

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import logging
import os
from typing import Tuple

logger = logging.getLogger(__name__)


class RSAEncryptionError(Exception):
    """RSA 加密服务异常"""
    pass


class RSAEncryptionService:
    """
    RSA 加密服务类

    提供 RSA 公钥加密和私钥解密功能。
    用于 iOS 端 API Key 的安全传输。

    安全特性：
    - 使用 OAEP 填充（SHA-256）
    - 公钥加密，私钥解密
    - 私钥使用 PKCS#8 格式存储
    """

    def __init__(self, private_key_pem: bytes = None, public_key_pem: bytes = None):
        """
        初始化 RSA 加密服务

        Args:
            private_key_pem: PEM 格式的私钥（可选，如果不提供则生成新密钥对）
            public_key_pem: PEM 格式的公钥（可选，如果不提供则从私钥派生）

        Raises:
            RSAEncryptionError: 如果密钥无效
        """
        if private_key_pem:
            # 使用提供的私钥
            self.private_key = serialization.load_pem_private_key(
                private_key_pem,
                password=None,
                backend=default_backend()
            )
            self.public_key = self.private_key.public_key()
        else:
            # 生成新的 RSA 密钥对
            self.private_key = rsa.generate_private_key(
                public_exponent=65537,
                key_size=2048,
                backend=default_backend()
            )
            self.public_key = self.private_key.public_key()
            logger.info("New RSA key pair generated")

    @classmethod
    def from_pem_files(cls, private_key_path: str, public_key_path: str = None) -> "RSAEncryptionService":
        """
        从 PEM 文件加载密钥对

        Args:
            private_key_path: 私钥文件路径
            public_key_path: 公钥文件路径（可选，如果不提供则从私钥派生）

        Returns:
            RSAEncryptionService 实例
        """
        with open(private_key_path, "rb") as f:
            private_key_pem = f.read()

        public_key_pem = None
        if public_key_path and os.path.exists(public_key_path):
            with open(public_key_path, "rb") as f:
                public_key_pem = f.read()

        return cls(private_key_pem=private_key_pem, public_key_pem=public_key_pem)

    def encrypt(self, plaintext: str) -> bytes:
        """
        使用公钥加密明文

        Args:
            plaintext: 要加密的明文字符串

        Returns:
            加密后的字节数据

        Raises:
            RSAEncryptionError: 如果加密失败
        """
        if not plaintext:
            logger.warning("Attempted to encrypt empty string")
            raise RSAEncryptionError("Cannot encrypt empty string")

        try:
            ciphertext = self.public_key.encrypt(
                plaintext.encode('utf-8'),
                padding.OAEP(
                    mgf=padding.MGF1(algorithm=hashes.SHA256()),
                    algorithm=hashes.SHA256(),
                    label=None
                )
            )
            logger.debug("Data encrypted successfully with RSA public key")
            return ciphertext

        except Exception as e:
            logger.error(f"RSA encryption failed: {str(e)}")
            raise RSAEncryptionError(f"Failed to encrypt data: {str(e)}")

    def decrypt(self, ciphertext: bytes) -> str:
        """
        使用私钥解密密文

        Args:
            ciphertext: 加密后的字节数据

        Returns:
            解密后的明文字符串

        Raises:
            RSAEncryptionError: 如果解密失败
        """
        if not ciphertext:
            logger.warning("Attempted to decrypt empty data")
            raise RSAEncryptionError("Cannot decrypt empty data")

        try:
            plaintext = self.private_key.decrypt(
                ciphertext,
                padding.OAEP(
                    mgf=padding.MGF1(algorithm=hashes.SHA256()),
                    algorithm=hashes.SHA256(),
                    label=None
                )
            )
            logger.debug("Data decrypted successfully with RSA private key")
            return plaintext.decode('utf-8')

        except Exception as e:
            logger.error(f"RSA decryption failed: {str(e)}")
            raise RSAEncryptionError(f"Failed to decrypt data: {str(e)}")

    def get_public_key_pem(self) -> bytes:
        """
        获取公钥的 PEM 格式

        Returns:
            PEM 格式的公钥字节
        """
        return self.public_key.public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        )

    def get_public_key_pem_base64(self) -> str:
        """
        获取公钥的 Base64 编码字符串（用于 API 响应）

        Returns:
            Base64 编码的公钥字符串
        """
        import base64
        return base64.b64encode(self.get_public_key_pem()).decode('utf-8')

    def save_keys(self, private_key_path: str, public_key_path: str = None):
        """
        保存密钥对到文件

        Args:
            private_key_path: 私钥文件路径
            public_key_path: 公钥文件路径（可选）
        """
        # 保存私钥
        private_key_pem = self.private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        )
        with open(private_key_path, "wb") as f:
            f.write(private_key_pem)

        # 保存公钥
        if public_key_path:
            with open(public_key_path, "wb") as f:
                f.write(self.get_public_key_pem())

        logger.info(f"RSA keys saved to {private_key_path} and {public_key_path}")

    @staticmethod
    def generate_keypair() -> Tuple[bytes, bytes]:
        """
        生成新的 RSA 密钥对

        Returns:
            (private_key_pem, public_key_pem) 元组
        """
        service = RSAEncryptionService()
        return service.private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption()
        ), service.get_public_key_pem()


def load_public_key_from_base64(public_key_base64: str):
    """
    从 Base64 字符串加载公钥

    Args:
        public_key_base64: Base64 编码的公钥字符串

    Returns:
        RSAPublicKey 对象
    """
    import base64
    public_key_pem = base64.b64decode(public_key_base64)
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.backends import default_backend
    return serialization.load_pem_public_key(public_key_pem, backend=default_backend())
