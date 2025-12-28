"""
加密服务测试

测试 EncryptionService 类的所有功能。
"""

import pytest
from app.services.encryption import (
    EncryptionService,
    EncryptionError,
    InvalidKeyError,
    DecryptionError
)


class TestEncryptionService:
    """加密服务测试类"""

    def test_generate_key(self):
        """测试生成密钥"""
        key = EncryptionService.generate_key()
        assert key is not None
        assert isinstance(key, str)
        assert len(key) == 44  # Fernet 密钥长度为 32 字节，Base64 编码后为 44 字符

    def test_init_with_valid_key(self):
        """测试使用有效密钥初始化"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)
        assert service is not None
        assert service.fernet is not None

    def test_init_with_empty_key(self):
        """测试使用空密钥初始化"""
        with pytest.raises(InvalidKeyError) as exc_info:
            EncryptionService("")
        assert "required" in str(exc_info.value).lower()

    def test_init_with_none_key(self):
        """测试使用 None 密钥初始化"""
        with pytest.raises(InvalidKeyError) as exc_info:
            EncryptionService(None)
        assert "required" in str(exc_info.value).lower()

    def test_init_with_invalid_key(self):
        """测试使用无效密钥初始化"""
        with pytest.raises(InvalidKeyError):
            EncryptionService("invalid_key_format")

    def test_encrypt_decrypt(self):
        """测试基本的加密和解密"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)

        plaintext = "my_api_key_12345"
        encrypted = service.encrypt(plaintext)
        decrypted = service.decrypt(encrypted)

        assert decrypted == plaintext
        assert encrypted != plaintext

    def test_encrypt_empty_string(self):
        """测试加密空字符串"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)

        with pytest.raises(EncryptionError) as exc_info:
            service.encrypt("")
        assert "empty" in str(exc_info.value).lower()

    def test_decrypt_empty_string(self):
        """测试解密空字符串"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)

        with pytest.raises(EncryptionError) as exc_info:
            service.decrypt("")
        assert "empty" in str(exc_info.value).lower()

    def test_decrypt_with_wrong_key(self):
        """测试使用错误的密钥解密"""
        key1 = EncryptionService.generate_key()
        key2 = EncryptionService.generate_key()

        service1 = EncryptionService(key1)
        service2 = EncryptionService(key2)

        plaintext = "my_api_key_12345"
        encrypted = service1.encrypt(plaintext)

        # 使用不同的密钥解密应该失败
        with pytest.raises(DecryptionError):
            service2.decrypt(encrypted)

    def test_decrypt_invalid_ciphertext(self):
        """测试解密无效的密文"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)

        with pytest.raises(DecryptionError):
            service.decrypt("invalid_ciphertext")

    def test_encrypt_unicode(self):
        """测试加密 Unicode 字符串"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)

        plaintext = "你好世界！Hello World! 🎨"
        encrypted = service.encrypt(plaintext)
        decrypted = service.decrypt(encrypted)

        assert decrypted == plaintext

    def test_encrypt_long_string(self):
        """测试加密长字符串"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)

        plaintext = "a" * 10000  # 10000 个字符
        encrypted = service.encrypt(plaintext)
        decrypted = service.decrypt(encrypted)

        assert decrypted == plaintext

    def test_encrypt_api_key(self):
        """测试加密 API Key"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)

        # 模拟真实的 API Key
        plaintext = "AIzaSyDhI8hQf-7H9jK0lM1nO2pQ3rS4tU5vW6xY"
        encrypted = service.encrypt(plaintext)
        decrypted = service.decrypt(encrypted)

        assert decrypted == plaintext
        assert encrypted != plaintext

    def test_is_valid_token(self):
        """测试验证密文有效性"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)

        plaintext = "my_api_key_12345"
        encrypted = service.encrypt(plaintext)

        assert service.is_valid_token(encrypted) is True
        assert service.is_valid_token("invalid_token") is False
        assert service.is_valid_token("") is False

    def test_different_encryptions(self):
        """测试相同明文多次加密产生不同密文"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)

        plaintext = "my_api_key_12345"
        encrypted1 = service.encrypt(plaintext)
        encrypted2 = service.encrypt(plaintext)

        # Fernet 每次加密都会产生不同的结果（因为包含时间戳）
        assert encrypted1 != encrypted2

        # 但解密后应该得到相同的明文
        assert service.decrypt(encrypted1) == plaintext
        assert service.decrypt(encrypted2) == plaintext

    def test_encrypt_special_characters(self):
        """测试加密包含特殊字符的字符串"""
        key = EncryptionService.generate_key()
        service = EncryptionService(key)

        plaintext = "!@#$%^&*()_+-=[]{}|;':\",./<>?"
        encrypted = service.encrypt(plaintext)
        decrypted = service.decrypt(encrypted)

        assert decrypted == plaintext


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
