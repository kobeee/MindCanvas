#!/usr/bin/env python3
"""
减少指定邮箱初始配额脚本

使用方法：
    python reduce_email_quota.py <email> <amount>

示例：
    python reduce_email_quota.py test@example.com 5
"""

import sys
import asyncio
import httpx


async def reduce_email_quota(email: str, amount: int, admin_secret: str, base_url: str = "http://127.0.0.1:8009"):
    """减少指定邮箱的初始配额"""
    url = f"{base_url}/api/v1/admin/email-quota/reduce"

    headers = {
        "admin-secret": admin_secret,
        "Content-Type": "application/json"
    }

    payload = {
        "email": email,
        "amount": amount
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(url, headers=headers, json=payload)

        if response.status_code == 200:
            result = response.json()
            print(f"✅ {result['message']}")
            print(f"   Email: {email}")
            print(f"   Old Initial: {result['old_initial']}")
            print(f"   Reduced By: {result['reduced_by']}")
            print(f"   New Initial: {result['new_initial']}")
            print(f"   Used Quota: {result['used_quota']}")
            print(f"   Remaining: {result['remaining_quota']}")
        else:
            error = response.json()
            print(f"❌ Failed: {error.get('detail', 'Unknown error')}")
            sys.exit(1)


def main():
    """主函数"""
    if len(sys.argv) < 3:
        print("Usage: python reduce_email_quota.py <email> <amount>")
        print("Example: python reduce_email_quota.py test@example.com 5")
        sys.exit(1)

    email = sys.argv[1]
    amount = int(sys.argv[2])

    # 从环境变量读取管理员密钥
    import os
    admin_secret = os.getenv("ADMIN_SECRET_KEY", "")

    if not admin_secret:
        print("Error: ADMIN_SECRET_KEY environment variable not set")
        sys.exit(1)

    # 从环境变量读取基础 URL（可选）
    base_url = os.getenv("API_BASE_URL", "http://localhost:8008")

    asyncio.run(reduce_email_quota(email, amount, admin_secret, base_url))


if __name__ == "__main__":
    main()