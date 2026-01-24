#!/usr/bin/env python3
"""
查询指定邮箱配额脚本

使用方法：
    python get_email_quota.py <email>

示例：
    python get_email_quota.py test@example.com
"""

import sys
import asyncio
import httpx
from datetime import datetime


async def get_email_quota(email: str, admin_secret: str, base_url: str = "http://127.0.0.1:8009"):
    """查询指定邮箱配额"""
    url = f"{base_url}/api/v1/admin/email-quota/{email}"

    headers = {
        "admin-secret": admin_secret,
        "Content-Type": "application/json"
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, headers=headers)

        if response.status_code == 200:
            result = response.json()
            print(f"✅ Email Quota Information")
            print(f"   Email: {result['email']}")
            print(f"   Initial Quota: {result['initial_quota']}")
            print(f"   Used Quota: {result['used_quota']}")
            print(f"   Remaining Quota: {result['remaining_quota']}")

            if result.get('created_at'):
                dt = datetime.fromisoformat(result['created_at'])
                print(f"   Created At: {dt.strftime('%Y-%m-%d %H:%M:%S')}")
        else:
            error = response.json()
            print(f"❌ Failed: {error.get('detail', 'Unknown error')}")
            sys.exit(1)


def main():
    """主函数"""
    if len(sys.argv) < 2:
        print("Usage: python get_email_quota.py <email>")
        print("Example: python get_email_quota.py test@example.com")
        sys.exit(1)

    email = sys.argv[1]

    # 从环境变量读取管理员密钥
    import os
    admin_secret = os.getenv("ADMIN_SECRET_KEY", "")

    if not admin_secret:
        print("Error: ADMIN_SECRET_KEY environment variable not set")
        sys.exit(1)

    # 从环境变量读取基础 URL（可选）
    base_url = os.getenv("API_BASE_URL", "http://localhost:8008")

    asyncio.run(get_email_quota(email, admin_secret, base_url))


if __name__ == "__main__":
    main()