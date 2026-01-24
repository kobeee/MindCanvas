#!/bin/bash

# MindCanvas 后端部署脚本
# 用途：一键部署、管理 MindCanvas 后端服务
# 功能：部署、启动、停止、重启、清理、重置、注入邮箱配额

set -e

echo "=========================================="
echo "MindCanvas 后端管理脚本"
echo "=========================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# 获取脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 显示帮助信息
show_help() {
    echo "用法: ./deploy.sh [命令]"
    echo ""
    echo "命令:"
    echo "  deploy       部署并启动服务（默认）"
    echo "  start        启动服务"
    echo "  stop         停止服务"
    echo "  restart      重启服务"
    echo "  status       查看服务状态"
    echo "  logs         查看后端日志"
    echo "  rebuild      重新构建并启动服务"
    echo "  clean        清理服务（保留数据）"
    echo "  reset        重置服务（删除所有数据）"
    echo "  start-admin  启动管理服务（仅本地）"
    echo "  stop-admin   停止管理服务"
    echo "  quota        注入邮箱配额"
    echo "  list-quota   查看邮箱配额"
    echo "  help         显示帮助信息"
    echo ""
    echo "示例:"
    echo "  ./deploy.sh deploy          # 部署并启动服务"
    echo "  ./deploy.sh start-admin     # 启动管理服务"
    echo "  ./deploy.sh quota test@example.com 10  # 注入邮箱配额"
    echo "  ./deploy.sh list-quota      # 查看邮箱配额"
}

# 检查 .env 文件
check_env() {
    if [ ! -f .env ]; then
        echo -e "${YELLOW}警告: .env 文件不存在，正在从 .env.example 创建...${NC}"
        cp .env.example .env

        # 生成加密密钥
        echo -e "${YELLOW}正在生成加密密钥...${NC}"
        ENCRYPTION_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
        sed -i.bak "s/your_generated_secret_key_here/$ENCRYPTION_KEY/" .env
        rm .env.bak

        # 生成管理员密钥
        echo -e "${YELLOW}正在生成管理员密钥...${NC}"
        ADMIN_KEY=$(python3 -c "import secrets; print(secrets.token_urlsafe(32))")
        sed -i.bak "s/your-admin-secret-key-change-in-production/$ADMIN_KEY/" .env
        rm .env.bak

        echo -e "${GREEN}✓ .env 文件已创建，密钥已生成${NC}"
        echo -e "${YELLOW}提示: 请编辑 .env 文件，配置 Resend API Key 和其他参数${NC}"
        echo -e "${YELLOW}管理员密钥: $ADMIN_KEY${NC}"
    fi

    # 检查加密密钥是否已配置
    ENCRYPTION_KEY=$(grep "ENCRYPTION_SECRET_KEY" .env | cut -d '=' -f2)
    if [ "$ENCRYPTION_KEY" = "your_generated_secret_key_here" ]; then
        echo -e "${RED}错误: ENCRYPTION_SECRET_KEY 未配置${NC}"
        exit 1
    fi

    # 检查管理员密钥是否已配置
    ADMIN_KEY=$(grep "ADMIN_SECRET_KEY" .env | cut -d '=' -f2)
    if [ "$ADMIN_KEY" = "your-admin-secret-key-change-in-production" ]; then
        echo -e "${YELLOW}警告: ADMIN_SECRET_KEY 未配置，将使用默认值${NC}"
    fi
}

# 创建存储目录
create_storage_dirs() {
    echo -e "${YELLOW}正在创建存储目录...${NC}"
    mkdir -p storage/images/generated
    mkdir -p storage/images/uploaded
    echo -e "${GREEN}✓ 存储目录已创建${NC}"
}

# 部署服务
deploy() {
    check_env
    create_storage_dirs

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

    show_success
}

# 启动服务
start() {
    check_env
    echo -e "${YELLOW}正在启动服务...${NC}"
    docker-compose up -d
    sleep 5
    docker-compose ps
    echo -e "${GREEN}✓ 服务已启动${NC}"
}

# 停止服务
stop() {
    echo -e "${YELLOW}正在停止服务...${NC}"
    docker-compose down
    echo -e "${GREEN}✓ 服务已停止${NC}"
}

# 重启服务
restart() {
    echo -e "${YELLOW}正在重启服务...${NC}"
    docker-compose restart
    sleep 5
    docker-compose ps
    echo -e "${GREEN}✓ 服务已重启${NC}"
}

# 查看状态
status() {
    echo -e "${YELLOW}服务状态：${NC}"
    docker-compose ps
}

# 查看日志
logs() {
    docker-compose logs -f backend
}

# 重新构建
rebuild() {
    echo -e "${YELLOW}正在重新构建 Docker 镜像...${NC}"
    docker-compose build --no-cache
    echo -e "${YELLOW}正在重启服务...${NC}"
    docker-compose up -d
    sleep 5
    docker-compose ps
    echo -e "${GREEN}✓ 服务已重新构建并启动${NC}"
}

