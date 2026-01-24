#!/usr/bin/env python3
"""
邮箱配额注入脚本

使用方法：
    python inject_email_quota.py <email> <quota>

示例：
    python inject_email_quota.py test@example.com 10
"""

import sys
import asyncio
import httpx


async def inject_email_quota(email: str, quota: int, admin_secret: str, base_url: str = "http://127.0.0.1:8009"):
    """注入邮箱配额"""
    url = f"{base_url}/api/v1/admin/email-quota"

    headers = {
        "admin-secret": admin_secret,
        "Content-Type": "application/json"
    }

    payload = {
        "email": email,
        "quota": quota
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, headers=headers, json=payload)

        if response.status_code == 201:
            result = response.json()
            print(f"✅ {result['message']}")
            print(f"   Email: {email}")
            print(f"   Quota: {quota}")
        else:
            error = response.json()
            print(f"❌ Failed: {error.get('detail', 'Unknown error')}")
            sys.exit(1)


def main():
    """主函数"""
    if len(sys.argv) < 3:
        print("Usage: python inject_email_quota.py <email> <quota>")
        print("Example: python inject_email_quota.py test@example.com 10")
        sys.exit(1)

    email = sys.argv[1]
    quota = int(sys.argv[2])

    # 从环境变量读取管理员密钥
    import os
    admin_secret = os.getenv("ADMIN_SECRET_KEY", "")

    if not admin_secret:
        print("Error: ADMIN_SECRET_KEY environment variable not set")
        sys.exit(1)

    # 从环境变量读取基础 URL（可选）
    base_url = os.getenv("API_BASE_URL", "http://localhost:8008")

    asyncio.run(inject_email_quota(email, quota, admin_secret, base_url))


if __name__ == "__main__":
    main()