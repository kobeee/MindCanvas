#!/bin/bash
# MindCanvas Nginx 安装和配置脚本
# 用于在服务器上安装 Nginx 并配置反向代理

set -e

echo "========================================="
echo "MindCanvas Nginx 安装和配置脚本"
echo "========================================="

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 用户运行此脚本"
    exit 1
fi

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "项目根目录: $PROJECT_ROOT"

# 1. 安装 Nginx
echo ""
echo "步骤 1/5: 安装 Nginx..."
apt-get update
apt-get install -y nginx

# 2. 备份默认配置
echo ""
echo "步骤 2/5: 备份默认配置..."
if [ -f /etc/nginx/sites-enabled/default ]; then
    mv /etc/nginx/sites-enabled/default /etc/nginx/sites-enabled/default.bak
    echo "已备份默认配置到 /etc/nginx/sites-enabled/default.bak"
fi

# 3. 复制 MindCanvas Nginx 配置
echo ""
echo "步骤 3/5: 复制 MindCanvas Nginx 配置..."
cp "$PROJECT_ROOT/nginx/mindcanvas.conf" /etc/nginx/sites-available/mindcanvas
ln -sf /etc/nginx/sites-available/mindcanvas /etc/nginx/sites-enabled/mindcanvas
echo "已复制 MindCanvas Nginx 配置"

# 4. 测试 Nginx 配置
echo ""
echo "步骤 4/4: 测试 Nginx 配置..."
nginx -t

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================="
    echo "Nginx 配置测试通过！"
    echo "========================================="
    echo ""
    echo "下一步操作:"
    echo "1. 重启 Nginx: systemctl restart nginx"
    echo "2. 启用 Nginx 开机自启: systemctl enable nginx"
    echo ""
else
    echo ""
    echo "========================================="
    echo "Nginx 配置测试失败！请检查配置文件"
    echo "========================================="
    exit 1
fi