# 清理服务（保留数据）
clean() {
    echo -e "${YELLOW}正在清理服务...${NC}"
    docker-compose down
    docker system prune -f
    echo -e "${GREEN}✓ 服务已清理（数据已保留）${NC}"
}

# 重置服务（删除所有数据）
reset() {
    echo -e "${RED}警告: 此操作将删除所有数据，包括数据库和图片！${NC}"
    read -p "确认继续？(yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "操作已取消"
        exit 0
    fi

    echo -e "${YELLOW}正在停止并删除服务...${NC}"
    docker-compose down -v

    echo -e "${YELLOW}正在删除数据卷...${NC}"
    docker volume rm mindcanvas_postgres_data 2>/dev/null || true
    docker volume rm mindcanvas_redis_data 2>/dev/null || true

    echo -e "${YELLOW}正在清理存储目录...${NC}"
    rm -rf storage/images/generated/*
    rm -rf storage/images/uploaded/*

    echo -e "${GREEN}✓ 服务已重置（所有数据已删除）${NC}"
    echo -e "${YELLOW}提示: 运行 './deploy.sh deploy' 重新部署服务${NC}"
}

# 注入邮箱配额
inject_quota() {
    if [ -z "$2" ] || [ -z "$3" ]; then
        echo "用法: ./deploy.sh quota <email> <quota>"
        echo "示例: ./deploy.sh quota test@example.com 10"
        exit 1
    fi

    check_env

    EMAIL=$2
    QUOTA=$3

    # 读取管理员密钥
    ADMIN_KEY=$(grep "ADMIN_SECRET_KEY" .env | cut -d '=' -f2)

    echo -e "${YELLOW}正在注入邮箱配额...${NC}"
    echo "  Email: $EMAIL"
    echo "  Quota: $QUOTA"

    # 通过 docker exec 调用管理服务
    docker-compose exec -T admin curl -s -X POST "http://localhost:8009/api/v1/admin/email-quota" \
        -H "admin-secret: $ADMIN_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"email\": \"$EMAIL\", \"quota\": $QUOTA}"

    echo ""
}

# 查询邮箱配额
list_quota() {
    check_env

    # 读取管理员密钥
    ADMIN_KEY=$(grep "ADMIN_SECRET_KEY" .env | cut -d '=' -f2)

    echo -e "${YELLOW}查询邮箱配额...${NC}"

    # 通过 docker exec 调用管理服务
    docker-compose exec -T admin curl -s -X GET "http://localhost:8009/api/v1/admin/email-quota" \
        -H "admin-secret: $ADMIN_KEY"

    echo ""
}

# 启动管理服务
start_admin() {
    check_env

    echo -e "${YELLOW}正在启动管理服务（Docker 容器）...${NC}"

    # 检查是否已经在运行
    if docker ps | grep -q mindcanvas_admin; then
        echo -e "${YELLOW}管理服务已在运行${NC}"
        return 0
    fi

    # 启动管理服务
    docker-compose up -d admin

    # 等待服务启动
    echo -e "${YELLOW}等待管理服务启动...${NC}"
    sleep 5

    # 检查服务状态
    if docker ps | grep -q mindcanvas_admin; then
        echo -e "${GREEN}✓ 管理服务已启动${NC}"
        echo -e "  容器名称: mindcanvas_admin"
        echo -e "  内部端口: 8009"
    else
        echo -e "${RED}✗ 管理服务启动失败${NC}"
        docker-compose logs admin
        exit 1
    fi
}

# 停止管理服务
stop_admin() {
    echo -e "${YELLOW}正在停止管理服务...${NC}"

    docker-compose stop admin
    echo -e "${GREEN}✓ 管理服务已停止${NC}"
}

# 显示成功信息
show_success() {
    echo ""
    echo "=========================================="
    echo -e "${GREEN}✓ 部署完成！${NC}"
    echo "=========================================="
    echo ""
    echo "服务地址："
    echo "  - 后端 API: http://localhost:8008"
    echo "  - API 文档: http://localhost:8008/docs"
    echo "  - 健康检查: http://localhost:8008/health"
    echo ""
    echo "常用命令："
    echo "  - 查看日志: ./deploy.sh logs"
    echo "  - 停止服务: ./deploy.sh stop"
    echo "  - 重启服务: ./deploy.sh restart"
    echo "  - 查看状态: ./deploy.sh status"
    echo "  - 注入配额: ./deploy.sh quota <email> <quota>"
    echo "  - 查询配额: ./deploy.sh list-quota"
    echo ""
    echo "=========================================="
}

# 主函数
main() {
    case "${1:-deploy}" in
        deploy)
            deploy
            ;;
        start)
            start
            ;;
        stop)
            stop
            ;;
        restart)
            restart
            ;;
        status)
            status
            ;;
        logs)
            logs
            ;;
        rebuild)
            rebuild
            ;;
        clean)
            clean
            ;;
        reset)
            reset
            ;;
        start-admin)
            start_admin
            ;;
        stop-admin)
            stop_admin
            ;;
        quota)
            inject_quota "$@"
            ;;
        list-quota)
            list_quota
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}错误: 未知命令 '$1'${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

main "$@"