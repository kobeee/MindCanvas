#!/bin/bash

# MindCanvas 后端部署脚本
# 用途：一键部署 MindCanvas 后端服务

set -e

echo "=========================================="
echo "MindCanvas 后端部署脚本"
echo "=========================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo -e "${RED}错误: Docker 未安装，请先安装 Docker${NC}"
    exit 1
fi

# 检查 Docker Compose 是否安装
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}错误: Docker Compose 未安装，请先安装 Docker Compose${NC}"
    exit 1
fi

# 检查 .env 文件是否存在
if [ ! -f .env ]; then
    echo -e "${YELLOW}警告: .env 文件不存在，正在从 .env.example 创建...${NC}"
    cp .env.example .env

    # 生成加密密钥
    echo -e "${YELLOW}正在生成加密密钥...${NC}"
    ENCRYPTION_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
    sed -i.bak "s/your_generated_secret_key_here/$ENCRYPTION_KEY/" .env
    rm .env.bak

    echo -e "${GREEN}✓ .env 文件已创建，加密密钥已生成${NC}"
    echo -e "${YELLOW}提示: 请编辑 .env 文件，配置数据库密码和其他参数${NC}"
fi

# 检查加密密钥是否已配置
ENCRYPTION_KEY=$(grep "ENCRYPTION_SECRET_KEY" .env | cut -d '=' -f2)
if [ "$ENCRYPTION_KEY" = "your_generated_secret_key_here" ]; then
    echo -e "${RED}错误: ENCRYPTION_SECRET_KEY 未配置，请编辑 .env 文件设置有效的加密密钥${NC}"
    echo -e "${YELLOW}提示: 使用以下命令生成加密密钥：${NC}"
    echo -e "${YELLOW}python3 -c \"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())\"${NC}"
    exit 1
fi

# 创建存储目录
echo -e "${YELLOW}正在创建存储目录...${NC}"
mkdir -p storage/images/generated
mkdir -p storage/images/uploaded
echo -e "${GREEN}✓ 存储目录已创建${NC}"

# 构建并启动服务
echo -e "${YELLOW}正在构建 Docker 镜像...${NC}"
docker-compose build

echo -e "${YELLOW}正在启动服务...${NC}"
docker-compose up -d

# 等待服务启动
echo -e "${YELLOW}等待服务启动...${NC}"
sleep 10

# 检查服务状态
echo -e "${YELLOW}检查服务状态...${NC}"
docker-compose ps

# 显示日志
echo ""
echo "=========================================="
echo -e "${GREEN}✓ 部署完成！${NC}"
echo "=========================================="
echo ""
echo "服务地址："
echo "  - 后端 API: http://localhost:8000"
echo "  - API 文档: http://localhost:8000/docs"
echo "  - 健康检查: http://localhost:8000/health"
echo ""
echo "常用命令："
echo "  - 查看日志: docker-compose logs -f backend"
echo "  - 停止服务: docker-compose down"
echo "  - 重启服务: docker-compose restart"
echo "  - 查看状态: docker-compose ps"
echo ""
echo "=========================================="