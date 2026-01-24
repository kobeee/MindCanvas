#!/usr/bin/env python3
"""
邮箱配额查询脚本

使用方法：
    python list_email_quotas.py

示例：
    python list_email_quotas.py
"""

import sys
import asyncio
import httpx
from datetime import datetime


async def list_email_quotas(admin_secret: str, base_url: str = "http://127.0.0.1:8009"):
    """查询所有邮箱配额"""
    url = f"{base_url}/api/v1/admin/email-quota"

    headers = {
        "admin-secret": admin_secret,
        "Content-Type": "application/json"
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.get(url, headers=headers)

        if response.status_code == 200:
            result = response.json()
            print(f"✅ Total: {result['total']} email quota(s)")
            print()

            if result['items']:
                print("Email Quotas:")
                print("-" * 80)
                print(f"{'Email':<40} {'Quota':<10} {'Created At':<30}")
                print("-" * 80)

                for item in result['items']:
                    email = item['email']
                    quota = item['initial_quota']
                    created_at = item['created_at']

                    # 格式化时间
                    if created_at:
                        dt = datetime.fromisoformat(created_at)
                        created_at_str = dt.strftime("%Y-%m-%d %H:%M:%S")
                    else:
                        created_at_str = "N/A"

                    print(f"{email:<40} {quota:<10} {created_at_str:<30}")
            else:
                print("No email quotas found.")
        else:
            error = response.json()
            print(f"❌ Failed: {error.get('detail', 'Unknown error')}")
            sys.exit(1)


def main():
    """主函数"""
    # 从环境变量读取管理员密钥
    import os
    admin_secret = os.getenv("ADMIN_SECRET_KEY", "")

    if not admin_secret:
        print("Error: ADMIN_SECRET_KEY environment variable not set")
        sys.exit(1)

    # 从环境变量读取基础 URL（可选）
    base_url = os.getenv("API_BASE_URL", "http://localhost:8008")

    asyncio.run(list_email_quotas(admin_secret, base_url))


if __name__ == "__main__":
    main()