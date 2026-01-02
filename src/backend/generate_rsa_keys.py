"""
生成 RSA 密钥对

用于 iOS 端 API Key 安全传输
"""

from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import base64

# 生成 RSA 密钥对
private_key = rsa.generate_private_key(
    public_exponent=65537,
    key_size=2048,
    backend=default_backend()
)

public_key = private_key.public_key()

# 导出私钥（PKCS#8 格式）
private_key_pem = private_key.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption()
)

# 导出公钥（SubjectPublicKeyInfo 格式）
public_key_pem = public_key.public_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PublicFormat.SubjectPublicKeyInfo
)

# Base64 编码
private_key_base64 = base64.b64encode(private_key_pem).decode('utf-8')
public_key_base64 = base64.b64encode(public_key_pem).decode('utf-8')

print("=" * 80)
print("RSA 密钥对生成成功")
print("=" * 80)
print()
print("公钥（Base64 编码）:")
print("-" * 80)
print(public_key_base64)
print()
print("私钥（Base64 编码）:")
print("-" * 80)
print(private_key_base64)
print()
print("=" * 80)
print("使用说明:")
print("1. 将公钥添加到 config.py 的 RSA_PUBLIC_KEY_BASE64")
print("2. 将私钥添加到 config.py 的 RSA_PRIVATE_KEY_BASE64")
print("3. 更新 iOS 端 RSAEncryptionService.swift 中的公钥")
print("=" * 80)